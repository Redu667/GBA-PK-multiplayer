#!/usr/bin/env python3
"""GBA-PK web chat gateway.

Serves a phone-friendly chat page over HTTP and bridges it to a GBA-PK
dedicated server, so anyone — Android included — can join the session's chat
by just opening a URL in a browser. No app, no account, no dependencies
beyond Python 3: the WebSocket side is hand-rolled on the standard library.

    python3 webchat.py <gbapk host[:port]> [--http-port 8080] [--name Web]

It joins the game server as one chat-only player (game id "CHAT"), the same
pattern as the other companions; every web visitor shares that slot and gets
a "Name: text" prefix. The bundled server Dockerfile runs this next to the
Lua server, so a Railway deployment's HTTP domain serves the chat page while
the TCP proxy carries the game protocol.
"""
import argparse
import base64
import hashlib
import http.server
import json
import socket
import struct
import sys
import threading
import time

FRAME = 64
CHAT_MAX = 43
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

PAGE = """<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>GBA-PK chat</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font: 16px/1.4 system-ui, sans-serif; display: flex;
         flex-direction: column; height: 100dvh;
         background: #1b1e26; color: #e8e8e2; }
  header { padding: 10px 14px; background: #2b3348; color: #fff;
           font-weight: 600; border-bottom: 3px solid #8898b8; }
  header small { opacity: .7; font-weight: 400; margin-left: 8px; }
  #log { flex: 1; overflow-y: auto; padding: 10px 14px; }
  #log div { margin: 3px 0; word-wrap: break-word; }
  #log .sys { opacity: .65; font-style: italic; }
  form { display: flex; gap: 8px; padding: 10px 14px;
         padding-bottom: calc(10px + env(safe-area-inset-bottom));
         background: #232838; }
  input { border: 1px solid #566; border-radius: 8px; padding: 10px;
          font: inherit; background: #171a22; color: inherit; }
  #name { width: 90px; }
  #text { flex: 1; min-width: 0; }
  button { border: 0; border-radius: 8px; padding: 10px 16px; font: inherit;
           background: #3060c0; color: #fff; }
  button:disabled { opacity: .5; }
</style></head><body>
<header>GBA-PK chat<small id="st">connecting…</small></header>
<div id="log"></div>
<form id="f">
  <input id="name" maxlength="10" placeholder="name" autocomplete="nickname">
  <input id="text" maxlength="200" placeholder="message" autocomplete="off">
  <button id="send" disabled>Send</button>
</form>
<script>
  const log = document.getElementById("log"), st = document.getElementById("st");
  const name = document.getElementById("name"), text = document.getElementById("text");
  const send = document.getElementById("send");
  name.value = localStorage.gbapkName || "";
  function add(line, sys) {
    const d = document.createElement("div");
    d.textContent = line;
    if (sys) d.className = "sys";
    log.appendChild(d);
    while (log.childElementCount > 200) log.removeChild(log.firstChild);
    log.scrollTop = log.scrollHeight;
  }
  let ws, retry = 0;
  function connect() {
    ws = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/ws");
    ws.onopen = () => { st.textContent = "online"; send.disabled = false; retry = 0; };
    ws.onmessage = (e) => { const m = JSON.parse(e.data); add(m.line, m.sys); };
    ws.onclose = () => {
      st.textContent = "reconnecting…"; send.disabled = true;
      setTimeout(connect, Math.min(1000 * ++retry, 10000));
    };
  }
  connect();
  document.getElementById("f").onsubmit = (e) => {
    e.preventDefault();
    const n = name.value.trim() || "Guest", t = text.value.trim();
    if (!t || ws.readyState !== 1) return;
    localStorage.gbapkName = n;
    ws.send(JSON.stringify({ name: n, text: t }));
    text.value = "";
  };
</script></body></html>"""


def fid(n: int) -> str:
    return f"{1000 + n:04d}"


def frame(gameid: str, pid: int, sendto: int, ptype: str, reqbytes: int, payload: bytes = None) -> bytes:
    extra = payload if payload is not None else (
        fid(reqbytes).encode() + b"\x00" * 33 + b"F" + b"FFFFF")
    f = gameid.encode() + b"FFFF" + fid(pid).encode() + fid(sendto).encode() + ptype.encode() + extra + b"U"
    assert len(f) == FRAME, len(f)
    return f


def padded(text: str) -> bytes:
    raw = text.encode("ascii", "replace")[:CHAT_MAX]
    return raw + b"~" * (CHAT_MAX - len(raw))


def payload_of(f: bytes) -> str:
    return f[20:63].rstrip(b"~").decode("ascii", "replace")


def pid_of(f: bytes) -> int:
    try:
        return int(f[8:12]) - 1000
    except ValueError:
        return -1


class Bridge:
    """The game-server side: keeps (re)joining, receives chat, sends chat."""

    def __init__(self, host: str, port: int, name: str):
        self.host, self.port = host, port
        self.name = name[:10]
        self.sock = None
        self.id = None
        self.nicks = {}
        self.on_chat = lambda line: None
        self.running = True
        threading.Thread(target=self._connect_loop, daemon=True).start()
        threading.Thread(target=self._heartbeat, daemon=True).start()

    def send_chat(self, text: str) -> None:
        sock, me = self.sock, self.id
        if sock is None or me is None:
            return
        text = "".join(c if 32 <= ord(c) < 127 else " " for c in text).replace("~", "-")
        # budget for the server's cross-room "NAME (CHAT): " wrap of the payload
        step = max(CHAT_MAX - (len(self.name) + len(" (CHAT): ")), 16)
        try:
            for i in range(0, max(len(text), 1), step):
                sock.sendall(frame("CHAT", me, 0, "CHAT", 0, payload=padded(text[i:i + step])))
        except OSError:
            pass

    def _connect_loop(self) -> None:
        while self.running:
            try:
                sock = socket.create_connection((self.host, self.port), timeout=10)
            except OSError:
                time.sleep(3)
                continue
            sock.settimeout(None)
            try:
                sock.sendall(frame("CHAT", 0, 0, "JOIN", 0))
                self.sock = sock
                self._receive(sock)
            except OSError:
                pass
            self.sock, self.id = None, None
            if self.running:
                self.on_chat("(webchat lost the game server, reconnecting...)")
                time.sleep(3)

    def _receive(self, sock: socket.socket) -> None:
        buf = b""
        while self.running:
            chunk = sock.recv(65536)
            if not chunk:
                return
            buf += chunk
            while len(buf) >= FRAME:
                f, buf = buf[:FRAME], buf[FRAME:]
                t = f[16:20]
                if t == b"STRT":
                    self.id = int(f[20:24]) - 1000
                    sock.sendall(frame("CHAT", self.id, 0, "NICK", 0, payload=padded(self.name)))
                    print(f"* joined the GBA-PK server as player {self.id}")
                elif t == b"CHAT":
                    pid = pid_of(f)
                    if pid == 0:
                        self.on_chat(payload_of(f))
                    else:
                        who = self.nicks.get(pid, f"P{pid}")
                        self.on_chat(f"{who}: {payload_of(f)}")
                elif t == b"NICK":
                    self.nicks[pid_of(f)] = payload_of(f)
                elif t == b"RFSE":
                    print("* game server refused the connection (full?)")

    def _heartbeat(self) -> None:
        while self.running:
            time.sleep(4)
            sock, me = self.sock, self.id
            if sock is not None and me is not None:
                try:
                    sock.sendall(frame("CHAT", me, 0, "PING", 0))
                except OSError:
                    pass


class WebClients:
    """Registry of connected browsers; broadcast pushes a JSON line to each."""

    def __init__(self):
        self.lock = threading.Lock()
        self.conns = set()

    def add(self, conn):
        with self.lock:
            self.conns.add(conn)

    def remove(self, conn):
        with self.lock:
            self.conns.discard(conn)

    def broadcast(self, line: str, sys_line: bool = False) -> None:
        data = ws_text_frame(json.dumps({"line": line, "sys": sys_line}))
        with self.lock:
            dead = []
            for c in self.conns:
                try:
                    c.sendall(data)
                except OSError:
                    dead.append(c)
            for c in dead:
                self.conns.discard(c)


def ws_text_frame(text: str) -> bytes:
    payload = text.encode()
    if len(payload) < 126:
        return bytes([0x81, len(payload)]) + payload
    return bytes([0x81, 126]) + struct.pack(">H", len(payload)) + payload


def ws_read_frame(conn) -> tuple:
    """Returns (opcode, payload) or (None, None) on EOF."""
    def need(n):
        data = b""
        while len(data) < n:
            chunk = conn.recv(n - len(data))
            if not chunk:
                raise OSError("closed")
            data += chunk
        return data
    try:
        b1, b2 = need(2)
    except OSError:
        return None, None
    opcode = b1 & 0x0F
    masked = b2 & 0x80
    ln = b2 & 0x7F
    if ln == 126:
        ln = struct.unpack(">H", need(2))[0]
    elif ln == 127:
        ln = struct.unpack(">Q", need(8))[0]
    if ln > 65536:
        return None, None
    mask = need(4) if masked else b"\x00" * 4
    payload = bytes(b ^ mask[i % 4] for i, b in enumerate(need(ln)))
    return opcode, payload


def make_handler(bridge: Bridge, clients: WebClients):
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *a):
            pass

        def do_GET(self):
            if self.path == "/ws":
                self._websocket()
                return
            body = PAGE.encode() if self.path == "/" else b"not found"
            self.send_response(200 if self.path == "/" else 404)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _websocket(self):
            key = self.headers.get("Sec-WebSocket-Key")
            if not key:
                self.send_response(400)
                self.end_headers()
                return
            accept = base64.b64encode(
                hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
            self.send_response(101, "Switching Protocols")
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            conn = self.connection
            clients.add(conn)
            conn.sendall(ws_text_frame(json.dumps(
                {"line": "connected - messages reach players in-game", "sys": True})))
            last_send = 0.0
            try:
                while True:
                    opcode, payload = ws_read_frame(conn)
                    if opcode is None or opcode == 0x8:      # EOF / close
                        break
                    if opcode == 0x9:                        # ping -> pong
                        conn.sendall(bytes([0x8A, len(payload)]) + payload)
                        continue
                    if opcode != 0x1:
                        continue
                    try:
                        m = json.loads(payload.decode())
                        name = str(m.get("name", "Guest"))[:10] or "Guest"
                        text = str(m.get("text", ""))[:200].strip()
                    except (ValueError, UnicodeDecodeError):
                        continue
                    if not text or time.time() - last_send < 0.5:
                        continue                             # simple per-tab rate limit
                    last_send = time.time()
                    line = f"{name}: {text}"
                    bridge.send_chat(line)
                    clients.broadcast(f"{bridge.name}: {line}")
            finally:
                clients.remove(conn)
                self.close_connection = True

    return Handler


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("server", help="GBA-PK game server, host or host:port")
    ap.add_argument("--http-port", type=int, default=8080)
    ap.add_argument("--name", default="Web", help="the gateway's nickname in game chat")
    args = ap.parse_args()

    host, _, port = args.server.partition(":")
    clients = WebClients()
    bridge = Bridge(host, int(port or 4096), args.name)
    bridge.on_chat = clients.broadcast

    httpd = http.server.ThreadingHTTPServer(("0.0.0.0", args.http_port),
                                            make_handler(bridge, clients))
    print(f"* web chat listening on http://0.0.0.0:{args.http_port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    bridge.running = False


if __name__ == "__main__":
    main()
