# Changelog

## v1.2.0

- **Set the host IP from the menu.** The connect menu has a new **Set IP** entry with a D-pad
  editor (Up/Down change a digit or dot, Left/Right move, A confirms) so you can point **Join**
  at any address without touching the scripting box. `join("ip")` still works too.
- **In-session menu.** Press **Select** while hosting or connected to open a new in-game menu
  with **Set name**, **Set skin** and **Disconnect** — so you can change how you look or what
  you're called without leaving the session. (Host/Join/Soullocke setup only apply before you
  connect, so they're not shown here.) Skin changes ride out in the normal position packet, so
  everyone sees your new look live; name changes send a nickname update to the other players.
  `setname()` in the scripting box now also broadcasts mid-session.
- **Tidier on-screen menu.** The overlay menu used oversized text that filled the screen and
  clipped the title. Type is smaller and rows are tighter now, so the whole menu fits neatly and
  the console-style `=====` title decoration is dropped on screen.

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
