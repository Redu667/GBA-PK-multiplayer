# GBA-PK dedicated server

This folder is a **self-contained, deployable server**: `GBA-PK-Server.lua` (the whole
server — plain Lua + luasocket, no emulator or ROM), `webchat.py` (a phone-friendly web
chat page bridged into the session, Python 3 stdlib only) plus a `Dockerfile` so cloud
hosts can run both directly.

The game speaks **raw TCP** on port `4096` (not HTTP); the web chat speaks normal HTTP —
that split drives all the hosting notes below.

## Host it on Railway (recommended easy path)

1. Fork this repository (or use your own copy).
2. On [Railway](https://railway.com): **New Project → Deploy from GitHub repo** and pick
   the repo.
3. In the service **Settings → Source**, set **Root Directory** to `server`. Railway will
   detect the Dockerfile and build it.
4. In **Settings → Networking**, click **TCP Proxy** and point it at port **4096**.
   Railway gives you an endpoint like `tramway.proxy.rlwy.net:31702` — that's the *game*
   endpoint.
5. That endpoint is what players use. In `GBA-PK.lua` they either set

   ```lua
   local ServerIP   = "tramway.proxy.rlwy.net:31702"  -- host:port works
   ```

   or type `join("tramway.proxy.rlwy.net:31702")` in the scripting box, then **Join**.
   (The D-pad **Set IP** editor only types numeric IPs — hostnames go in the config or
   the scripting box.)
6. *(Optional, for phone chat)* Also click **Generate Domain** to add an **HTTP domain**:
   that URL (e.g. `https://your-app.up.railway.app`) serves the **web chat page** — open
   it on any phone or browser, pick a name, and you're in the session's chat. Android
   players hang out here (no Android emulator can run the mod itself — see the root
   README). Set `WEBCHAT=0` to turn the page off.
7. *(Optional but recommended)* Add a **Volume** mounted at `/data` so player accounts
   (`GBA-PK-Server.accounts` — names + reconnect identities) survive redeploys.
8. *(Optional)* **Variables:** `MAX_PLAYERS` (default 8), `SERVER_FLAGS` (e.g.
   `--local=7 -v` for map-local visibility + verbose logs), `GAME_PORT` (default 4096;
   keep it matching the TCP proxy target). `PORT` belongs to the web chat — Railway sets
   it automatically for the HTTP domain.

Keep it at **one replica** — the server is stateful (one lobby world per process).

## Any Docker host / VPS

```sh
cd server
docker build -t gba-pk-server .
docker run -d --restart unless-stopped -p 4096:4096 -p 8080:8080 -v gbapk-data:/data gba-pk-server
```

Open TCP `4096` (game) and `8080` (web chat, optional) in the firewall / security group.

## Bare metal (no Docker)

```sh
sudo apt install lua5.4 lua-socket     # Debian/Ubuntu
lua5.4 GBA-PK-Server.lua               # port 4096, up to 8 players
lua5.4 GBA-PK-Server.lua 4096 32 --local=7   # big lobby
python3 webchat.py 127.0.0.1:4096 --http-port 8080   # optional web chat page
```

The accounts file is written to the directory you start it from.

## What the server does

Assigns player ids, relays positions/trades/battles/Soullocke within region rooms (Kanto =
FR/LG, Hoenn = R/S/E), carries chat and join/leave notices across rooms, remembers player
identities (reconnect tokens + owned nicknames), runs the `duel()` matchmaking queue and
named `channel()` lobbies, heartbeats, rate-limits, and drops spoofed frames. See the root
[README](../README.md) and [ROADMAP](../ROADMAP.md) for the full picture.
