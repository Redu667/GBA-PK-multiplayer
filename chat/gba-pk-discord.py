#!/usr/bin/env python3
"""GBA-PK <-> Discord chat bridge.

Connects a GBA-PK dedicated server's chat to a Discord channel, so people on
phones (or anyone not at the emulator) can follow and join the conversation.
It speaks the same 64-byte frame protocol as the mod, joins as a chat-only
player (game id "CHAT"), and since chat crosses rooms on the server, it sees
everything and everything it says reaches every player's in-game feed.

Two modes:

  One-way (game -> Discord), no dependencies beyond Python 3:
    python3 gba-pk-discord.py <host[:port]> --webhook https://discord.com/api/webhooks/...

  Two-way (game <-> Discord), needs `pip install discord.py`:
    python3 gba-pk-discord.py <host[:port]> --bot BOT_TOKEN --discord-channel 123456789012345678

Make a webhook in Discord: channel settings -> Integrations -> Webhooks.
For a bot: https://discord.com/developers -> create app -> bot -> enable the
MESSAGE CONTENT intent -> invite it to your server with Send Messages.

Notes: the bridge occupies one player slot on the GBA-PK server and heartbeats
like any client. Discord messages longer than the protocol's 43-char chat line
are split across several lines.
"""
import argparse
import json
import queue
import socket
import sys
import threading
import time
import urllib.request

FRAME = 64
CHAT_MAX = 43


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
    """The GBA-PK side: join, heartbeat, receive chat, send chat."""

    def __init__(self, host: str, port: int, name: str):
        self.name = name[:10]
        self.sock = socket.create_connection((host, port), timeout=10)
        self.sock.settimeout(None)
        self.id = None
        self.nicks = {}
        self.alive = True
        self.on_chat = lambda line: None      # called with "Name: text" / server line
        self.sock.sendall(frame("CHAT", 0, 0, "JOIN", 0))
        threading.Thread(target=self._receiver, daemon=True).start()
        threading.Thread(target=self._heartbeat, daemon=True).start()

    def wait_ready(self, seconds: float = 5.0) -> bool:
        deadline = time.time() + seconds
        while time.time() < deadline and self.alive:
            if self.id is not None:
                return True
            time.sleep(0.1)
        return self.id is not None

    def send_chat(self, text: str) -> None:
        if self.id is None:
            return
        text = "".join(c if 32 <= ord(c) < 127 else " " for c in text).replace("~", "-")
        # the server re-wraps cross-room chat as "NAME (CHAT): text" inside the
        # same 43-char payload, so leave room for that prefix or the tail is cut
        step = max(CHAT_MAX - (len(self.name) + len(" (CHAT): ")), 16)
        for i in range(0, max(len(text), 1), step):
            self.sock.sendall(frame("CHAT", self.id, 0, "CHAT", 0,
                                    payload=padded(text[i:i + step])))

    def _receiver(self) -> None:
        buf = b""
        while self.alive:
            try:
                chunk = self.sock.recv(65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
            while len(buf) >= FRAME:
                f, buf = buf[:FRAME], buf[FRAME:]
                t = f[16:20]
                if t == b"STRT":
                    self.id = int(f[20:24]) - 1000
                    self.sock.sendall(frame("CHAT", self.id, 0, "NICK", 0, payload=padded(self.name)))
                    print(f"* connected to GBA-PK server as player {self.id}")
                elif t == b"CHAT":
                    pid = pid_of(f)
                    if pid == 0:
                        self.on_chat(payload_of(f))   # already "NAME (Room): text"
                    else:
                        who = self.nicks.get(pid, f"P{pid}")
                        self.on_chat(f"{who}: {payload_of(f)}")
                elif t == b"NICK":
                    self.nicks[pid_of(f)] = payload_of(f)
                elif t == b"RFSE":
                    print("* server refused the connection (full?)")
                    self.alive = False
        self.alive = False
        print("* disconnected from GBA-PK server")

    def _heartbeat(self) -> None:
        while self.alive:
            time.sleep(4)
            if self.id is not None:
                try:
                    self.sock.sendall(frame("CHAT", self.id, 0, "PING", 0))
                except OSError:
                    break


def run_webhook(bridge: Bridge, url: str) -> None:
    """One-way: every in-game chat line becomes a Discord message (rate-spaced)."""
    q = queue.Queue()
    bridge.on_chat = q.put

    def poster():
        while bridge.alive or not q.empty():
            try:
                line = q.get(timeout=1)
            except queue.Empty:
                continue
            body = json.dumps({"content": line[:1900]}).encode()
            req = urllib.request.Request(url, data=body,
                                         headers={"Content-Type": "application/json",
                                                  "User-Agent": "GBA-PK-bridge"})
            try:
                urllib.request.urlopen(req, timeout=10).read()
            except Exception as e:               # keep bridging even if one post fails
                print(f"* webhook post failed: {e}")
            time.sleep(0.5)                      # stay far under Discord's rate limit

    threading.Thread(target=poster, daemon=True).start()
    print("* bridging game chat -> Discord webhook (one-way). Ctrl-C to quit")
    try:
        while bridge.alive:
            time.sleep(1)
    except KeyboardInterrupt:
        pass


def run_bot(bridge: Bridge, token: str, channel_id: int) -> None:
    """Two-way: needs discord.py."""
    try:
        import discord
    except ImportError:
        sys.exit("Two-way mode needs discord.py: pip install discord.py "
                 "(or use --webhook for one-way bridging with no dependencies)")

    intents = discord.Intents.default()
    intents.message_content = True
    client = discord.Client(intents=intents)

    @client.event
    async def on_ready():
        channel = client.get_channel(channel_id)
        if channel is None:
            print(f"* bot can't see channel {channel_id} - check the id and permissions")
            await client.close()
            return
        loop = client.loop

        def to_discord(line: str) -> None:
            loop.call_soon_threadsafe(lambda: loop.create_task(channel.send(line[:1900])))

        bridge.on_chat = to_discord
        print(f"* bridging both ways with #{channel.name}. Ctrl-C to quit")

    @client.event
    async def on_message(message):
        if message.author == client.user or message.channel.id != channel_id:
            return
        if message.content:
            bridge.send_chat(f"{message.author.display_name}: {message.content}")

    client.run(token)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("server", help="GBA-PK server, host or host:port")
    ap.add_argument("--webhook", help="Discord webhook URL (one-way: game -> Discord)")
    ap.add_argument("--bot", help="Discord bot token (two-way; needs discord.py)")
    ap.add_argument("--discord-channel", type=int, help="Discord channel id for --bot mode")
    ap.add_argument("--name", default="Discord", help="bridge's nickname in game chat")
    args = ap.parse_args()

    if not args.webhook and not args.bot:
        ap.error("pick a mode: --webhook URL, or --bot TOKEN --discord-channel ID")
    if args.bot and not args.discord_channel:
        ap.error("--bot needs --discord-channel ID")

    host, _, port = args.server.partition(":")
    bridge = Bridge(host, int(port or 4096), args.name)
    if not bridge.wait_ready():
        sys.exit("* could not join the GBA-PK server")

    if args.bot:
        run_bot(bridge, args.bot, args.discord_channel)
    else:
        run_webhook(bridge, args.webhook)


if __name__ == "__main__":
    main()
