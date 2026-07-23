#!/usr/bin/env python3
"""Web-chat gateway integration test (no browser needed).

Starts webchat.py against a running GBA-PK server, then acts as both a phone
browser (raw HTTP + hand-rolled WebSocket client) and an in-game player
(64-byte frames): asserts the page serves, and that chat flows browser->game
and game->browser with proper attribution. Run via tests/run_webchat_test.sh.
"""
import base64
import http.client
import json
import os
import signal
import socket
import struct
import subprocess
import sys
import time

FRAME = 64
GAME_PORT = 4096
HTTP_PORT = 8766

passed = failed = 0
def check(cond, msg):
    global passed, failed
    if cond:
        passed += 1
        print("  PASS " + msg)
    else:
        failed += 1
        print("  FAIL " + msg)


def fid(n):
    return f"{1000 + n:04d}"


def frame(gameid, pid, sendto, ptype, reqbytes, payload=None):
    extra = payload if payload is not None else (
        fid(reqbytes).encode() + b"\x00" * 33 + b"F" + b"FFFFF")
    f = gameid.encode() + b"FFFF" + fid(pid).encode() + fid(sendto).encode() + ptype.encode() + extra + b"U"
    assert len(f) == FRAME
    return f


def padded(text):
    raw = text.encode()[:43]
    return raw + b"~" * (43 - len(raw))


class WsClient:
    """Minimal RFC6455 client: handshake + masked text frames."""

    def __init__(self, host, port, path="/ws"):
        self.sock = socket.create_connection((host, port), timeout=5)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((
            f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            resp += self.sock.recv(4096)
        assert b"101" in resp.split(b"\r\n", 1)[0], resp
        self.buf = resp.split(b"\r\n\r\n", 1)[1]

    def send_text(self, text):
        payload = text.encode()
        mask = os.urandom(4)
        head = bytes([0x81])
        if len(payload) < 126:
            head += bytes([0x80 | len(payload)])
        else:
            head += bytes([0x80 | 126]) + struct.pack(">H", len(payload))
        body = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(head + mask + body)

    def _need(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise OSError("closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv_text(self, timeout=5.0):
        self.sock.settimeout(timeout)
        b1, b2 = self._need(2)
        ln = b2 & 0x7F
        if ln == 126:
            ln = struct.unpack(">H", self._need(2))[0]
        elif ln == 127:
            ln = struct.unpack(">Q", self._need(8))[0]
        payload = self._need(ln)
        if b1 & 0x0F != 0x1:
            return self.recv_text(timeout)
        return payload.decode()


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    gw = subprocess.Popen(
        [sys.executable, os.path.join(root, "server", "webchat.py"),
         f"127.0.0.1:{GAME_PORT}", "--http-port", str(HTTP_PORT)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        time.sleep(1.5)

        # the page serves
        h = http.client.HTTPConnection("127.0.0.1", HTTP_PORT, timeout=5)
        h.request("GET", "/")
        r = h.getresponse()
        body = r.read().decode()
        check(r.status == 200 and "GBA-PK chat" in body, "chat page serves over HTTP")

        # fake in-game player joins Kanto
        game = socket.create_connection(("127.0.0.1", GAME_PORT), timeout=5)
        game.settimeout(0.2)
        game.sendall(frame("BPR1", 0, 0, "JOIN", 0))
        gid = None
        gbuf = b""
        game_chat = []

        def pump(seconds):
            nonlocal gid, gbuf
            end = time.time() + seconds
            while time.time() < end:
                try:
                    chunk = game.recv(65536)
                except socket.timeout:
                    continue
                gbuf += chunk
                while len(gbuf) >= FRAME:
                    f, gbuf = gbuf[:FRAME], gbuf[FRAME:]
                    if f[16:20] == b"STRT":
                        gid = int(f[20:24]) - 1000
                    elif f[16:20] == b"CHAT":
                        game_chat.append((int(f[8:12]) - 1000,
                                          f[20:63].rstrip(b"~").decode()))

        pump(1.0)
        check(gid is not None and gid >= 2, "fake in-game client joined")

        # browser connects; greeted with a system line
        ws = WsClient("127.0.0.1", HTTP_PORT)
        hello = json.loads(ws.recv_text())
        check(hello.get("sys") is True, "browser gets the connected notice")

        # browser -> game
        ws.send_text(json.dumps({"name": "Phone", "text": "hi from a browser"}))
        echo = json.loads(ws.recv_text())
        check("Phone: hi from a browser" in echo["line"], "sender sees the local echo")
        pump(3.0)
        wrapped = next((p for pid, p in game_chat if pid == 0 and "hi from a browser" in p), None)
        check(wrapped is not None, "browser chat reached the in-game client")
        check(wrapped is not None and "Web" in wrapped and "Phone" in wrapped,
              "in-game line names the gateway and the web user: " + repr(wrapped))

        # game -> browser
        game.sendall(frame("BPR1", gid, 0, "CHAT", 0, payload=padded("hello web people")))
        got = None
        deadline = time.time() + 5
        while time.time() < deadline and got is None:
            m = json.loads(ws.recv_text())
            if "hello web people" in m["line"]:
                got = m["line"]
        check(got is not None, "in-game chat reached the browser: " + repr(got))
        game.close()
    finally:
        gw.send_signal(signal.SIGKILL)
    print(f"\n== RESULT: {passed} passed, {failed} failed ==")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
