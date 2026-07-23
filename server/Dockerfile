# GBA-PK dedicated server — container image.
# Works on Railway (set the service's Root Directory to `server`), Fly.io,
# render.com, a VPS with Docker, or plain `docker run`.
#
#   docker build -t gba-pk-server .
#   docker run -p 4096:4096 -v gbapk-data:/data gba-pk-server
#
# Configuration (environment variables):
#   PORT          port to listen on            (default 4096)
#   MAX_PLAYERS   player cap                   (default 8)
#   SERVER_FLAGS  extra flags, e.g. "--local=7 -v"
#
# The server persists player accounts to /data/GBA-PK-Server.accounts —
# mount a volume there to keep identities across restarts/redeploys.
FROM debian:bookworm-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends lua5.4 lua-socket \
	&& rm -rf /var/lib/apt/lists/*

COPY GBA-PK-Server.lua /app/GBA-PK-Server.lua

WORKDIR /data
EXPOSE 4096

CMD ["sh", "-c", "exec lua5.4 /app/GBA-PK-Server.lua ${PORT:-4096} ${MAX_PLAYERS:-8} ${SERVER_FLAGS:-}"]
