# GBA-PK dedicated server

This folder is a **self-contained, deployable server**: `GBA-PK-Server.lua` (the whole
server — plain Lua + luasocket, no emulator or ROM) plus a `Dockerfile` so cloud hosts can
run it directly.

The game speaks **raw TCP** on port `4096` (not HTTP) — that one fact drives all the
hosting notes below.

## Host it on Railway (recommended easy path)

1. Fork this repository (or use your own copy).
2. On [Railway](https://railway.com): **New Project → Deploy from GitHub repo** and pick
   the repo.
3. In the service **Settings → Source**, set **Root Directory** to `server`. Railway will
   detect the Dockerfile and build it.
4. In **Settings → Networking**, do **not** add an HTTP domain — instead click
   **TCP Proxy** and point it at port **4096**. Railway gives you an endpoint like
   `tramway.proxy.rlwy.net:31702`.
5. That endpoint is what players use. In `GBA-PK.lua` they either set

   ```lua
   local ServerIP   = "tramway.proxy.rlwy.net:31702"  -- host:port works
   ```

   or type `join("tramway.proxy.rlwy.net:31702")` in the scripting box, then **Join**.
   (The D-pad **Set IP** editor only types numeric IPs — hostnames go in the config or
   the scripting box.)
6. *(Optional but recommended)* Add a **Volume** mounted at `/data` so player accounts
   (`GBA-PK-Server.accounts` — names + reconnect identities) survive redeploys.
7. *(Optional)* **Variables:** `MAX_PLAYERS` (default 8), `SERVER_FLAGS` (e.g.
   `--local=7 -v` for map-local visibility + verbose logs). Leave `PORT` alone unless you
   change the TCP proxy target to match.

Keep it at **one replica** — the server is stateful (one lobby world per process).

## Any Docker host / VPS

```sh
cd server
docker build -t gba-pk-server .
docker run -d --restart unless-stopped -p 4096:4096 -v gbapk-data:/data gba-pk-server
```

Open TCP `4096` in the firewall / security group.

## Bare metal (no Docker)

```sh
sudo apt install lua5.4 lua-socket     # Debian/Ubuntu
lua5.4 GBA-PK-Server.lua               # port 4096, up to 8 players
lua5.4 GBA-PK-Server.lua 4096 32 --local=7   # big lobby
```

The accounts file is written to the directory you start it from.

## What the server does

Assigns player ids, relays positions/trades/battles/Soullocke within region rooms (Kanto =
FR/LG, Hoenn = R/S/E), carries chat and join/leave notices across rooms, remembers player
identities (reconnect tokens + owned nicknames), runs the `duel()` matchmaking queue and
named `channel()` lobbies, heartbeats, rate-limits, and drops spoofed frames. See the root
[README](../README.md) and [ROADMAP](../ROADMAP.md) for the full picture.
