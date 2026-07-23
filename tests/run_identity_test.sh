#!/bin/sh
# Persistent-identity test: phase 1 claims a name, then the server is genuinely
# restarted (same working dir, so it reloads its accounts file from disk), and
# phase 2 verifies the name comes back and stays protected.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/gbapk-idtest"
rm -rf "$WORK"; mkdir -p "$WORK"
S1=""; S2=""
cleanup() { [ -n "$S1" ] && kill -9 "$S1" 2>/dev/null; [ -n "$S2" ] && kill -9 "$S2" 2>/dev/null; }
trap cleanup EXIT INT TERM

cd "$WORK"
lua5.4 "$ROOT/server/GBA-PK-Server.lua" 4096 8 > s1.log 2>&1 &
S1=$!
sleep 1.2
grep -q "listening" s1.log || { echo "ERROR: phase-1 server failed to start (port busy?)"; cat s1.log; exit 1; }
( cd "$ROOT" && lua5.4 tests/identity_test.lua phase1 "$WORK/tok.txt" )
P1=$?
kill -9 "$S1" 2>/dev/null; wait "$S1" 2>/dev/null; S1=""
sleep 0.5
[ "$P1" -eq 0 ] || { echo "phase1 failed"; exit 1; }
[ -s GBA-PK-Server.accounts ] || { echo "ERROR: accounts file not written"; exit 1; }

lua5.4 "$ROOT/server/GBA-PK-Server.lua" 4096 8 > s2.log 2>&1 &
S2=$!
sleep 1.2
grep -q "loaded 1 known player" s2.log || { echo "ERROR: restarted server did not load accounts"; cat s2.log; exit 1; }
( cd "$ROOT" && lua5.4 tests/identity_test.lua phase2 "$WORK/tok.txt" )
RC=$?
echo "identity test complete (rc=$RC)"
exit $RC
