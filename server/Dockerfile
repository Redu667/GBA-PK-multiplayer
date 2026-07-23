# GBA-PK dedicated server — container image.
# Works on Railway (set the service's Root Directory to `server`), Fly.io,
# render.com, a VPS with Docker, or plain `docker run`.
#
#   docker build -t gba-pk-server .
#   docker run -p 4096:4096 -p 8080:8080 -v gbapk-data:/data gba-pk-server
#
# The container runs two things:
#   * the game server (Lua) on GAME_PORT (default 4096) — point your Railway
#     TCP proxy / players here, and
#   * the web chat page (server/webchat.py) on PORT (default 8080) — give the
#     service an HTTP domain and phones can chat at https://your-app.../
#
# Configuration (environment variables):
#   GAME_PORT     game protocol port           (default 4096)
#   PORT          web chat HTTP port           (default 8080; Railway sets this
#                 automatically when you generate an HTTP domain)
#   MAX_PLAYERS   player cap                   (default 8)
#   SERVER_FLAGS  extra flags, e.g. "--local=7 -v"
#   WEBCHAT       set to 0 to not start the web chat
#
# The server persists player accounts to /data/GBA-PK-Server.accounts —
# mount a volume there to keep identities across restarts/redeploys.
FROM debian:bookworm-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends lua5.4 lua-socket python3-minimal \
	&& rm -rf /var/lib/apt/lists/*

COPY GBA-PK-Server.lua /app/GBA-PK-Server.lua
COPY webchat.py /app/webchat.py

WORKDIR /data
EXPOSE 4096 8080

CMD ["sh", "-c", "\
	if [ \"${WEBCHAT:-1}\" != \"0\" ]; then \
		python3 /app/webchat.py 127.0.0.1:${GAME_PORT:-4096} --http-port ${PORT:-8080} & \
	fi; \
	exec lua5.4 /app/GBA-PK-Server.lua ${GAME_PORT:-4096} ${MAX_PLAYERS:-8} ${SERVER_FLAGS:-}"]
