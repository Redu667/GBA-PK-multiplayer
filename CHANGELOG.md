# Changelog

## v2.0.0

The mid-term roadmap tier, complete. One dedicated server is now a small multiplayer
platform: regions, channels, identity, chat, matchmaking, reconnects, scale, and a first
layer of server-side validation.

- **Named channels.** `channel("name")` splits your region room into a separate lobby
  (`Kanto#speedrun`) — its own visibility and duels, while chat still crosses everything.
  `channel("")` returns to the main room, and your channel is rejoined automatically after a
  reconnect.
- **Battle matchmaking.** `duel()` queues you; when another player in your room queues, the
  server pairs you first-come-first-served and tells you both in chat ("Duel matched:
  NAME!"). Leave the queue by running `duel()` again.
- **Server-side validation (anti-cheat foundation).** The server now drops any frame that
  claims another player's id (spoofing) and kicks connections that keep doing it, rejects
  malformed trade-stage fields, and — in map-local mode — refuses trade/battle packets aimed
  at players you can't currently see. Deep content validation (legal species/moves/stats)
  requires per-game data tables and stays on the long-term roadmap, stated honestly.
- **One-click server hosting.** The server now lives in a self-contained
  [`server/`](server/) folder with a Dockerfile: point a **Railway** service at the repo
  with Root Directory `server`, enable a TCP proxy on port 4096, and you have a hosted
  server — full steps in `server/README.md` (Docker/VPS options included). `ServerIP` and
  `join()` accept `host:port`, so a Railway endpoint like `xyz.proxy.rlwy.net:31702` pastes
  straight in. Mount a volume at `/data` to keep player accounts across redeploys.
- Spectating was re-triaged to long term: it needs battle-UI state injection on the client,
  which is deep game work, and matchmaking + chat cover the social need for now.

## v1.8.0

- **Map-local visibility — the server can now scale past 8 players.** Small lobbies behave
  exactly as before. When a region room's population exceeds a threshold (server flag
  `--local=N`, default 7), the server switches that room to map-local mode: you're only
  introduced to — and synced with — players **on your current map**, are removed from view
  when you part ways, and see at most 8 others (the renderer's limit). Walking onto a map
  introduces whoever is there; a transition grace keeps border crossings from flickering.
  Combined with a higher player cap (`lua GBA-PK-Server.lua 4096 32 --local=7`), one server
  can hold a whole community while each screen stays sane.
- Clients on a dedicated server now keep reporting their position even when nobody is
  visible, so the server always knows which map you're on. **Update the script together with
  the server** — an old client alone on a map can't be re-introduced by a map-local server.

## v1.7.0

- **Persistent identity.** You are now *someone* on a server, durably. The mod saves your
  reconnect token and nickname to `GBA-PK.identity` (next to the script) and restores them
  on startup — "Welcome back, NAME." The dedicated server keeps token→nickname accounts in
  `GBA-PK-Server.accounts`, so restarting the emulator, your PC or even the **server** brings
  you back as yourself, greeted by name. Your nickname is **owned**: anyone else claiming it
  is renamed to `NAME(id)` even while you're offline.
- Running two instances on one PC (which share the identity file) is handled: a join that
  presents a token belonging to a visibly-live connection is treated as a new player instead
  of kicking the first instance.
- New test harnesses (`tests/run_server_test.sh`, `tests/run_identity_test.sh`) run the
  suites against a fresh server — including a genuine server restart for the identity test.

## v1.6.0

- **Region rooms (multi-region stage 1).** One dedicated server now hosts **Kanto (FR/LG)
  and Hoenn (R/S/E) players at the same time**. Gameplay — positions, introductions,
  nicknames, trades, battles — is scoped to your region's room (a FireRed map id means
  nothing in Emerald, and cross-family trades now abort cleanly with "too busy" instead of
  desyncing), while **chat and join/leave notices cross regions**, so the server still feels
  like one world: a Hoenn player's message shows up for Kanto players as
  "NAME (Hoenn): text", and notices read "NAME joined Hoenn (3/8 online)".
- **Region travel, semi-manual.** Because rejoining rooms you by the game you're playing and
  the reconnect token keeps your identity, switching regions is: save, load the other
  region's ROM, join again — same name, new region.
- Unknown/custom game codes get their own room, so odd romhacks can't pollute official
  lobbies with mismatched maps.

## v1.5.0

- **Graceful reconnect.** Losing your connection to a dedicated server no longer kicks you
  back to square one. The server now issues each player a reconnect token in the join
  handshake and holds a dropped player's id and nickname for 2 minutes; the client detects a
  dead server (heartbeat silence), quietly retries in the background (up to 20 attempts over
  ~100 seconds) and rejoins with its token — getting the same player id and name back. A
  rejoin also cleanly replaces a stale half-open connection, and everyone else sees a
  "NAME reconnected" notice instead of a confusing leave/join pair. Set `AutoReconnect =
  false` at the top of the script to keep the old behavior.
- Re-announced players can no longer create duplicate entries in the player list (the client
  now replaces an existing entry with the same id).

## v1.4.0

- **Chat.** Type `say("your message")` in the scripting box to talk to everyone in the
  session. Messages relay through the dedicated server (or the peer host) and appear in the
  console — and on mGBA 0.11+, in a small on-screen feed at the bottom of the game that fades
  out after a few seconds. The server announces joins and leaves in chat too ("[server]
  Player 3 joined (2/8 online)").
- **Presence.** The dedicated server now keeps nicknames unique — a duplicate name is shown
  to everyone else as `NAME(id)` — and every join/leave notice includes the online count.
- **Reliability.** Client and dedicated server exchange PING heartbeats, so a lone player is
  no longer silent (idle sessions stay accurately alive) and the client notices a dead server
  within ~25s and disconnects cleanly instead of hanging. The server also rate-limits each
  connection (240 frames/s) so one broken client can't flood a lobby.
- All of it is backward-compatible: new frame types are addressed per-recipient, so v1.3.0
  clients simply ignore them.

## v1.3.0

- **Dedicated server.** New standalone `GBA-PK-Server.lua` — a headless relay you can run on
  a VPS, spare PC or Pi (`lua GBA-PK-Server.lua [port] [maxplayers]`, needs luasocket). No
  emulator or ROM required. Everyone just uses **Set IP > Join** to connect; nobody has to
  host from inside their game, and the session survives any one player leaving. It speaks the
  same 64-byte protocol and plays the host's relay role (assigns ids, exchanges the join
  handshake, relays position/trade/battle/Soullocke packets, announces disconnects) but is not
  itself a player. The client detects a dedicated server (a flag in the STRT handshake) and
  doesn't add a phantom host player; peer `host()` mode is unchanged.
- **ROADMAP.md** added: multiplayer feature goals with PokeMMO as the yardstick, and the
  emulator decision (stay on mGBA; a bundled/customized build is a later packaging step).

## v1.2.3

- **Fix garbled packets / random disconnects over the internet.** Network packets are a fixed
  64 bytes, but the receiver treated each socket read as one whole packet. TCP is a byte
  stream, so on slower/real internet links a 64-byte packet often arrives split across reads
  (or several arrive coalesced). A single split packet permanently mis-aligned the stream, so
  every packet after it failed the validator ("got unverified packet") and the desync led to
  dropped connections — often on map changes, which burst several packets at once. The receiver
  now buffers incoming bytes per connection and dispatches only complete 64-byte frames,
  keeping any partial tail for the next read. LAN/localhost play was unaffected (packets
  arrived whole there); this fixes internet play.

## v1.2.2

- **Connection diagnostics.** New `netlog(on)` command toggles verbose network logging at
  runtime. When on, the host logs each incoming connection (so you can tell whether a joiner's
  connection is even reaching you — i.e. whether port forwarding works) and both sides log the
  join handshake. A failed join now also prints a clearer reason plus the usual things to check
  (public vs LAN IP, port-forward, firewall).

## v1.2.1

- **Set the host IP from the menu.** The connect menu has a new **Set IP** entry with a D-pad
  editor (Up/Down change a digit or dot, Left/Right move, A confirms) so you can point **Join**
  at any address without touching the scripting box. `join("ip")` still works too.
- **Tidier on-screen menu.** The overlay menu used oversized text that filled the screen and
  clipped the title. Type is smaller and rows are tighter now, so the whole menu fits neatly and
  the console-style `=====` title decoration is dropped on screen.

## v1.2.0

- **In-session menu.** Press **Select** while hosting or connected to open a new in-game menu
  with **Set name**, **Set skin** and **Disconnect** — so you can change how you look or what
  you're called without leaving the session. (Host/Join/Soullocke setup only apply before you
  connect, so they're not shown here.) Skin changes ride out in the normal position packet, so
  everyone sees your new look live; name changes send a nickname update to the other players.
  `setname()` in the scripting box now also broadcasts mid-session.

## v1.1.1

- **On-screen menu fixes (mGBA 0.11+).** Two bugs in the v1.1.0 on-screen overlay:
  - The panel background could disappear behind the text while navigating the menu.
    `render()` now fully clears the layer and repaints the panel opaque (blend off) before
    drawing the text (blend on), so every redraw lands a solid background.
  - After choosing an option (e.g. Host) the menu didn't disappear — it dropped into the
    black border below the game. The overlay is now hidden by **clearing its layer to
    transparent** rather than moving it off-screen: mGBA composites the overlay across the
    whole window, so a layer pushed past the 160px screen height lands in the letterbox
    instead of vanishing. The layer stays pinned at the top-left of the game and is
    re-composited each frame, so showing/hiding is just draw-panel vs. clear-to-transparent.

## v1.1.0

- **On-screen menu (mGBA 0.11+).** The connect/setup menu now draws directly on the game
  screen using mGBA 0.11's canvas/painter scripting API, instead of only in the scripting
  console tab. It falls back to the console panel automatically on mGBA 0.10.x. Bundles
  `SourceSans3-Regular.otf` (SIL OFL) for the on-screen text; keep it next to `GBA-PK.lua`.
- **mGBA 0.11 compatibility fix.** mGBA 0.11's `emu:getGameCode()` returns the bare 4-char
  code (e.g. `BPEE`) instead of 0.10's `AGB-BPEE`; the game code is now normalized so
  detection works on both versions. Without this the script disabled itself on 0.11.
- Menu input handling and the Select toggle from v1.0.0 are unchanged and apply to both
  the on-screen and console backends.

## v1.0.0

First tagged release of GBA-PK Multiplayer — one Lua script that adds multiplayer to the
official Generation 3 Pokémon games (FireRed/LeafGreen, Ruby/Sapphire, Emerald) in mGBA,
including most romhacks and randomized ROMs.

### Multiplayer

- See other players walk around the overworld in real time (up to 4 by default, 8 supported).
- **Trade** and **battle** with other players over the link-cable emulation.
- One unified script for both hosting and joining — no separate client/server files.
- Easy setup: a D-pad menu (Host / Join / Set name / Set skin / Soullocke setup) driven
  from the game window — while it's open your inputs go only to the menu, not the game, and
  **Select** toggles it. Plus scripting-box commands (`host()`, `join("IP")`, `setname()`,
  `who()`, `status()`, …).
- Works across all official Gen 3 games and regional variants, with a `RomHackBaseGame`
  override for custom-code romhacks.

### Appearance

- **Player skins** — cycle through a curated set of each game's own overworld sprites;
  others see your skin, you look normal to yourself.
- Skins **animate** with a full walk cycle and face their direction of travel.
- **Battle indicator** — a "!" bubble appears over a player who is in a battle.

### Soullocke mode

A co-op, soul-linked Nuzlocke handler (opt-in) for all five games:

- **Auto soul-linking** of Pokémon caught in the same area, rebuilt over the network each
  session (no separate save file).
- **Shared fate** — when a linked Pokémon faints it is marked dead and its linked
  partner(s) are fainted on the other games; revived dead Pokémon are re-fainted.
- **Same team, same box** — benching or re-teaming a linked Pokémon prompts partners to
  keep theirs in sync.
- Optional rules as toggles: **dupes clause** (default on) and **primary-type restriction**
  (default off), plus an opt-in **auto-release** of dead links.
- **Randomizer-safe** — reads only structural game state (party data, HP, met location, and
  the ROM base-stat table for types), so it works on ROMs randomized with tools such as the
  Universal Pokémon Randomizer FVX.
- Commands: `soullocke()`, `soul_dupes()`, `soul_typerule()`, `soul_autorelease()`,
  `soul_status()`.
