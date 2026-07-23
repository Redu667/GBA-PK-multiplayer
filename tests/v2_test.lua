-- v2.0.0 feature test: named channels, duel matchmaking, spoof rejection and
-- local-mode interaction gating. Run against a server with --local=2 (see
-- tests/run_v2_test.sh).
local socket = require("socket")
local FRAME = 64
local function fid(x) return string.format("%04d", 1000 + x) end
local function padded(text) return text .. string.rep("~", 43 - #text) end
local function frame(gameid, pid, sendto, ptype, reqbytes, extraTail)
  local extra = fid(reqbytes) .. string.rep("\0", 33) .. "F" .. "FFFFF"
  if extraTail then extra = extraTail end
  local f = gameid .. "FFFF" .. fid(pid) .. fid(sendto) .. ptype .. extra .. "U"
  assert(#f == FRAME)
  return f
end
local function posFrame(gameid, pid, sendto, ptype, reqbytes, map, prevmap)
  local extra = fid(reqbytes)
    .. string.rep("\0", 5)
    .. string.char(map % 256, math.floor(map / 256) % 256)
    .. string.char((prevmap or map) % 256, math.floor((prevmap or map) / 256) % 256)
    .. string.rep("\0", 24) .. "F" .. "FFFFF"
  local f = gameid .. "FFFF" .. fid(pid) .. fid(sendto) .. ptype .. extra .. "U"
  assert(#f == FRAME)
  return f
end
local function ftype(f) return f:sub(17,20) end
local function freqbytes(f) return (tonumber(f:sub(21,24)) or 1000) - 1000 end
local function fpid(f) return (tonumber(f:sub(9,12)) or 1000) - 1000 end
local function fpayload(f) return (f:sub(21,63):gsub("~*$","")) end

local function newClient()
  local c = assert(socket.connect("127.0.0.1", 4096))
  c:settimeout(0); c:setoption("tcp-nodelay", true)
  return { sock = c, buf = "", frames = {} }
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

print("== Setup: A and B in Kanto, same map ==")
local A = newClient()
A.sock:send(posFrame("BPR1", 0, 0, "JOIN", 0, 100))
pump(A, 0.5)
local aid = freqbytes(findType(A, "STRT"))
local B = newClient()
B.sock:send(posFrame("BPR1", 0, 0, "JOIN", 0, 100))
pump(B, 0.5); pump(A, 0.3)
local bid = freqbytes(findType(B, "STRT"))
check(aid and bid and aid ~= bid, "A and B joined")

print("== Channels: B moves to #alpha, A stops seeing B ==")
A.frames = {}; B.frames = {}
B.sock:send(frame("BPR1", bid, 0, "ROOM", 0, padded("alpha")))
pump(B, 0.5); pump(A, 0.3)
check(findType(B, "CHAT", function(f) return fpid(f) == 0 and fpayload(f):find("alpha") end) ~= nil, "B is told it moved to #alpha")
check(findType(A, "RPLA", function(f) return freqbytes(f) == bid end) ~= nil, "A stops seeing B (RPLA)")
A.frames = {}
B.sock:send(posFrame("BPR1", bid, bid, "SPOS", bid, 100))
pump(A, 0.3)
check(findType(A, "SPOS", function(f) return fpid(f) == bid end) == nil, "B's movement no longer reaches A")

print("== Channels: B returns to the main room ==")
A.frames = {}; B.frames = {}
B.sock:send(frame("BPR1", bid, 0, "ROOM", 0, padded("")))
pump(B, 0.5); pump(A, 0.3)
check(findType(A, "APLA", function(f) return freqbytes(f) == bid end) ~= nil, "A sees B again after B returns")

print("== Duel matchmaking ==")
A.frames = {}; B.frames = {}
A.sock:send(frame("BPR1", aid, 0, "DUEL", 0))
pump(A, 0.4)
check(findType(A, "CHAT", function(f) return fpid(f) == 0 and fpayload(f):find("ueue") end) ~= nil, "A is told it queued")
B.sock:send(frame("BPR1", bid, 0, "DUEL", 0))
pump(A, 0.4); pump(B, 0.3)
check(findType(A, "CHAT", function(f) return fpid(f) == 0 and fpayload(f):find("atched") end) ~= nil, "A gets a match notice")
check(findType(B, "CHAT", function(f) return fpid(f) == 0 and fpayload(f):find("atched") end) ~= nil, "B gets a match notice")

print("== Spoof rejection: frames claiming another id are dropped ==")
B.frames = {}
A.sock:send(posFrame("BPR1", 99, 99, "SPOS", 99, 100))   -- A pretends to be 99
pump(B, 0.4)
check(findType(B, "SPOS", function(f) return fpid(f) == 99 end) == nil, "spoofed SPOS is not relayed")
A.sock:send(posFrame("BPR1", aid, aid, "SPOS", aid, 100))
pump(B, 0.3)
check(findType(B, "SPOS", function(f) return fpid(f) == aid end) ~= nil, "A's honest SPOS still relays")

print("== Local-mode interaction gating ==")
-- C joins on a different map; the third join trips local mode (--local=2)
local C = newClient()
C.sock:send(posFrame("BPR1", 0, 0, "JOIN", 0, 200))
pump(C, 0.5)
local cid = freqbytes(findType(C, "STRT"))
C.frames = {}
C.sock:send(posFrame("BPR1", cid, aid, "TRAD", cid, 200))   -- same room, can't see A
pump(C, 0.4)
check(findType(C, "TBUS") ~= nil, "trading with someone you can't see returns TBUS")

print("== Kick after repeated spoofing ==")
B.frames = {}
for i = 1, 25 do A.sock:send(posFrame("BPR1", 99, 99, "SPOS", 99, 100)) end
pump(B, 1.0)
check(findType(B, "DISC", function(f) return freqbytes(f) == aid end) ~= nil, "A is kicked after repeated spoofed frames")

A.sock:close(); B.sock:close(); C.sock:close()
print(string.format("\n== RESULT: %d passed, %d failed ==", pass, fail))
os.exit(fail == 0 and 0 or 1)
