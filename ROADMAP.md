# GBA-PK roadmap

Where multiplayer is today and where it's heading. [PokeMMO](https://pokemmo.com/) is
the reference point for the multiplayer feature set — not to clone it, but as a concrete
target for what "good" looks like.

## Where we are (v1.3.0)

- Real-time shared overworld: see other players walk, up to 8.
- Player-vs-player **trade** and **battle** over emulated link cable.
- Co-op **Soullocke** (soul-linked Nuzlocke) with shared fate.
- Player skins, in-session name/skin changes, D-pad menus with on-screen (0.11) UI.
- **Dedicated server** (`GBA-PK-Server.lua`) — a standalone relay so nobody has to host
  from inside their game.
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
- [ ] **Graceful reconnect** — rejoin after a drop and get your player id/state back.
- [ ] **Rooms/channels** — multiple independent sessions on one server; matchmaking by game
      family (FR/LG vs R/S/E) enforced server-side.

### Mid term — MMO-ish structure
- [ ] **Persistent identity** — accounts/nicknames the server remembers across sessions.
- [ ] **Global vs local visibility** — show only players on the same map/route (scales past 8).
- [ ] **Spectating** trades/battles; **matchmaking** queues for battles.
- [ ] **Trade/battle validation** on the server (prevent malformed or cheated packets).

### Long term — the ambitious PokeMMO-style bits
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
