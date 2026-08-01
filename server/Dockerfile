# GBA-PK dedicated server — container image.
# Works on Railway (set the service's Root Directory to `server`), Fly.io,
# render.com, a VPS with Docker, or plain `docker run`.
#
#   docker build -t gba-pk-server .
#   docker run -p 4096:4096 -p 8080:8080 -v gbapk-data:/data gba-pk-server
#
# The container runs up to three things, all talking to each other over
# localhost — no extra Railway service needed:
#   * the game server (Lua) on GAME_PORT (default 4096) — point your Railway
#     TCP proxy / players here,
#   * the web chat page (webchat.py) on PORT (default 8080) — give the service
#     an HTTP domain and phones can chat at https://your-app.../ , and
#   * the Discord bridge (gba-pk-discord.py), if you set the variables below.
#
# Configuration (environment variables):
#   GAME_PORT           game protocol port     (default 4096)
#   PORT                web chat HTTP port     (default 8080; Railway sets this
#                       automatically when you generate an HTTP domain)
#   MAX_PLAYERS         player cap             (default 8)
#   SERVER_FLAGS        extra flags, e.g. "--local=7 -v"
#   WEBCHAT             set to 0 to not start the web chat
#   DISCORD_BOT_TOKEN   Discord bot token   } set BOTH for a two-way bridge
#   DISCORD_CHANNEL     Discord channel id  }
#   DISCORD_WEBHOOK     webhook URL — one-way (game -> Discord) alternative,
#                       used only when no bot token is set
#   DISCORD_NAME        bridge's nickname in game chat (default "Discord")
#
# Each chat bridge that runs occupies one player slot, so raise MAX_PLAYERS
# accordingly (web chat + Discord = 2 slots).
#
# The server persists player accounts to /data/GBA-PK-Server.accounts —
# mount a volume there to keep identities across restarts/redeploys.
FROM debian:bookworm-slim

# discord.py is only needed for the two-way Discord bridge. If it can't be
# installed the image still builds: the game server and web chat are what
# matter, and the bridge says so clearly at runtime instead of taking the
# whole deployment down over an optional feature.
RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		lua5.4 lua-socket python3-minimal python3-pip \
	&& (pip3 install --no-cache-dir --break-system-packages discord.py \
		|| echo "WARNING: discord.py not installed - two-way Discord bridge unavailable") \
	&& apt-get purge -y python3-pip && apt-get autoremove -y \
	&& rm -rf /var/lib/apt/lists/*

COPY GBA-PK-Server.lua /app/GBA-PK-Server.lua
COPY webchat.py /app/webchat.py
COPY gba-pk-discord.py /app/gba-pk-discord.py

WORKDIR /data
EXPOSE 4096 8080

CMD ["sh", "-c", "\
	if [ \"${WEBCHAT:-1}\" != \"0\" ]; then \
		python3 /app/webchat.py 127.0.0.1:${GAME_PORT:-4096} --http-port ${PORT:-8080} & \
	fi; \
	if [ -n \"${DISCORD_BOT_TOKEN}\" ] && [ -n \"${DISCORD_CHANNEL}\" ]; then \
		python3 /app/gba-pk-discord.py 127.0.0.1:${GAME_PORT:-4096} \
			--bot \"${DISCORD_BOT_TOKEN}\" --discord-channel \"${DISCORD_CHANNEL}\" \
			--name \"${DISCORD_NAME:-Discord}\" & \
	elif [ -n \"${DISCORD_WEBHOOK}\" ]; then \
		python3 /app/gba-pk-discord.py 127.0.0.1:${GAME_PORT:-4096} \
			--webhook \"${DISCORD_WEBHOOK}\" --name \"${DISCORD_NAME:-Discord}\" & \
	fi; \
	exec lua5.4 /app/GBA-PK-Server.lua ${GAME_PORT:-4096} ${MAX_PLAYERS:-8} ${SERVER_FLAGS:-}"]
