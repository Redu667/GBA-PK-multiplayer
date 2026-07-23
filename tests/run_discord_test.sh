#!/bin/sh
# Discord-bridge suite: a local HTTP sink plays the Discord webhook; asserts
# game->Discord delivery, Discord->game delivery, and long-message splitting.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${TMPDIR:-/tmp}/gbapk-discordtest"
rm -rf "$WORK"; mkdir -p "$WORK"
SRV=""
cleanup() { [ -n "$SRV" ] && kill -9 "$SRV" 2>/dev/null; }
trap cleanup EXIT INT TERM
cd "$WORK"
lua5.4 "$ROOT/server/GBA-PK-Server.lua" 4096 16 > server.log 2>&1 &
SRV=$!
sleep 1.2
grep -q "listening" server.log || { echo "ERROR: server failed to start"; cat server.log; exit 1; }
( cd "$ROOT" && python3 tests/discord_bridge_test.py )
RC=$?
echo "discord bridge test complete (rc=$RC)"
exit $RC
