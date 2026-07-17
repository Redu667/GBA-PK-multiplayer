# Changelog

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
