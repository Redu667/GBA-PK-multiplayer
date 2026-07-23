# GBA-PK roadmap

Where multiplayer is today and where it's heading. [PokeMMO](https://pokemmo.com/) is
the reference point for the multiplayer feature set — not to clone it, but as a concrete
target for what "good" looks like.

## Where we are (v2.0.0)

- Real-time shared overworld: see other players walk, up to 8.
- Player-vs-player **trade** and **battle** over emulated link cable.
- Co-op **Soullocke** (soul-linked Nuzlocke) with shared fate.
- Player skins, in-session name/skin changes, D-pad menus with on-screen (0.11) UI.
- **Dedicated server** (`GBA-PK-Server.lua`) — a standalone relay so nobody has to host
  from inside their game — with chat, join/leave notices, heartbeats and auto-reconnect.
- Works on FR/LG, R/S/E and most romhacks, including randomized ROMs.

## Networking model

Two topologies now share the same 64-byte frame protocol:

| Mode | How | Good for |
|------|-----|----------|
| **Peer host** (original) | One player runs `host()`; they are player 1 and relay for everyone. | Two friends, quick sessions. |
| **Dedicated server** (new) | `GBA-PK-Server.lua` runs headless on a VPS/PC; everyone just **Joins** it. | Persistent lobbies, more players, no host-quits-game-ends. |

The dedicated server is the foundation for everything MMO-shaped below: a always-on
authority that owns session state, independent of any one player's emulator.

## Feature goals (PokeMMO as the yardstick)

Roughly in dependency order. Nothing here is committed; it's a direction.

### Near term — solidify shared world
- [x] **Server-owned presence** *(v1.4.0)* — join/leave notices broadcast to everyone, online
      count in each notice, and duplicate nicknames deduped server-side (`NAME` → `NAME(id)`).
- [x] **Chat** *(v1.4.0)* — `say("message")` relays through the dedicated server (or the peer
      host); messages show in the console and, on mGBA 0.11+, in an on-screen feed at the
      bottom of the game. Follow-up: an in-game way to type (D-pad editor or quick-phrases).
- [x] **Heartbeat + rate limiting** *(v1.4.0)* — client↔server PING keepalive (lone players
      are no longer silent; clients detect a dead server and say so) and per-client frame
      rate limiting on the server.
- [x] **Graceful reconnect** *(v1.5.0)* — the server issues a reconnect token and holds a
      dropped player's id/nickname for 2 minutes; the client auto-rejoins a lost dedicated
      server (retrying for ~100s) and gets its identity back, replacing any stale connection.
- [x] **Region rooms** *(v1.6.0)* — the server scopes gameplay to game-family rooms (Kanto =
      FR/LG, Hoenn = R/S/E), enforcing family matchmaking server-side; chat and notices cross
      rooms. The foundation of the multi-region world below.
- [x] **Named channels** *(v2.0.0)* — `channel("name")` splits a region room into separate
      lobbies (`Kanto#speedrun`); `channel("")` returns to the main one. The channel is
      rejoined automatically after a reconnect.

### The multi-region world (multiple ROMs, PokeMMO-style)

PokeMMO has every region available at once because it is a **custom engine** that uses the
ROMs as asset files — it doesn't emulate one cartridge, it reimplements the games. mGBA runs
one core with one ROM, so a Lua script can't literally do that. What we *can* do is stage
toward the same experience on our architecture:

1. **Cross-region server** *(done, v1.6.0)* — one dedicated server hosts Kanto
   (FR/LG) and Hoenn (R/S/E) players at the same time. Gameplay (positions, trades,
   battles) is scoped to your region's room; **chat and presence are shared**, so the
   server feels like one world even though play happens per-region.
2. **Region travel** *(works today, semi-manual)* — "take the ferry": save, load the other
   region's ROM in mGBA, rejoin — the reconnect token keeps your identity and the server
   rooms you by whatever game you're now playing, so switching ROMs *is* switching regions.
   Polish (an in-menu "travel" flow that walks you through it) still to come.
3. **One-click travel via the bundled build** — the custom mGBA distribution (see the
   emulator section) automates step 2: swap core + save automatically so switching regions
   feels like one client with all regions, PokeMMO-style. Needs the launcher/fork work, so
   it lands with the bundling milestone.

You need to own each region's ROM, and each region keeps its own save file. A single
*account* spanning regions (one name, shared friends/chat identity) comes from the
persistent-identity item below; a single *save* spanning regions is engine-level work that
belongs to the far end of the roadmap.

### Mid term — MMO-ish structure
- [x] **Persistent identity** *(v1.7.0)* — the client keeps its identity (token + nickname)
      in a small file next to the script, and the server keeps token→nickname accounts on
      disk. Restart anything — emulator, PC, even the server — and you come back as
      yourself; your nickname is protected even while you're offline.
- [x] **Map-local visibility** *(v1.8.0)* — above a room-population threshold (`--local=N`,
      default 7) the server only introduces and syncs players on the same map (with a
      transition grace so border crossings don't flicker), removing them again when they part
      ways, capped at 8 visible per client (the renderer's slot limit). One server can now
      hold far more players than one screen.
- [x] **Battle matchmaking** *(v2.0.0)* — `duel()` queues you; when another player in your
      room queues, the server pairs you and tells you both in chat.
- [x] **Packet validation (foundation)** *(v2.0.0)* — the server drops frames that claim
      another player's id (spoofing) and kicks repeat offenders, rejects malformed trade
      fields, and in map-local mode refuses interactions with players you can't see. Deep
      *content* validation (legal species/moves/stats) needs per-game data tables — moved to
      long term with the rest of anti-cheat.

### Long term — the ambitious PokeMMO-style bits
- [ ] **Spectating** trades/battles — needs battle-UI state injection on the client, which
      is deep game work; deferred from mid term.
- [ ] **Shared economy / GTS-style trading** brokered by the server.
- [ ] **Server-authoritative anti-cheat** (the client can't be trusted for competitive play).
- [ ] **Cross-map "overworld hub"**, events, seasonal content.

These get progressively harder because Gen 3 games weren't built for it — the further right
we go, the more the server has to become the source of truth rather than a relay.

## Emulator: mGBA, alternatives, and bundling

**Decision: stay on mGBA for now; keep the door open to a bundled fork later.**

- **Why mGBA:** it's the only mainstream emulator with a Lua scripting API rich enough to do
  all of this from a single script — memory read/write, input hooks, sockets, and (0.11) an
  on-screen canvas. It's actively maintained, cross-platform, and accurate. The whole mod is
  ~16k lines of Lua running inside it; there is no comparable scripting surface elsewhere.
- **Alternatives considered:**
  - *BizHawk* — strong Lua too, but Windows-first and heavier; no clear win over mGBA and a
    full rewrite of the script's emulator interface.
  - *VBA-M / others* — weaker/older scripting, worse accuracy. Regression.
  - *A native netplay build* — mGBA and RetroArch already do lockstep link-cable netplay, but
    that's a *different* thing: it syncs two instances of *one* cartridge frame-for-frame, not
    many independent save files sharing an overworld. Not what this project is.
- **Bundling / customizing:** the realistic long-term path if we outgrow the scripting API is
  a **lightly-patched mGBA distribution** shipped with the script and font preconfigured
  (one-click "install & play"), and eventually small native hooks (e.g. a cleaner overlay or
  a built-in server browser) contributed upstream or carried as a fork. We're not there yet —
  the scripting API still covers the near/mid-term goals, and a fork is a maintenance burden
  we only take on when a concrete feature can't be done in Lua.

Short version: **mGBA is the right base today**; a bundled/customized mGBA is a *packaging*
and *polish* step for later, not a prerequisite for the feature goals above.
