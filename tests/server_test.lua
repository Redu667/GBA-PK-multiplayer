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
