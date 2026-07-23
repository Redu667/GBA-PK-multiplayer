# GBA-PK roadmap

Where multiplayer is today and where it's heading. [PokeMMO](https://pokemmo.com/) is
the reference point for the multiplayer feature set — not to clone it, but as a concrete
target for what "good" looks like.

## Scope (decided v2.2.0, after surveying the field)

We looked at how every notable Pokémon multiplayer project is built before deciding how
far to push this one. The short version:

- **The projects with MMO-grade UI all own their entire client.** PokeMMO is a custom
  Java/OpenGL engine that uses your ROMs as asset files (14+ years of development);
  Pokemon Revolution Online and PokeOne are from-scratch Unity clients; Pokemon Showdown
  is a website. None of them render inside a real emulator — that's the only reason
  their chat and menus look the way they do.
- **At our tier (emulator scripts and romhacks), nobody has in-game chat at all.** The
  strongest comparable — Pokémon Emerald Rogue, which controls the full game source via
  the decomp — still chose stock mGBA plus an external companion app, and has no chat
  three years in. Archipelago and mGBA-http put all text in a companion window too.
- **Hobby emulator forks die.** Every fork we found (tpp-BizHawk2, VBALink) is
  abandoned; every living project sits on a stock emulator. Meanwhile mGBA upstream has
  networked link-cable support milestoned for 0.12 — the platform is moving toward us.

**The decision:** GBA-PK stays a *multiplayer mod* — one Lua script on stock mGBA, a
dedicated server, and companion apps. A custom client or emulator fork is permanently
off the table. The good news from the same research: mGBA 0.11's scripting additions
(`canvas` for drawing, `input`/key events for real keyboard input) are enough to build
a typed in-window chat box and properly skinned menus in pure Lua — the two things that
seemed to demand a fork don't.

## Where we are (v2.2.0)

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
      bottom of the game.
- [x] **Typed in-window chat** *(v2.2.0)* — on mGBA 0.11+, press the chat key (default
      `T`) and type with your real keyboard into an on-screen compose box; Enter sends,
      Esc cancels, and the game's controls are muted while you type.
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
3. **Guided travel** — polish step 2 into an in-menu "travel" flow that walks you
   through the ROM swap (and, where scripting allows, pre-fills the rejoin). A tiny
   *launcher* script next to mGBA could automate the swap without touching the emulator
   itself; a custom mGBA build is out of scope (see the scope decision above).

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

### Long term — aspirational

These are the features that separate a *mod* from an *MMO*, and the projects that have
them are decade-scale efforts with teams. They stay on the list as direction, not as
commitments — none of them should be started at the cost of polishing what exists.

- [ ] **Spectating** trades/battles — needs battle-UI state injection on the client, which
      is deep game work; deferred from mid term.
- [ ] **Shared economy / GTS-style trading** brokered by the server.
- [ ] **Server-authoritative anti-cheat** (the client can't be trusted for competitive play).
- [ ] **Cross-map "overworld hub"**, events, seasonal content.

These get progressively harder because Gen 3 games weren't built for it — the further right
we go, the more the server has to become the source of truth rather than a relay.

## Emulator: stock mGBA, permanently

**Decision (v2.2.0): stock mGBA is the platform. No fork, no custom client — ever for
the former, and the latter would be a different project.** See the scope section at the
top for the research behind this.

- **Why mGBA:** it's the only mainstream emulator with a Lua scripting API rich enough to do
  all of this from a single script — memory read/write, input hooks, sockets, and (0.11) an
  on-screen canvas plus raw keyboard/mouse input events. It's actively maintained,
  cross-platform, and accurate. The whole mod is ~16k lines of Lua running inside it; there
  is no comparable scripting surface elsewhere.
- **Alternatives considered:**
  - *BizHawk* — strong Lua too (its `forms` API even has real textboxes), but Windows-first
    and heavier; no clear win over mGBA and a full rewrite of the script's emulator interface.
  - *VBA-M / others* — weaker/older scripting, worse accuracy. Regression.
  - *A native netplay build* — mGBA and RetroArch already do lockstep link-cable netplay, but
    that's a *different* thing: it syncs two instances of *one* cartridge frame-for-frame, not
    many independent save files sharing an overworld. Not what this project is.
- **What 0.11 scripting unlocks:** the `canvas`/`image` APIs (which draw the on-screen menu
  and chat feed) plus the `input` API and `key` events (raw keyboard, unicode codepoints,
  modifiers) mean **typed in-window chat and image-quality UI are possible in pure Lua**.
  The two features that once seemed to require a fork don't.
- **Companion apps:** the server speaks a simple TCP protocol, so *anything* can join it —
  the keyboard chat companion (`chat/gba-pk-chat.py`, v2.1.0) and the **Discord bridge**
  (`chat/gba-pk-discord.py`) are the first two. A server-status web page would be the same
  pattern, and it's the ecosystem-standard shape (Archipelago, mGBA-http, Emerald Rogue's
  assistant all work this way). Companions are also the whole Android story for now: no
  Android GBA emulator exposes mGBA's scripting (RetroArch cores can't load scripts), so
  phones join the *chat* via Discord/Termux rather than the overworld — until upstream
  grows script support on Android.
- **Packaging (the surviving sliver of the old "bundling" idea):** a zip/installer that
  lays out *stock* mGBA + script + font + a preconfigured server list is still fair game —
  that's distribution, not a fork. Anything requiring us to compile a modified emulator
  is out.

Short version: **stock mGBA is the base, full stop**; if a need ever truly outgrows the
scripting API, the answer is contributing the missing primitive upstream, not forking.
