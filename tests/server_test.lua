-- Integration test for GBA-PK-Server.lua using fake luasocket clients.
-- Run:  lua GBA-PK-Server.lua &   then   lua tests/server_test.lua
-- Covers the v1.3.0 relay behavior plus v1.4.0 chat/presence/heartbeat.
local socket = require("socket")
local FRAME = 64
local function fid(x) return string.format("%04d", 1000 + x) end
local function frame(gameid, pid, sendto, ptype, reqbytes, extraTail)
  local extra = fid(reqbytes) .. string.rep("\0", 33) .. "F" .. "FFFFF"
  if extraTail then extra = extraTail end
  local f = gameid .. "FFFF" .. fid(pid) .. fid(sendto) .. ptype .. extra .. "U"
  assert(#f == FRAME, "built frame len " .. #f)
  return f
end
local function padded(text) return text .. string.rep("~", 43 - #text) end
local function ftype(f) return f:sub(17,20) end
local function freqbytes(f) return (tonumber(f:sub(21,24)) or 1000) - 1000 end
local function fpid(f) return (tonumber(f:sub(9,12)) or 1000) - 1000 end
local function fsendto(f) return (tonumber(f:sub(13,16)) or 1000) - 1000 end
local function fpayload(f) return (f:sub(21,63):gsub("~*$","")) end
local function fdedicated(f) return f:sub(21+37, 21+37) == "D" end

local function newClient(gameid)
  local c = assert(socket.connect("127.0.0.1", 4096))
  c:settimeout(0); c:setoption("tcp-nodelay", true)
  return { sock = c, buf = "", frames = {}, gameid = gameid }
end
local function pump(c, seconds)
  local deadline = socket.gettime() + (seconds or 0.4)
  while socket.gettime() < deadline do
    local d, err, part = c.sock:receive(65536)
    local chunk = d or part
    if chunk and #chunk > 0 then
      c.buf = c.buf .. chunk
      while #c.buf >= FRAME do
        c.frames[#c.frames+1] = c.buf:sub(1, FRAME)
        c.buf = c.buf:sub(FRAME+1)
      end
    end
    socket.sleep(0.01)
  end
end
local function findType(c, ty, pred)
  for _, f in ipairs(c.frames) do
    if ftype(f) == ty and (not pred or pred(f)) then return f end
  end
end

local pass, fail = 0, 0
local function check(cond, msg)
  if cond then pass = pass + 1; print("  PASS " .. msg)
  else fail = fail + 1; print("  FAIL " .. msg) end
end

print("== Client A joins ==")
local A = newClient("BPR1")
A.sock:send(frame("BPR1", 0, 0, "JOIN", 0))
pump(A, 0.5)
local strt = findType(A, "STRT")
check(strt ~= nil, "A receives STRT")
check(strt and fdedicated(strt), "STRT carries the dedicated-server flag (D)")
check(strt and freqbytes(strt) == 2, "A is assigned player id 2")
local tokA = strt and strt:sub(59, 63)
check(tokA and tokA ~= "FFFFF", "STRT carries a reconnect token [" .. tostring(tokA) .. "]")
check(findType(A, "GNIC") ~= nil, "A receives GNIC (server asks for nickname)")

print("== Client B joins; A gets an APLA and a join notice ==")
A.frames = {}
local B = newClient("BPR1")
B.sock:send(frame("BPR1", 0, 0, "JOIN", 0))
pump(B, 0.5); pump(A, 0.4)
local strtB = findType(B, "STRT")
check(strtB and freqbytes(strtB) == 3, "B is assigned player id 3")
check(findType(B, "APLA") ~= nil, "B is introduced to A via APLA")
local aplaOnA = findType(A, "APLA")
check(aplaOnA and freqbytes(aplaOnA) == 3, "A is introduced to B via APLA")
local joinNote = findType(A, "CHAT", function(f) return fpid(f) == 0 end)
check(joinNote ~= nil, "A receives a server join notice (CHAT from id 0)")
check(joinNote and fpayload(joinNote):find("joined") ~= nil, "the notice says someone joined")

print("== Nickname presence: dedupe on collision ==")
A.sock:send(frame("BPR1", 2, 0, "NICK", 0, padded("DUDE")))
pump(B, 0.4)
local nickA = findType(B, "NICK")
check(nickA and fpayload(nickA) == "DUDE", "B sees A's nickname DUDE")
B.frames = {}; A.frames = {}
B.sock:send(frame("BPR1", 3, 0, "NICK", 0, padded("DUDE")))
pump(A, 0.4)
local nickB = findType(A, "NICK")
check(nickB and fpayload(nickB) == "DUDE(3)", "duplicate nickname is deduped to DUDE(3) [got " .. tostring(nickB and fpayload(nickB)) .. "]")

print("== Reconnect: replace a stale connection ==")
B.frames = {}
-- The server refuses to kick a connection that heartbeated within the last 4s
-- (that's how two instances sharing one identity file on a PC are told apart
-- from a genuine reconnect). Let A's connection go silent past that window
-- first, like a real dropped client would be.
socket.sleep(4.5)
local A2 = newClient("BPR1")
A2.sock:send(frame("BPR1", 0, 0, "JOIN", 0, fid(0) .. string.rep("\0", 33) .. "R" .. tokA))
pump(A2, 0.6); pump(B, 0.4)
local strtA2 = findType(A2, "STRT")
check(strtA2 and freqbytes(strtA2) == 2, "rejoining with the token restores player id 2 [got " .. tostring(strtA2 and freqbytes(strtA2)) .. "]")
check(strtA2 and strtA2:sub(59, 63) == tokA, "the same token is confirmed back")
check(findType(B, "DISC", function(f) return freqbytes(f) == 2 end) ~= nil, "B is told the stale player 2 left")
check(findType(B, "APLA", function(f) return freqbytes(f) == 2 end) ~= nil, "B is re-introduced to the rejoined player 2")
local reNote = findType(B, "CHAT", function(f) return fpid(f) == 0 and fpayload(f):find("reconnected") end)
check(reNote ~= nil, "B sees a reconnect notice: " .. tostring(reNote and fpayload(reNote)))
A = A2

print("== Reconnect: drop, then rejoin inside the reservation window ==")
A.sock:close()
pump(B, 1.2)   -- server notices the close, reserves id 2
check(findType(B, "DISC", function(f) return freqbytes(f) == 2 end) ~= nil, "B is told player 2 dropped")
B.frames = {}
local A3 = newClient("BPR1")
A3.sock:send(frame("BPR1", 0, 0, "JOIN", 0, fid(0) .. string.rep("\0", 33) .. "R" .. tokA))
pump(A3, 0.6); pump(B, 0.4)
local strtA3 = findType(A3, "STRT")
check(strtA3 and freqbytes(strtA3) == 2, "rejoin within the window restores id 2 from the reservation")
check(findType(B, "APLA", function(f) return freqbytes(f) == 2 end) ~= nil, "B is re-introduced after the reservation rejoin")
A = A3

print("== Reconnect: a bogus token gets a fresh id ==")
local C = newClient("BPR1")
C.sock:send(frame("BPR1", 0, 0, "JOIN", 0, fid(0) .. string.rep("\0", 33) .. "R" .. "ZZZZZ"))
pump(C, 0.6)
local strtC = findType(C, "STRT")
check(strtC and freqbytes(strtC) == 4, "unknown token falls back to a fresh id [got " .. tostring(strtC and freqbytes(strtC)) .. "]")
C.sock:close()
pump(A, 0.8); A.frames = {}; pump(B, 0.8); B.frames = {}

print("== Chat relay ==")
A.frames = {}; B.frames = {}
A.sock:send(frame("BPR1", 2, 0, "CHAT", 0, padded("hello world")))
pump(B, 0.4); pump(A, 0.2)
local chatOnB = findType(B, "CHAT", function(f) return fpid(f) == 2 end)
check(chatOnB ~= nil, "B receives A's chat message")
check(chatOnB and fpayload(chatOnB) == "hello world", "chat text arrives intact")
check(chatOnB and fsendto(chatOnB) == 3, "chat is re-addressed to the recipient (SendToID=3)")
check(findType(A, "CHAT", function(f) return fpid(f) == 2 end) == nil, "A gets no echo of their own chat")

print("== Heartbeat: client PING absorbed; server PINGs on its own ==")
A.frames = {}
A.sock:send(frame("BPR1", 2, 0, "PING", 0))
B.sock:send(frame("BPR1", 3, 0, "PING", 0))   -- keep B alive through the 6s wait (real clients heartbeat)
pump(A, 0.4)
check(findType(A, "TBUS") == nil, "client PING does not bounce back as TBUS")
pump(A, 6.0)
local ping = findType(A, "PING")
check(ping ~= nil, "server sends its own PING heartbeat")
check(ping and fsendto(ping) == 2, "server PING is addressed to the recipient")

print("== SPOS relay ==")
A.frames = {}; B.frames = {}
B.sock:send(frame("BPR1", 3, 3, "SPOS", 3))
pump(A, 0.4); pump(B, 0.2)
local sposOnA = findType(A, "SPOS")
check(sposOnA and fpid(sposOnA) == 3, "A receives B's SPOS (relayed, from player 3)")
check(findType(B, "SPOS") == nil, "B does not receive its own SPOS back")

print("== Targeted relay + TBUS ==")
A.frames = {}; B.frames = {}
B.sock:send(frame("BPR1", 3, 2, "TRAD", 3))
pump(A, 0.4)
check(findType(A, "TRAD") ~= nil, "targeted TRAD from B reaches A")
B.sock:send(frame("BPR1", 3, 99, "TRAD", 3))
pump(B, 0.4)
check(findType(B, "TBUS") ~= nil, "targeting a missing player returns TBUS")

print("== Region rooms: a Hoenn player is isolated from Kanto gameplay ==")
A.frames = {}; B.frames = {}
local H = newClient("BPEE")
H.sock:send(frame("BPEE", 0, 0, "JOIN", 0))
pump(H, 0.6); pump(A, 0.4)
local strtH = findType(H, "STRT")
check(strtH ~= nil, "Hoenn client joins and receives STRT")
local hid = strtH and freqbytes(strtH)
check(findType(H, "APLA") == nil, "Hoenn client is NOT introduced to the Kanto players")
check(findType(A, "APLA", function(f) return freqbytes(f) == hid end) == nil, "Kanto players are NOT introduced to the Hoenn player")
local hoennNote = findType(A, "CHAT", function(f) return fpid(f) == 0 and fpayload(f):find("Hoenn") end)
check(hoennNote ~= nil, "the join notice names the region: " .. tostring(hoennNote and fpayload(hoennNote)))

print("== Region rooms: gameplay stays in-room, chat crosses ==")
A.frames = {}
H.sock:send(frame("BPEE", hid or 0, hid or 0, "SPOS", hid or 0))
pump(A, 0.4)
check(findType(A, "SPOS", function(f) return fpid(f) == hid end) == nil, "Hoenn SPOS does not reach Kanto")
H.frames = {}
H.sock:send(frame("BPEE", hid or 0, 2, "TRAD", hid or 0))
pump(H, 0.4)
check(findType(H, "TBUS") ~= nil, "a cross-region trade attempt is rejected with TBUS")
A.frames = {}
H.sock:send(frame("BPEE", hid or 0, 0, "CHAT", 0, padded("hi from hoenn")))
pump(A, 0.4)
local xchat = findType(A, "CHAT", function(f) return fpid(f) == 0 and fpayload(f):find("hi from hoenn") end)
check(xchat ~= nil, "cross-region chat arrives, server-wrapped")
check(xchat and fpayload(xchat):find("Hoenn") ~= nil, "the wrap names the sender's region: " .. tostring(xchat and fpayload(xchat)))
H.sock:close()
pump(A, 1.0); A.frames = {}

print("== Disconnect: DISC + leave notice ==")
A.frames = {}
B.sock:close()
pump(A, 1.2)
local disc = findType(A, "DISC")
check(disc and freqbytes(disc) == 3, "A is told B (player 3) left via DISC")
local leaveNote = findType(A, "CHAT", function(f) return fpid(f) == 0 end)
check(leaveNote and fpayload(leaveNote):find("left") ~= nil, "A receives a leave notice: " .. tostring(leaveNote and fpayload(leaveNote)))

A.sock:close()
print(string.format("\n== RESULT: %d passed, %d failed ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
