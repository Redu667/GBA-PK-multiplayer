# GBA-PK-multiplayer

A free mod that adds multiplayer to the 3rd-generation Pokémon games. Players can see each
other, walk around together, trade, battle, and run a co-op **Soullocke** — all from a
single Lua script in mGBA. Works on the official FireRed/LeafGreen, Ruby/Sapphire and
Emerald ROMs (and many romhacks), including randomized ROMs.

## Supported games

The script auto-detects the loaded ROM and enables itself for all official Generation 3 games:

- **Pokémon FireRed** (1.0 / 1.1) and **LeafGreen** (1.0 / 1.1)
- **Pokémon Ruby** (1.0 / 1.1 / 1.2) and **Sapphire** (1.0 / 1.1 / 1.2)
- **Pokémon Emerald**

Japanese, French, German, Spanish and Italian releases of the above are recognised as well.

Players are matched by game family (FR/LG together, R/S/E together) so everyone shares the same map layout. This is controlled by the `SeperateGames` option near the top of the script.

## Romhack support (experimental)

Most Gen 3 romhacks are built on top of an official base game (usually FireRed or Emerald):

- **If the romhack keeps its base game's 4-letter game code, it is detected automatically** and simply works with the base game's memory layout.
- **If the romhack uses a custom game code** it won't be recognised on its own. Set the `RomHackBaseGame` option near the top of the script to the base game it was built from, and the script will treat the ROM as that game:

  ```lua
  local RomHackBaseGame = "BPR1" -- e.g. a FireRed-based romhack with a custom game code
  ```

  | Value  | Base game        |
  |--------|------------------|
  | `BPR1` / `BPR2` | FireRed 1.0 / 1.1 |
  | `BPG1` / `BPG2` | LeafGreen 1.0 / 1.1 |
  | `BPEE` | Emerald |
  | `AXV1` / `AXV2` | Ruby 1.0 / 1.1-1.2 |
  | `AXP1` / `AXP2` | Sapphire 1.0 / 1.1-1.2 |

  Leave it as `""` for normal auto-detection.

Romhacks that relocate RAM structures (for example, hacks that move the save blocks) may still need custom addresses; the override assumes the base game's memory layout.

## Getting started (up to 4 players)

Everyone uses the **same single file**, `GBA-PK.lua` — there is no longer a separate
client and server script.

1. Open your Gen 3 Pokémon ROM in mGBA (0.10.x or 0.11).
2. Load **`GBA-PK.lua`** via **Tools → Scripting → Load script…**
   - On **mGBA 0.11+**, keep `SourceSans3-Regular.otf` (bundled here) **next to
     `GBA-PK.lua`** — that lets the menu draw right on the game screen.
3. **Click the game window** and drive the menu with the emulator's buttons. On mGBA
   **0.11+** the menu appears **on the game screen**; on **0.10.x** it appears in the
   **GBA-PK** tab of the scripting window (keep that tab visible). Either way, while the
   menu is open your presses go **only to the menu** (your character won't move, Start
   won't open the game menu), and **Select** closes/reopens it. Use **D-pad Up/Down** and
   **A** to choose:
   - **Host a game** — others connect to your IP address.
   - **Join a game** — connect to the host's IP (set `ServerIP` in the config, or use
     `join("their.ip.address")`).
   - **Set name** — type a nickname with the D-pad (Up/Down change the letter, Left/Right
     move the cursor, **A** confirms, **B** backspaces).
   - **Set skin** — change how you look to other players. Use **Left/Right** to cycle
     through a curated set of the game's own overworld sprites (you keep looking normal to
     yourself; everyone else sees the skin). You can also type `setskin(id)` in the
     scripting box to use any raw overworld graphics id.

That's it. Up to 4 players (host + 3) can see, walk around, trade and battle with each
other in the overworld. Everyone must use the same port (default `4096`); the host may
need to port-forward it for players over the internet.

### Seeing other players

- **Skins animate.** Other players' chosen overworld skins walk with a full walk
  cycle (not a static frame) and face the direction they're moving, just like the
  normal protagonist. The curated skin lists are per game — FireRed/LeafGreen,
  Ruby/Sapphire and Emerald each use their own game's overworld sprites.
- **Battle indicator.** When another player is in a battle, a small **"!"** bubble
  appears above their overworld avatar so you can tell at a glance who's busy. It
  clears automatically when their battle ends.

> **Note on the menu:** the menu is drawn through a swappable backend. On **mGBA 0.11+** it
> uses the canvas/painter scripting API to draw **on the game screen** (`ScreenMenuUI`,
> needs the bundled font next to the script). On **0.10.x**, whose scripting API can't draw
> over the game, it falls back to the scripting window's **GBA-PK** tab (`ConsoleMenuUI`).
> Either way, while the menu is open the script **swallows the emulator's inputs** (via
> `keysRead` + `clearKeys`) so they drive only the menu and never leak into the game, and
> **Select** toggles it open/closed. The menu logic is identical across both backends.

### Configuration

The only things most people touch are at the very top of `GBA-PK.lua`:

```lua
local Role       = "menu"        -- "menu" (choose in-game), "host", or "join"
local Nickname   = ""            -- up to 10 chars. Blank = use your in-game name.
local ServerIP   = "127.0.0.1"   -- the host's IP address (only used when joining)
local Port       = 4096          -- must be the same for everyone
local MaxPlayers = 4             -- players per session (supports up to 8)
```

### Commands

You can also drive everything by typing in mGBA's scripting box (type `help()` for the
full list):

| Command | What it does |
|---------|--------------|
| `host()` | Start hosting a game |
| `join("IP")` | Join a game at that IP (omit `IP` to use the configured one) |
| `setname("Name")` | Set your nickname |
| `who()` | List everyone in your session |
| `status()` | Show connection status |
| `disconnect()` | Leave the current session |
| `soullocke(on)` | Turn the Soullocke handler on/off (omit the arg to toggle) |
| `soul_dupes(on)` | Toggle the dupes clause |
| `soul_typerule(on)` | Toggle the primary-type restriction |
| `soul_autorelease(on)` | Toggle auto-removing dead linked mons from the party |
| `soul_status()` | Show the Soullocke state and current soul-links |

## Soullocke mode

A **Soullocke** is a co-op, soul-linked [Nuzlocke](https://bulbapedia.bulbagarden.net/wiki/Nuzlocke_Challenge):
two or more players run their games in parallel, the Pokémon they catch in the **same
area** are "soul-linked", and linked Pokémon **share fates** — if one faints (dies), its
partner dies too. This mod can run that bookkeeping for you automatically.

Turn it on from the **"Soullocke setup"** entry in the in-game menu (before you host or
join), or with `soullocke(true)` in the scripting box. Everyone in the session should
enable it.

**What it automates**

- **Auto soul-linking.** When you catch a Pokémon, it's broadcast to the other players.
  The first catch each player makes in a given area (its met location) forms a soul-link,
  and you'll see `Soul-linked (area N): your NICK <-> DIXIE's NICK` in the console. Links
  are rebuilt automatically whenever players connect, so they survive across sessions
  without any save file of their own.
- **Shared fate.** When a linked Pokémon faints, the handler marks it dead and tells the
  other games, which **faint the linked partner(s)** so nobody can keep using half a link.
  Revived "dead" Pokémon are re-fainted (no revives).
- **Same team, same box.** When you bench a linked Pokémon (move it to the PC) or add it
  back to your team, the other players are told to do the same with their linked partner,
  so soul-linked Pokémon stay together on the team or in the box.
- **Rule reminders.** Catching a second Pokémon in an area, catching a species you already
  own (dupes clause), blacking out, and "nickname everything" are surfaced as console
  notes as they come up.

**Options** (in the setup menu, or via the commands above)

| Option | Default | Meaning |
|--------|---------|---------|
| Soullocke | off | Master switch for the handler |
| Dupes clause | **on** | Notes when your encounter is a species you already own, so you may skip it and re-encounter (recommended on) |
| Primary-type rule | off | Warns if two team members share a primary type (recommended off, especially with 3+ players) |
| Auto-release dead | off | When on, dead linked Pokémon are removed from the party automatically; when off, you box/release them yourself |

You can also set the defaults at the top of `GBA-PK.lua` (`Soullocke`,
`SoullockeDupesClause`, `SoullockeTypeRestriction`, `SoullockeAutoRelease`).

**Works with randomized games.** The handler only reads structural game state — party
data, HP, met location, and the ROM's base-stat table for types — so it works unchanged on
ROMs randomized with tools like the
[Universal Pokémon Randomizer (FVX)](https://github.com/upr-fvx/universal-pokemon-randomizer-fvx).
Nothing assumes a specific species list. For soul-links to line up, everyone should play
the **same base game** (areas are matched by the game's met-location ids).

**Notes and limits**

- Soul-links are matched by area, so players should catch together, on the same game.
- Catching with a **full party** (the catch goes straight to the PC) isn't detected as a
  new link — box a slot first, as you normally would in a Nuzlocke.
- The handler reads Pokémon **in the party** and prompts you to box/withdraw/release to
  keep links in sync; it doesn't move Pokémon in your PC for you (writing PC storage safely
  across every ROM and romhack isn't guaranteed), so you perform the box moves yourself when
  prompted. A boxed partner of a fallen Pokémon is likewise flagged for you to release.

## Support

If you'd like to support the project: https://ko-fi.com/ynnead
