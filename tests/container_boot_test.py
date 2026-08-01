#!/usr/bin/env python3
"""Container startup test: runs the Dockerfile's real CMD locally.

Docker isn't needed (or available in CI here) to check the part that actually
breaks: process boot order and env-var wiring. This parses the CMD string out
of server/Dockerfile, points /app at the repo's server/ folder, and runs it —
so the bridges must survive being started *before* the game server is
listening, which is exactly what happens in the container.

Asserts: the game server comes up on GAME_PORT; the Discord bridge starts from
DISCORD_WEBHOOK, waits out the boot race, joins, and relays in-game chat to a
webhook sink; and no bridge starts when the variables are absent.
"""
import http.server
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME_PORT = 4123          # off the default so a stray server can't fake a pass
HOOK_PORT = 8788
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


def docker_cmd() -> str:
    """The shell string from the Dockerfile's CMD, with /app pointed at server/."""
    text = open(os.path.join(ROOT, "server", "Dockerfile")).read()
    m = re.search(r'^CMD \[(.*?)\]\s*$', text, re.S | re.M)
    assert m, "could not find CMD in the Dockerfile"
    parts = json.loads("[" + m.group(1).replace("\\\n", "").replace("\t", " ") + "]")
    return parts[-1].replace("/app/", os.path.join(ROOT, "server") + "/")


def fid(n):
    return f"{1000 + n:04d}"


def frame(gameid, pid, sendto, ptype, reqbytes, payload=None):
    extra = payload if payload is not None else (
        fid(reqbytes).encode() + b"\x00" * 33 + b"F" + b"FFFFF")
    f = (gameid.encode() + b"FFFF" + fid(pid).encode() + fid(sendto).encode()
         + ptype.encode() + extra + b"U")
    assert len(f) == 64
    return f


def padded(text):
    raw = text.encode()[:43]
    return raw + b"~" * (43 - len(raw))


def wait_port(port, seconds=20):
    deadline = time.time() + seconds
    while time.time() < deadline:
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            return True
        except OSError:
            time.sleep(0.3)
    return False


def run_container(env_extra, workdir):
    """Start the CMD with its output going to a file we can show on failure."""
    env = dict(os.environ)
    env.update({"GAME_PORT": str(GAME_PORT), "MAX_PLAYERS": "8", "WEBCHAT": "0"})
    env.update(env_extra)
    logpath = os.path.join(workdir, "container.log")
    log = open(logpath, "w")
    proc = subprocess.Popen(["sh", "-c", docker_cmd()], cwd=workdir, env=env,
                            stdout=log, stderr=subprocess.STDOUT,
                            text=True, preexec_fn=os.setsid)
    proc.logpath = logpath
    return proc


def dump(proc, label):
    try:
        with open(proc.logpath) as fh:
            body = fh.read().strip()
    except OSError:
        body = "(no output captured)"
    print(f"  --- {label} container output ---")
    for line in body.splitlines():
        print("  | " + line)


def main():
    cmd = docker_cmd()
    check("gba-pk-discord.py" in cmd and "DISCORD_BOT_TOKEN" in cmd,
          "Dockerfile CMD starts the Discord bridge")

    threading.Thread(target=http.server.HTTPServer(("127.0.0.1", HOOK_PORT), Hook)
                     .serve_forever, daemon=True).start()

    work = os.path.join(os.environ.get("TMPDIR", "/tmp"), "gbapk-containertest")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)

    # --- with DISCORD_WEBHOOK set: bridge must start and survive the boot race
    proc = run_container({"DISCORD_WEBHOOK": f"http://127.0.0.1:{HOOK_PORT}/hook",
                          "DISCORD_NAME": "Disc"}, work)
    try:
        check(wait_port(GAME_PORT), "game server listening on GAME_PORT")

        game = socket.create_connection(("127.0.0.1", GAME_PORT), timeout=5)
        game.settimeout(0.2)
        game.sendall(frame("BPR1", 0, 0, "JOIN", 0))
        gid, buf = None, b""
        end = time.time() + 2
        while time.time() < end:
            try:
                chunk = game.recv(65536)
            except socket.timeout:
                continue
            buf += chunk
            while len(buf) >= 64:
                f, buf = buf[:64], buf[64:]
                if f[16:20] == b"STRT":
                    gid = int(f[20:24]) - 1000
        check(gid is not None, "in-game client joined the container's server")

        game.sendall(frame("BPR1", gid, 0, "CHAT", 0, payload=padded("container hello")))
        end = time.time() + 15
        while time.time() < end and not any(
                "container hello" in r.get("content", "") for r in received):
            time.sleep(0.3)
        hit = next((r for r in received if "container hello" in r.get("content", "")), None)
        check(hit is not None,
              "bridge auto-started by the container relayed chat to Discord")
        if hit is None:
            dump(proc, "webhook-mode")
        game.close()
    finally:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        proc.wait()

    # --- with no Discord variables: no bridge process should be started
    time.sleep(1)
    received.clear()
    proc = run_container({}, work)
    try:
        check(wait_port(GAME_PORT), "game server still starts without Discord vars")
        time.sleep(2)
        ps = subprocess.run(["ps", "-eo", "args"], capture_output=True, text=True).stdout
        check("gba-pk-discord.py" not in ps,
              "no bridge process when DISCORD_* is unset")
    finally:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        proc.wait()

    print(f"\n== RESULT: {passed} passed, {failed} failed ==")
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
