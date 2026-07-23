#!/bin/sh
# Map-local visibility suite: server runs with --local=2 so three same-room
# clients trip local mode.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/gbapk-v2test"
rm -rf "$WORK"; mkdir -p "$WORK"
SRV=""
cleanup() { [ -n "$SRV" ] && kill -9 "$SRV" 2>/dev/null; }
trap cleanup EXIT INT TERM
cd "$WORK"
lua5.4 "$ROOT/GBA-PK-Server.lua" 4096 16 --local=2 > server.log 2>&1 &
SRV=$!
sleep 1.2
grep -q "listening" server.log || { echo "ERROR: server failed to start"; cat server.log; exit 1; }
( cd "$ROOT" && lua5.4 tests/v2_test.lua )
RC=$?
echo "v2 test complete (rc=$RC)"
exit $RC
