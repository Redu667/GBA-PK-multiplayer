# GBA-PK-multiplayer

This is a free mod that adds multiplayer interactions to the 3rd generation Pokémon games. Players can see, walk around, trade and battle with each other. Updates and more information can be found on YouTube, Patreon or PokéCommunity.

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

## Usage

1. Open your Gen 3 Pokémon ROM in mGBA.
2. Load `GBA-PK_Client ALPHA 4.lua` (to join a server) or `GBA-PK_Server ALPHA 4.lua` (to host) via **Tools → Scripting**.
3. Configure the `IPAddress`/`Port` (and, for romhacks, `RomHackBaseGame`) at the top of the file if needed.

## Links

- Patreon: https://www.patreon.com/user?u=81688818
- YouTube: https://www.youtube.com/channel/UCdXg0-BF9FblZ2GTi3u4orQ
- PokéCommunity: https://www.pokecommunity.com/showthread.php?t=484949
