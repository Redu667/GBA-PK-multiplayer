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
local LocalThreshold = 7         -- room population above which map-local visibility kicks in
for _, a in ipairs(arg or {}) do
	if a == "-v" or a == "--verbose" then Verbose = true end
	local n = tostring(a):match("^%-%-local=(%d+)$")
	if n then LocalThreshold = tonumber(n) end
end

local FRAME = 64                 -- every packet is exactly this many bytes
local JOIN_GRACE   = 5           -- seconds a socket may sit connected without sending JOIN
local IDLE_TIMEOUT = 15          -- seconds without any data before a client (with peers) is dropped
local PING_INTERVAL = 5          -- seconds between server heartbeats to each client
local RATE_LIMIT   = 240         -- max frames per client per second (SPOS ~30/s; battles burst)
local RESERVE_SECONDS = 120      -- how long a dropped player's id is held for reconnect

math.randomseed(os.time())

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
-- Map ids ride in every position-format frame (ExtraData 10-11 current map,
-- 12-13 previous map, little-endian), so the server always knows where
-- everyone is without understanding the games' map graphs.
local function frameMap(f)      return (f:byte(30) or 0) | ((f:byte(31) or 0) << 8) end
local function framePrevMap(f)  return (f:byte(32) or 0) | ((f:byte(33) or 0) << 8) end
local function frameSendTo(f)   return (tonumber(f:sub(13, 16)) or 1000) - 1000 end
local function framePid(f)      return (tonumber(f:sub(9, 12)) or -1000) - 1000 end
local function framePayload(f)  return (f:sub(21, 63):gsub("~*$", "")) end
local function frameValid(f)    return #f == FRAME and f:sub(64, 64) == "U" end

-- Build a position-format frame with zeroed position data.
--   gameid: 4 chars   ptype: 4 chars   pid/sendto/reqbytes: numeric ids
--   flags: optional table { dedicated = true }
local function buildFrame(gameid, pid, sendto, ptype, reqbytes, flags)
	local extra = fid(reqbytes)                    -- ExtraData 1-4: RequestBytes
		.. string.rep("\0", 33)                    -- ExtraData 5-37: binary fields, zeroed
		.. ((flags and flags.dedicated) and "D" or "F")  -- ExtraData 38: dedicated-server flag
		.. ((flags and flags.token) or "FFFFF")    -- ExtraData 39-43: reconnect token (in STRT)
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

-- Region rooms: gameplay (positions, trades, battles, nicknames) is scoped to
-- your game family's room, because a FireRed map id means nothing in Emerald.
-- Chat and join/leave notices are shared across rooms, so one server still
-- feels like one world (the first stage of the multi-region plan in ROADMAP.md).
local function familyOf(gameid)
	local p = (gameid or ""):sub(1, 3)
	if p == "BPR" or p == "BPG" then return "Kanto" end
	if p == "AXV" or p == "AXP" or p == "BPE" then return "Hoenn" end
	return gameid or "?"           -- unknown/custom codes get their own room
end

local function findByID(id)
	for _, c in ipairs(clients) do if c.joined and c.id == id then return c end end
end

local function roomCount(room)
	local n = 0
	for _, c in ipairs(clients) do if c.joined and c.room == room then n = n + 1 end end
	return n
end

local function sendTo(c, f)
	local ok, err = c.sock:send(f)
	if not ok then vlog("send to #" .. tostring(c.id) .. " failed: " .. tostring(err)) end
	return ok
end

-- ---------------------------------------------------------------------------
-- Map-local visibility. Small lobbies (room population <= LocalThreshold) get
-- full visibility, exactly as before. Above that, players are only introduced
-- to — and synced with — others on the same map (or one they're transitioning
-- from, so border crossings don't flicker), removed again when they part ways,
-- and each client sees at most VIS_CAP others (the renderer has 8 slots).
-- This is what lets one server hold far more players than one screen can.
-- ---------------------------------------------------------------------------
local VIS_CAP = 8

local function visCount(viewer)
	local n = 0
	for _ in pairs(viewer.vis or {}) do n = n + 1 end
	return n
end

local function onSameMap(a, b)
	if a.map == b.map then return true end
	-- during a map transition the previous map keeps the pair linked briefly
	if a.posRaw and framePrevMap(a.posRaw) == b.map then return true end
	if b.posRaw and framePrevMap(b.posRaw) == a.map then return true end
	return false
end

-- Make `viewer` see (or stop seeing) `subject`, sending APLA/RPLA as needed.
local function setVisible(viewer, subject, on)
	viewer.vis = viewer.vis or {}
	if on and not viewer.vis[subject.id] then
		if visCount(viewer) >= VIS_CAP then return end
		viewer.vis[subject.id] = true
		sendTo(viewer, retype(subject.posRaw, "APLA", subject.id, subject.id, subject.id))
		if subject.nickRaw then sendTo(viewer, subject.nickRaw) end
	elseif not on and viewer.vis[subject.id] then
		viewer.vis[subject.id] = nil
		sendTo(viewer, buildFrame("SERV", 0, viewer.id, "RPLA", subject.id))
	end
end

-- Recompute who can see `c` (and whom `c` can see) after a join or map change.
local function updateVisibility(c)
	local localMode = roomCount(c.room) > LocalThreshold
	for _, o in ipairs(clients) do
		if o.joined and o ~= c and o.room == c.room then
			local should = (not localMode) or onSameMap(c, o)
			setVisible(o, c, should)
			setVisible(c, o, should)
		end
	end
end

-- A server chat line to ONE client (queue updates, match notices, ...).
local function noticeTo(c, text)
	text = text:gsub("[%c~]", " ")
	if #text > 43 then text = text:sub(1, 43) end
	sendTo(c, "SERV" .. "FFFF" .. fid(0) .. fid(c.id) .. "CHAT" .. text .. string.rep("~", 43 - #text) .. "U")
end

-- Named channels: players can split a region room into separate lobbies
-- ("Kanto#speedrun"). Moving rooms drops you from your old room's views and
-- introduces you in the new one.
local duelQueue = {}   -- room -> waiting client

local function moveRoom(c, newRoom)
	if c.room == newRoom then return end
	if duelQueue[c.room] == c then duelQueue[c.room] = nil end
	for _, o in ipairs(clients) do
		if o.joined and o ~= c and o.room ~= newRoom then
			setVisible(o, c, false)
			setVisible(c, o, false)
		end
	end
	c.room = newRoom
	updateVisibility(c)
end

local function joinedCount()
	local n = 0
	for _, c in ipairs(clients) do if c.joined then n = n + 1 end end
	return n
end

-- Persistent identity: token -> nickname, kept on disk so the server remembers
-- players across restarts. Your name is restored when you join, and a nickname
-- someone else owns is treated as taken even while they're offline.
local ACCOUNTS_FILE = "GBA-PK-Server.accounts"
local accounts = {}       -- token -> nick

local function loadAccounts()
	local fh = io.open(ACCOUNTS_FILE, "r")
	if not fh then return end
	local n = 0
	for line in fh:lines() do
		local token, nick = line:match("^(%w%w%w%w%w)\t(.+)$")
		if token and nick then accounts[token] = nick n = n + 1 end
	end
	fh:close()
	if n > 0 then log("loaded " .. n .. " known player(s) from " .. ACCOUNTS_FILE) end
end

local function saveAccounts()
	local fh = io.open(ACCOUNTS_FILE, "w")
	if not fh then log("warning: could not write " .. ACCOUNTS_FILE) return end
	for token, nick in pairs(accounts) do fh:write(token .. "\t" .. nick .. "\n") end
	fh:close()
end

local function nickOwnedByOther(nick, token)
	local base = nick:lower()
	for t, n in pairs(accounts) do
		if t ~= token and n:lower() == base then return true end
	end
	return false
end

-- Reconnect support: when a joined player drops, their id (and nickname) is
-- held under their token for RESERVE_SECONDS, so rejoining with that token
-- restores the same identity.
local reservations = {}   -- token -> { id, nick, expires }

local function purgeReservations()
	local now = socket.gettime()
	for token, r in pairs(reservations) do
		if r.expires < now then reservations[token] = nil end
	end
end

local function idReserved(id)
	for _, r in pairs(reservations) do
		if r.id == id then return true end
	end
	return false
end

local function freeID()
	purgeReservations()
	local id = 2                                  -- 1 is the in-game host slot; never used here
	while findByID(id) or idReserved(id) do id = id + 1 end
	return id
end

local TOKEN_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local function newToken()
	local t = {}
	for i = 1, 5 do
		local k = math.random(1, #TOKEN_CHARS)
		t[i] = TOKEN_CHARS:sub(k, k)
	end
	return table.concat(t)
end

-- Broadcast to every joined client, optionally only those in `room`.
local function broadcast(f, except, room)
	for _, c in ipairs(clients) do
		if c.joined and c ~= except and (not room or c.room == room) then sendTo(c, f) end
	end
end

-- Broadcast with the SendToID field rewritten to each recipient. Required for
-- frame types older clients don't know (CHAT/PING): those fall through their
-- handler chain, and an unknown frame addressed to someone else makes a v1.3.0
-- client reply TBUS — addressed to *them*, it's ignored silently instead.
local function broadcastAddressed(f, except, room)
	for _, c in ipairs(clients) do
		if c.joined and c ~= except and (not room or c.room == room) then
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
	if c.dropped then return end
	c.dropped = true
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
	for _, o in ipairs(clients) do
		if o.vis then o.vis[c.id] = nil end
	end
	if duelQueue[c.room] == c then duelQueue[c.room] = nil end
	if c.joined then
		-- hold their identity so a reconnect within the window restores it
		if c.token then
			reservations[c.token] = { id = c.id, nick = c.nick, expires = socket.gettime() + RESERVE_SECONDS }
		end
		notice((c.nick or ("Player " .. c.id)) .. " left  (" .. joinedCount() .. "/" .. MaxPlayers .. " online)")
	end
end

-- ---------------------------------------------------------------------------
-- Frame handling
-- ---------------------------------------------------------------------------
local function handleJoin(c, f)
	if c.joined then return end
	purgeReservations()

	-- Reconnect: a rejoining client carries its old token in the JOIN frame
	-- (ExtraData 38 = "R", 39-43 = token). Restore its identity if we can.
	local rejoined = false
	local token
	if f:sub(58, 58) == "R" then
		local presented = f:sub(59, 63)
		-- still-active session with that token? (client came back before we
		-- noticed the old socket die) -> replace the stale connection
		for _, other in ipairs(clients) do
			if other.joined and other ~= c and other.token == presented then
				-- If that connection is visibly alive (heartbeating within 4s), this
				-- is most likely a SECOND instance sharing the same identity file on
				-- one PC — give it a fresh identity instead of kicking the first.
				if (socket.gettime() - other.lastSeen) < 4 then
					vlog("token in use by a live connection; treating join from " .. c.addr .. " as a new player")
					break
				end
				broadcast(buildFrame("SERV", 0, 0, "DISC", other.id), other)
				pcall(function() other.sock:close() end)
				other.joined = false                     -- strip it; removed below
				for i, v in ipairs(clients) do
					if v == other then table.remove(clients, i) break end
				end
				for _, o in ipairs(clients) do
					if o.vis then o.vis[other.id] = nil end   -- forget the stale sighting
				end
				c.id, c.nick, token, rejoined = other.id, other.nick, presented, true
				vlog("player " .. c.id .. " replaced a stale connection")
				break
			end
		end
		local r = reservations[presented]
		if not rejoined and r then
			c.id, c.nick, token, rejoined = r.id, r.nick, presented, true
			reservations[presented] = nil
		end
		-- No live session or reservation, but a known account (e.g. the server
		-- restarted): keep the presented token as their identity so their name
		-- comes back. Unknown tokens still get a fresh identity.
		if not rejoined and not token and accounts[presented] then
			token = presented
		end
	end

	if not rejoined and joinedCount() >= MaxPlayers then
		log("refused join from " .. c.addr .. " (server full)")
		sendTo(c, buildFrame("SERV", 0, 0, "RFSE", 2))     -- 2 = player-limit message
		return
	end
	c.id     = c.id or freeID()
	c.token  = token or newToken()
	c.nick   = c.nick or accounts[c.token]     -- greet returning players by name
	c.gameid = f:sub(1, 4)
	c.baseRoom = familyOf(c.gameid) -- on a rejoin after a ROM swap this lands
	                                -- them in the new region's room ("travel")
	c.room   = c.baseRoom
	c.map    = frameMap(f)
	c.vis    = {}
	c.joined = true
	c.lastSeen = socket.gettime()
	-- The JOIN frame is position-format and carries the joiner's coordinates:
	-- retyped, it becomes their initial SPOS/APLA snapshot.
	c.posRaw = retype(f, "SPOS", c.id, c.id, c.id)

	-- STRT: "your id is <id>" + the dedicated-server flag (so the client
	-- doesn't add the server as a phantom host player) + the reconnect token.
	-- GameID is echoed so nothing trips a family check.
	sendTo(c, buildFrame(c.gameid, 0, c.id, "STRT", c.id, { dedicated = true, token = c.token }))
	-- GNIC: ask the newcomer for their nickname (they answer with NICK).
	sendTo(c, buildFrame(c.gameid, 0, c.id, "GNIC", c.id))

	-- Introduce players — same room only, and by map when the room is crowded.
	updateVisibility(c)
	local who = c.nick or ("Player " .. c.id)
	local verb = rejoined and "reconnected" or "joined"
	log("player " .. c.id .. " " .. verb .. " from " .. c.addr .. " (game " .. c.gameid ..
		", room " .. c.room .. ")  [" .. joinedCount() .. "/" .. MaxPlayers .. " online]")
	notice(who .. " " .. verb .. " " .. c.room .. "  (" .. joinedCount() .. "/" .. MaxPlayers .. " online)")
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

	-- Validation: after joining, every frame a client sends must carry its own
	-- player id — a frame claiming to be someone else is a spoof and is dropped.
	-- Repeated violations get the connection kicked.
	if c.joined and t ~= "JOIN" and framePid(f) ~= c.id then
		c.badFrames = (c.badFrames or 0) + 1
		vlog("spoofed frame from player " .. c.id .. " (claimed " .. framePid(f) .. "), dropped")
		if c.badFrames > 20 then dropClient(c, "repeated invalid frames") end
		return
	end

	if t == "JOIN" then
		handleJoin(c, f)
	elseif not c.joined then
		vlog("frame " .. t .. " from unjoined " .. c.addr .. " ignored")
	elseif t == "ROOM" then
		-- switch (or leave) a named channel within your region
		local ch = framePayload(f):lower():gsub("[^%w]", ""):sub(1, 10)
		local newRoom = (ch == "") and c.baseRoom or (c.baseRoom .. "#" .. ch)
		moveRoom(c, newRoom)
		noticeTo(c, (ch == "") and ("Back in " .. c.baseRoom .. ".") or ("Moved to channel " .. c.room .. "."))
		log("player " .. c.id .. " moved to room " .. c.room)
	elseif t == "DUEL" then
		-- battle matchmaking: first-come pairing within your room
		local q = duelQueue[c.room]
		if q == c then
			duelQueue[c.room] = nil
			noticeTo(c, "Left the duel queue.")
		elseif q and q.joined then
			duelQueue[c.room] = nil
			local qn = q.nick or ("Player " .. q.id)
			local cn = c.nick or ("Player " .. c.id)
			noticeTo(c, "Duel matched: " .. qn .. "! Find them and battle.")
			noticeTo(q, "Duel matched: " .. cn .. "! Find them and battle.")
			log("duel matched: " .. c.id .. " vs " .. q.id .. " in " .. c.room)
		else
			duelQueue[c.room] = c
			noticeTo(c, "Queued for a duel - waiting for a rival.")
		end
	elseif t == "TRAD" and framePayload(f) ~= "" and not tonumber(f:sub(21, 24)) then
		-- malformed trade stage fields: drop rather than desync the partner
		c.badFrames = (c.badFrames or 0) + 1
		vlog("malformed TRAD from player " .. c.id .. ", dropped")
	elseif t == "PING" then
		-- liveness only; lastSeen is already refreshed above
	elseif t == "WHOQ" then
		-- who's online: reply (to the asker only) with one WHOR per joined
		-- player, payload "room|name", then a lone "." as terminator. Only
		-- companions that know WHOQ ask, so old clients never see WHOR.
		for _, o in ipairs(clients) do
			if o.joined then
				local line = o.room .. "|" .. (o.nick or ("Player " .. o.id))
				if #line > 43 then line = line:sub(1, 43) end
				sendTo(c, "SERV" .. "FFFF" .. fid(0) .. fid(c.id) .. "WHOR" .. line .. string.rep("~", 43 - #line) .. "U")
			end
		end
		sendTo(c, "SERV" .. "FFFF" .. fid(0) .. fid(c.id) .. "WHOR" .. "." .. string.rep("~", 42) .. "U")
	elseif t == "CHAT" then
		-- Chat crosses rooms (one world socially). Same-room clients get the raw
		-- frame and resolve the name from their player list; other rooms can't,
		-- so the message is re-wrapped as a server line: "NAME (Room): text".
		broadcastAddressed(f, c, c.room)
		local wrapped = (c.nick or ("Player " .. c.id)) .. " (" .. c.room .. "): " .. f:sub(21, 63):gsub("~*$", "")
		if #wrapped > 43 then wrapped = wrapped:sub(1, 43) end
		local wf = "SERV" .. "FFFF" .. fid(0) .. fid(0) .. "CHAT" .. wrapped .. string.rep("~", 43 - #wrapped) .. "U"
		for _, other in ipairs(clients) do
			if other.joined and other ~= c and other.room ~= c.room then
				sendTo(other, wf:sub(1, 12) .. fid(other.id) .. wf:sub(17))
			end
		end
	elseif t == "SPOS" then
		c.posRaw = f
		local m, pm = frameMap(f), framePrevMap(f)
		if m ~= c.map or pm ~= c.pmap then
			c.map, c.pmap = m, pm
			updateVisibility(c)     -- entering a map introduces; settling severs
		end
		-- relay only to clients that can currently see this player
		for _, o in ipairs(clients) do
			if o.joined and o ~= c and o.room == c.room and o.vis and o.vis[c.id] then
				sendTo(o, f)
			end
		end
	elseif t == "NICK" then
		-- Presence: keep nicknames unique. If this name is already taken by another
		-- player, rewrite it to "NAME(id)" before caching/broadcasting, so everyone
		-- else can tell the two apart (the owner still sees their own name locally).
		local nick = f:sub(21, 63):gsub("~*$", "")
		local base = nick:lower()
		local taken = nickOwnedByOther(nick, c.token)
		if not taken then
			for _, other in ipairs(clients) do
				if other.joined and other ~= c and other.nick and other.nick:lower() == base then
					taken = true
					break
				end
			end
		end
		if taken then
			nick = nick:sub(1, 36) .. "(" .. c.id .. ")"
			local payload = nick .. string.rep("~", 43 - #nick)
			f = f:sub(1, 20) .. payload .. "U"
			vlog("nickname collision: player " .. c.id .. " -> " .. nick)
		end
		c.nick = nick
		c.nickRaw = f
		if not taken and accounts[c.token] ~= nick then
			accounts[c.token] = nick               -- first come, first owned
			saveAccounts()
		end
		broadcast(f, c, c.room)                       -- names resolve within the room
	else
		-- Targeted packet (trade/battle/Pokémon data/Soullocke/…): forward raw
		-- to its SendToID, exactly like the in-game host's relay. If the target
		-- is gone — or plays a different game family (cross-room trades/battles
		-- can't work) — answer TBUS ("too busy") so the attempt aborts cleanly.
		local target = findByID(frameSendTo(f))
		if target and target.room ~= c.room then target = nil end
		-- in map-local mode you can only interact with someone you can see
		if target and roomCount(c.room) > LocalThreshold and not (target.vis and target.vis[c.id]) then
			target = nil
		end
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
loadAccounts()
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
