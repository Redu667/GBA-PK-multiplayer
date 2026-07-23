-- Persistent-identity test for GBA-PK-Server.lua. Run in two phases with a
-- server restart in between (see tests/run_identity_test.sh):
--   lua tests/identity_test.lua phase1 /tmp/tok.txt   -- claim a name, save token
--   <restart the server, keeping its accounts file>
--   lua tests/identity_test.lua phase2 /tmp/tok.txt   -- name restored + protected
local socket = require("socket")
local FRAME = 64
local phase = arg[1] or "phase1"
local tokfile = arg[2] or "/tmp/gbapk_tok.txt"

local function fid(x) return string.format("%04d", 1000 + x) end
local function frame(gameid, pid, sendto, ptype, reqbytes, extraTail)
  local extra = fid(reqbytes) .. string.rep("\0", 33) .. "F" .. "FFFFF"
  if extraTail then extra = extraTail end
  local f = gameid .. "FFFF" .. fid(pid) .. fid(sendto) .. ptype .. extra .. "U"
  assert(#f == FRAME)
  return f
end
local function padded(text) return text .. string.rep("~", 43 - #text) end
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

if phase == "phase1" then
  print("== Phase 1: claim a name; ownership holds while offline ==")
  local A = newClient()
  A.sock:send(frame("BPR1", 0, 0, "JOIN", 0))
  pump(A, 0.5)
  local strt = findType(A, "STRT")
  check(strt ~= nil, "A joins")
  local tok = strt and strt:sub(59, 63)
  check(tok and tok ~= "FFFFF", "A got a token")
  local aid = strt and freqbytes(strt)
  A.sock:send(frame("BPR1", aid, 0, "NICK", 0, padded("RED")))
  socket.sleep(0.3)

  local B = newClient()
  B.sock:send(frame("BPR1", 0, 0, "JOIN", 0))
  pump(B, 0.5)
  local bid = freqbytes(findType(B, "STRT") or frame("BPR1",0,0,"STRT",0))
  A.frames = {}
  B.sock:send(frame("BPR1", bid, 0, "NICK", 0, padded("RED")))
  pump(A, 0.4)
  local n1 = findType(A, "NICK")
  check(n1 and fpayload(n1) ~= "RED", "RED is taken while A is online [B became " .. tostring(n1 and fpayload(n1)) .. "]")

  A.sock:close()
  socket.sleep(0.8)                        -- server notices A left
  B.frames = {}
  B.sock:send(frame("BPR1", bid, 0, "NICK", 0, padded("RED")))
  socket.sleep(0.4)
  local C = newClient()
  C.sock:send(frame("BPR1", 0, 0, "JOIN", 0))
  pump(C, 0.5)
  local nOnC = findType(C, "NICK", function(f) return fpid(f) == bid end)
  check(nOnC and fpayload(nOnC) ~= "RED", "RED stays owned by A even offline [B shows as " .. tostring(nOnC and fpayload(nOnC)) .. "]")
  B.sock:close(); C.sock:close()

  local fh = assert(io.open(tokfile, "w"))
  fh:write(tok .. "\n")
  fh:close()
  print(string.format("phase1: %d passed, %d failed (token %s saved)", pass, fail, tok))
  os.exit(fail == 0 and 0 or 1)
end

if phase == "phase2" then
  print("== Phase 2 (after server restart): name restored from disk ==")
  local fh = assert(io.open(tokfile, "r"))
  local tok = fh:read("*l")
  fh:close()

  local X = newClient()                    -- bystander, joins first to hear notices
  X.sock:send(frame("BPR1", 0, 0, "JOIN", 0))
  pump(X, 0.5)
  check(findType(X, "STRT") ~= nil, "bystander joins the restarted server")

  X.frames = {}
  local A = newClient()
  A.sock:send(frame("BPR1", 0, 0, "JOIN", 0, fid(0) .. string.rep("\0", 33) .. "R" .. tok))
  pump(A, 0.6); pump(X, 0.4)
  check(findType(A, "STRT") ~= nil, "A rejoins with the old token")
  local note = findType(X, "CHAT", function(f) return fpid(f) == 0 and fpayload(f):find("RED") end)
  check(note ~= nil, "the restarted server greets A by name: " .. tostring(note and fpayload(note)))

  local xid = freqbytes(findType(X, "APLA") or frame("BPR1",0,0,"APLA",0))
  X.sock:send(frame("BPR1", 2, 0, "NICK", 0, padded("RED")))
  pump(A, 0.5)
  local n = findType(A, "NICK")
  check(n and fpayload(n) ~= "RED", "RED is still protected after the restart [bystander became " .. tostring(n and fpayload(n)) .. "]")

  A.sock:close(); X.sock:close()
  print(string.format("phase2: %d passed, %d failed", pass, fail))
  os.exit(fail == 0 and 0 or 1)
end
