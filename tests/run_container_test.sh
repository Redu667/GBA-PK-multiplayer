#!/bin/sh
# Container startup suite: runs the Dockerfile's real CMD (no Docker needed) to
# check process boot order and the DISCORD_*/WEBCHAT env wiring. Starts its own
# game server via that CMD, so nothing should be listening first.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
python3 tests/container_boot_test.py
RC=$?
echo "container boot test complete (rc=$RC)"
exit $RC
