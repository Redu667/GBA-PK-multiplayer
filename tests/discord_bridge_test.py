#!/usr/bin/env python3
"""Discord-bridge integration test (webhook mode, no real Discord needed).

A local HTTP server stands in for the Discord webhook; a fake in-game client
joins Kanto and chats; the bridge must POST that line (room-attributed) to the
webhook. Then the bridge's send_chat() path is exercised the other way: the
fake client must receive it as server-wrapped cross-room chat. Run via
tests/run_discord_test.sh (which starts the GBA-PK server first).
"""
import http.server
import json
import socket
import sys
import threading
import time

sys.path.insert(0, "chat")
import importlib
bridge_mod = importlib.import_module("gba-pk-discord")

PORT = 4096
HOOK_PORT = 8787
received = []

passed = failed = 0
def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
        print("  PASS " + msg)
    else:
        failed += 1
        print("  FAIL " + msg)


class Hook(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        received.append(json.loads(body.decode()))
        self.send_response(204)
        self.end_headers()

    def log_message(self, *a):
        pass


def main():
    httpd = http.server.HTTPServer(("127.0.0.1", HOOK_PORT), Hook)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    # fake in-game player joins Kanto
    game = socket.create_connection(("127.0.0.1", PORT), timeout=5)
    game.settimeout(0.2)
    game.sendall(bridge_mod.frame("BPR1", 0, 0, "JOIN", 0))
    gid = None
    buf = b""
    deadline = time.time() + 5
    game_chat = []

    def pump(seconds):
        nonlocal gid, buf
        end = time.time() + seconds
        while time.time() < end:
            try:
                chunk = game.recv(65536)
            except socket.timeout:
                continue
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            while len(buf) >= bridge_mod.FRAME:
                f, buf = buf[:bridge_mod.FRAME], buf[bridge_mod.FRAME:]
                t = f[16:20]
                if t == b"STRT":
                    gid = int(f[20:24]) - 1000
                elif t == b"CHAT":
                    game_chat.append((bridge_mod.pid_of(f), bridge_mod.payload_of(f)))

    pump(1.0)
    check(gid is not None and gid >= 2, "fake in-game client joined")

    # bridge joins and starts webhook mode in a thread
    br = bridge_mod.Bridge("127.0.0.1", PORT, "Disc")
    check(br.wait_ready(5), "bridge joined the server")
    threading.Thread(target=bridge_mod.run_webhook,
                     args=(br, f"http://127.0.0.1:{HOOK_PORT}/hook"),
                     daemon=True).start()
    time.sleep(0.5)

    # game -> Discord: the fake player chats; webhook sink must get it
    game.sendall(bridge_mod.frame("BPR1", gid, 0, "CHAT", 0,
                                  payload=bridge_mod.padded("bridge me please")))
    deadline = time.time() + 6
    while time.time() < deadline and not any(
            "bridge me please" in r.get("content", "") for r in received):
        pump(0.2)
    hit = next((r for r in received if "bridge me please" in r.get("content", "")), None)
    check(hit is not None, "in-game chat reached the webhook sink")
    check(hit is not None and "Kanto" in hit["content"],
          "webhook message is room-attributed: " + json.dumps(hit))

    # Discord -> game: send through the bridge; fake client must see it wrapped
    br.send_chat("PhoneUser: omw")
    pump(3.0)
    wrapped = next((p for pid, p in game_chat if pid == 0 and "omw" in p), None)
    check(wrapped is not None, "bridge chat reached the in-game client")
    check(wrapped is not None and "Disc" in wrapped and "CHAT" in wrapped,
          "in-game line is name+room attributed: " + repr(wrapped))

    # long Discord messages split into protocol-size lines, none lost
    br.send_chat("x" * 100)
    pump(3.0)
    parts = [p for pid, p in game_chat if pid == 0 and "xxx" in p]
    total = sum(p.count("x") for p in parts)
    check(total == 100, f"100-char message fully delivered across {len(parts)} lines")

    game.close()
    httpd.shutdown()
    print(f"\n== RESULT: {passed} passed, {failed} failed ==")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
