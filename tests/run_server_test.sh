#!/bin/sh
# Run the main server integration suite against a fresh server in a clean
# working directory (the server persists accounts to its cwd, and the suite's
# nickname expectations assume no prior state).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/gbapk-srvtest"
rm -rf "$WORK"; mkdir -p "$WORK"
SRV=""
cleanup() { [ -n "$SRV" ] && kill -9 "$SRV" 2>/dev/null; }
trap cleanup EXIT INT TERM

cd "$WORK"
lua5.4 "$ROOT/server/GBA-PK-Server.lua" 4096 8 > server.log 2>&1 &
SRV=$!
sleep 1.2
grep -q "listening" server.log || { echo "ERROR: server failed to start (port busy?)"; cat server.log; exit 1; }
( cd "$ROOT" && lua5.4 tests/server_test.lua )
RC=$?
echo "server test complete (rc=$RC)"
exit $RC
