#!/usr/bin/env lua
-- ============================================================================
-- GBA-PK dedicated server
--
-- A standalone, headless relay server for GBA-PK multiplayer. Run it on a VPS,
-- a spare PC or a Raspberry Pi — no emulator or ROM needed — and every player
-- simply uses "Join" to connect to it. Nobody has to host from inside their
-- game anymore.
--
--   Requirements:  Lua 5.3/5.4 (or 5.1/LuaJIT) + luasocket
--                    Debian/Ubuntu:  sudo apt install lua5.4 lua-socket
--                    Windows:        install Lua + luasocket via luarocks,
--                                    or run it under WSL
--   Run:           lua GBA-PK-Server.lua [port] [maxplayers]
--                    defaults: port 4096, maxplayers 8
--
-- Protocol: the same 64-byte frames the mod already speaks. The server plays
-- the host's relay role — assigns player IDs, exchanges the join handshake
-- (STRT/GNIC/NICK/APLA), relays position (SPOS) and targeted trade/battle/
-- Soullocke packets, and announces disconnects (DISC) — but it is NOT a
-- player: it marks its STRT with a "dedicated" flag so clients don't add a
-- phantom host player. Player IDs start at 2 (ID 1 is the in-game host slot,
-- which doesn't exist here).
-- ============================================================================

local socket = require("socket")

local Port       = tonumber(arg and arg[1]) or 4096
local MaxPlayers = tonumber(arg and arg[2]) or 8
local Verbose    = false
for _, a in ipairs(arg or {}) do if a == "-v" or a == "--verbose" then Verbose = true end end

local FRAME = 64                 -- every packet is exactly this many bytes
local JOIN_GRACE   = 5           -- seconds a socket may sit connected without sending JOIN
local IDLE_TIMEOUT = 15          -- seconds without any data before a client (with peers) is dropped
local PING_INTERVAL = 5          -- seconds between server heartbeats to each client
local RATE_LIMIT   = 240         -- max frames per client per second (SPOS ~30/s; battles burst)

local function log(msg)  print(os.date("[%H:%M:%S] ") .. msg) end
local function vlog(msg) if Verbose then log(msg) end end

-- ---------------------------------------------------------------------------
-- Frame helpers. Layout (1-indexed):
--   1-4 GameID | 5-8 "FFFF" | 9-12 PlayerID+1000 | 13-16 SendToID+1000
--   17-20 Type | 21-63 ExtraData (43 bytes; ExtraData[1-4] = RequestBytes+1000)
--   64 "U" validator
-- ---------------------------------------------------------------------------
local function fid(n) return string.format("%04d", 1000 + n) end

local function frameType(f)     return f:sub(17, 20) end
local function frameSendTo(f)   return (tonumber(f:sub(13, 16)) or 1000) - 1000 end
local function frameValid(f)    return #f == FRAME and f:sub(64, 64) == "U" end

-- Build a position-format frame with zeroed position data.
--   gameid: 4 chars   ptype: 4 chars   pid/sendto/reqbytes: numeric ids
--   flags: optional table { dedicated = true }
local function buildFrame(gameid, pid, sendto, ptype, reqbytes, flags)
	local extra = fid(reqbytes)                    -- ExtraData 1-4: RequestBytes
		.. string.rep("\0", 33)                    -- ExtraData 5-37: binary fields, zeroed
		.. ((flags and flags.dedicated) and "D" or "F")  -- ExtraData 38: dedicated-server flag
		.. "FFFFF"                                 -- ExtraData 39-43: filler
	local f = gameid .. "FFFF" .. fid(pid) .. fid(sendto) .. ptype .. extra .. "U"
	assert(#f == FRAME)
	return f
end

-- Rewrite pieces of an existing frame (used to retype a cached frame).
local function retype(f, ptype, pid, sendto, reqbytes)
	return f:sub(1, 8) .. fid(pid) .. fid(sendto) .. ptype .. fid(reqbytes) .. f:sub(25)
end

-- ---------------------------------------------------------------------------
-- Client registry
-- ---------------------------------------------------------------------------
local clients = {}   -- list of { sock, buf, id, gameid, joined, lastSeen, born, posRaw, nickRaw, addr }

local function findByID(id)
	for _, c in ipairs(clients) do if c.joined and c.id == id then return c end end
end

local function joinedCount()
	local n = 0
	for _, c in ipairs(clients) do if c.joined then n = n + 1 end end
	return n
end

local function freeID()
	local id = 2                                  -- 1 is the in-game host slot; never used here
	while findByID(id) do id = id + 1 end
	return id
end

local function sendTo(c, f)
	local ok, err = c.sock:send(f)
	if not ok then vlog("send to #" .. tostring(c.id) .. " failed: " .. tostring(err)) end
	return ok
end

local function broadcast(f, except)
	for _, c in ipairs(clients) do
		if c.joined and c ~= except then sendTo(c, f) end
	end
end

-- Broadcast with the SendToID field rewritten to each recipient. Required for
-- frame types older clients don't know (CHAT/PING): those fall through their
-- handler chain, and an unknown frame addressed to someone else makes a v1.3.0
-- client reply TBUS — addressed to *them*, it's ignored silently instead.
local function broadcastAddressed(f, except)
	for _, c in ipairs(clients) do
		if c.joined and c ~= except then
			sendTo(c, f:sub(1, 12) .. fid(c.id) .. f:sub(17))
		end
	end
end

-- Server-originated chat line (sender id 0 -> clients display "[server]").
local function notice(text)
	text = text:gsub("[%c~]", " ")
	if #text > 43 then text = text:sub(1, 43) end
	local payload = text .. string.rep("~", 43 - #text)
	local f = "SERV" .. "FFFF" .. fid(0) .. fid(0) .. "CHAT" .. payload .. "U"
	broadcastAddressed(f)
	log("[notice] " .. text)
end

local function dropClient(c, reason)
	if c.joined then
		log("player " .. c.id .. " (" .. c.addr .. ") left: " .. reason ..
			"  [" .. (joinedCount() - 1) .. "/" .. MaxPlayers .. " online]")
		-- position-format DISC; clients only read RequestBytes (the dropped id)
		broadcast(buildFrame("SERV", 0, 0, "DISC", c.id), c)
	else
		vlog("unjoined socket from " .. c.addr .. " dropped: " .. reason)
	end
	pcall(function() c.sock:close() end)
	for i, v in ipairs(clients) do
		if v == c then table.remove(clients, i) break end
	end
	if c.joined then
		notice((c.nick or ("Player " .. c.id)) .. " left  (" .. joinedCount() .. "/" .. MaxPlayers .. " online)")
	end
end

-- ---------------------------------------------------------------------------
-- Frame handling
-- ---------------------------------------------------------------------------
local function handleJoin(c, f)
	if c.joined then return end
	if joinedCount() >= MaxPlayers then
		log("refused join from " .. c.addr .. " (server full)")
		sendTo(c, buildFrame("SERV", 0, 0, "RFSE", 2))     -- 2 = player-limit message
		return
	end
	c.id     = freeID()
	c.gameid = f:sub(1, 4)
	c.joined = true
	c.lastSeen = socket.gettime()
	-- The JOIN frame is position-format and carries the joiner's coordinates:
	-- retyped, it becomes their initial SPOS/APLA snapshot.
	c.posRaw = retype(f, "SPOS", c.id, c.id, c.id)

	-- STRT: "your id is <id>" + the dedicated-server flag (so the client
	-- doesn't add the server as a phantom host player). GameID is echoed so
	-- nothing trips a family check.
	sendTo(c, buildFrame(c.gameid, 0, c.id, "STRT", c.id, { dedicated = true }))
	-- GNIC: ask the newcomer for their nickname (they answer with NICK).
	sendTo(c, buildFrame(c.gameid, 0, c.id, "GNIC", c.id))

	-- Introduce everyone to everyone.
	for _, other in ipairs(clients) do
		if other.joined and other ~= c then
			sendTo(c, retype(other.posRaw, "APLA", other.id, other.id, other.id))
			if other.nickRaw then sendTo(c, other.nickRaw) end
			sendTo(other, retype(c.posRaw, "APLA", c.id, c.id, c.id))
		end
	end
	log("player " .. c.id .. " joined from " .. c.addr .. " (game " .. c.gameid .. ")" ..
		"  [" .. joinedCount() .. "/" .. MaxPlayers .. " online]")
	notice("Player " .. c.id .. " joined  (" .. joinedCount() .. "/" .. MaxPlayers .. " online)")
end

local function handleFrame(c, f)
	if not frameValid(f) then
		vlog("invalid frame from " .. c.addr .. " (len " .. #f .. "), ignoring")
		return
	end
	local t = frameType(f)
	c.lastSeen = socket.gettime()

	-- Per-client rate limit: drop the excess instead of letting one broken or
	-- malicious client flood everyone else.
	local sec = math.floor(c.lastSeen)
	if c.rateSec ~= sec then c.rateSec, c.rateCount, c.rateWarned = sec, 0, false end
	c.rateCount = c.rateCount + 1
	if c.rateCount > RATE_LIMIT then
		if not c.rateWarned then
			c.rateWarned = true
			log("rate limit: player " .. tostring(c.id) .. " (" .. c.addr .. ") exceeded " ..
				RATE_LIMIT .. " frames/s; dropping the excess")
		end
		return
	end

	if t == "JOIN" then
		handleJoin(c, f)
	elseif not c.joined then
		vlog("frame " .. t .. " from unjoined " .. c.addr .. " ignored")
	elseif t == "PING" then
		-- liveness only; lastSeen is already refreshed above
	elseif t == "CHAT" then
		broadcastAddressed(f, c)                      -- everyone else sees the message
	elseif t == "SPOS" then
		c.posRaw = f
		broadcast(f, c)                               -- same relay the in-game host does
	elseif t == "NICK" then
		-- Presence: keep nicknames unique. If this name is already taken by another
		-- player, rewrite it to "NAME(id)" before caching/broadcasting, so everyone
		-- else can tell the two apart (the owner still sees their own name locally).
		local nick = f:sub(21, 63):gsub("~*$", "")
		local base = nick:lower()
		for _, other in ipairs(clients) do
			if other.joined and other ~= c and other.nick and other.nick:lower() == base then
				nick = nick:sub(1, 36) .. "(" .. c.id .. ")"
				local payload = nick .. string.rep("~", 43 - #nick)
				f = f:sub(1, 20) .. payload .. "U"
				vlog("nickname collision: player " .. c.id .. " -> " .. nick)
				break
			end
		end
		c.nick = nick
		c.nickRaw = f
		broadcast(f, c)                               -- names always go to everyone
	else
		-- Targeted packet (trade/battle/Pokémon data/Soullocke/…): forward raw
		-- to its SendToID, exactly like the in-game host's relay. If the target
		-- is gone, answer TBUS ("too busy") so trades/battles abort cleanly.
		local target = findByID(frameSendTo(f))
		if target then
			sendTo(target, f)
			vlog("relay " .. t .. " " .. c.id .. " -> " .. target.id)
		else
			sendTo(c, buildFrame("SERV", 0, c.id, "TBUS", c.id))
			vlog(t .. " from " .. c.id .. " to missing player " .. frameSendTo(f) .. " -> TBUS")
		end
	end
end

-- ---------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------
local server = assert(socket.bind("*", Port), "could not bind port " .. Port)
server:settimeout(0)
log("GBA-PK dedicated server listening on port " .. Port ..
	" (max " .. MaxPlayers .. " players). Players: menu > Set IP > this machine's address, then Join.")

while true do
	-- accept new connections
	while true do
		local s = server:accept()
		if not s then break end
		s:settimeout(0)
		s:setoption("tcp-nodelay", true)
		local ip, port = s:getpeername()
		local addr = tostring(ip) .. ":" .. tostring(port)
		table.insert(clients, { sock = s, buf = "", joined = false, addr = addr,
			born = socket.gettime(), lastSeen = socket.gettime() })
		vlog("connection from " .. addr)
	end

	-- read from everyone; reassemble 64-byte frames from the TCP stream
	local now = socket.gettime()
	for i = #clients, 1, -1 do
		local c = clients[i]
		local data, err, partial = c.sock:receive(65536)
		local chunk = data or partial
		if chunk and #chunk > 0 then
			c.buf = c.buf .. chunk
			while #c.buf >= FRAME do
				local f = c.buf:sub(1, FRAME)
				c.buf = c.buf:sub(FRAME + 1)
				handleFrame(c, f)
			end
		end
		if err == "closed" then
			dropClient(c, "connection closed")
		elseif not c.joined and (now - c.born) > JOIN_GRACE then
			dropClient(c, "never joined")
		elseif c.joined and joinedCount() >= 2 and (now - c.lastSeen) > IDLE_TIMEOUT then
			-- clients only send traffic when they have peers, so only enforce
			-- liveness when peers exist (a lone player idles silently by design;
			-- v1.4.0+ clients also heartbeat with PING, which refreshes lastSeen)
			dropClient(c, "timed out")
		elseif c.joined and (now - (c.lastPing or 0)) > PING_INTERVAL then
			-- heartbeat so clients can tell the server is alive even when idle.
			-- Addressed to the recipient so pre-1.4.0 clients ignore it silently.
			c.lastPing = now
			sendTo(c, buildFrame(c.gameid, 0, c.id, "PING", c.id))
		end
	end

	socket.sleep(0.015)   -- ~66 ticks/s; plenty for a relay
end
