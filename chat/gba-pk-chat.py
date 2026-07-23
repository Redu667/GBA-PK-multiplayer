#!/usr/bin/env python3
"""GBA-PK keyboard chat companion.

A tiny chat client for a GBA-PK dedicated server: run it next to your game and
you get a real keyboard chat box in a terminal — no more say("...") in the
scripting console. It speaks the same 64-byte frame protocol as the mod, joins
as a chat-only player (game id "CHAT", which gives it its own room), and since
chat crosses rooms on the server, everything you type reaches the in-game
players' chat feed and everything they say shows up here.

    python3 gba-pk-chat.py <host[:port]> [name]
    python3 gba-pk-chat.py tramway.proxy.rlwy.net:31702 Ynnead

Notes: it occupies one player slot on the server, heartbeats like any client,
and needs only the Python standard library.
"""
import socket
import sys
import threading
import time

FRAME = 64


def fid(n: int) -> str:
    return f"{1000 + n:04d}"


def frame(gameid: str, pid: int, sendto: int, ptype: str, reqbytes: int, payload: bytes = None) -> bytes:
    extra = payload if payload is not None else (
        fid(reqbytes).encode() + b"\x00" * 33 + b"F" + b"FFFFF")
    f = gameid.encode() + b"FFFF" + fid(pid).encode() + fid(sendto).encode() + ptype.encode() + extra + b"U"
    assert len(f) == FRAME, len(f)
    return f


def padded(text: str) -> bytes:
    raw = text.encode("ascii", "replace")[:43]
    return raw + b"~" * (43 - len(raw))


def payload_of(f: bytes) -> str:
    return f[20:63].rstrip(b"~").decode("ascii", "replace")


def pid_of(f: bytes) -> int:
    try:
        return int(f[8:12]) - 1000
    except ValueError:
        return -1


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    target = sys.argv[1]
    name = (sys.argv[2] if len(sys.argv) > 2 else "Keyboard")[:10]
    host, _, port = target.partition(":")
    port = int(port or 4096)

    sock = socket.create_connection((host, port), timeout=10)
    sock.settimeout(None)
    sock.sendall(frame("CHAT", 0, 0, "JOIN", 0))

    state = {"id": None, "nicks": {}, "alive": True}

    def send_chat(text: str) -> None:
        me = state["id"] or 0
        # the server re-wraps our chat for other rooms as "NAME (CHAT): text"
        # within the same 43-char payload; split long lines so nothing is cut
        step = max(43 - (len(name) + len(" (CHAT): ")), 16)
        text = text.replace("~", "-")
        for i in range(0, max(len(text), 1), step):
            sock.sendall(frame("CHAT", me, 0, "CHAT", 0, payload=padded(text[i:i + step])))

    def receiver() -> None:
        buf = b""
        while state["alive"]:
            try:
                chunk = sock.recv(65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            while len(buf) >= FRAME:
                f, buf = buf[:FRAME], buf[FRAME:]
                t = f[16:20]
                if t == b"STRT":
                    state["id"] = int(f[20:24]) - 1000
                    sock.sendall(frame("CHAT", state["id"], 0, "NICK", 0, payload=padded(name)))
                    print(f"* connected as player {state['id']} — type to chat, Ctrl-C to quit")
                elif t == b"CHAT":
                    pid = pid_of(f)
                    if pid == 0:
                        print(payload_of(f))          # server line: already "NAME (Room): text"
                    else:
                        who = state["nicks"].get(pid, f"P{pid}")
                        print(f"{who}: {payload_of(f)}")
                elif t == b"NICK":
                    state["nicks"][pid_of(f)] = payload_of(f)
                elif t == b"RFSE":
                    print("* server refused the connection (full?)")
                    state["alive"] = False
        state["alive"] = False
        print("* disconnected")

    def heartbeat() -> None:
        while state["alive"]:
            time.sleep(4)
            if state["id"] is not None:
                try:
                    sock.sendall(frame("CHAT", state["id"], 0, "PING", 0))
                except OSError:
                    break

    threading.Thread(target=receiver, daemon=True).start()
    threading.Thread(target=heartbeat, daemon=True).start()

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            # wait until the join handshake finished (the server drops frames
            # that don't carry our assigned player id)
            for _ in range(50):
                if state["id"] is not None or not state["alive"]:
                    break
                time.sleep(0.1)
            if state["alive"] and state["id"] is not None:
                send_chat(line)
                print(f"you: {line}")
        time.sleep(3)      # piped input: linger so replies still print
    except KeyboardInterrupt:
        pass
    finally:
        state["alive"] = False
        try:
            sock.close()
        except OSError:
            pass


if __name__ == "__main__":
    main()
