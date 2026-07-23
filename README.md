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
   - **Join a game** — connect to the host's IP.
   - **Set IP** — type the host's IP with the D-pad (Up/Down change a digit or dot,
     Left/Right move the cursor, **A** confirms, **B** backspaces), then choose **Join**. You
     can also set `ServerIP` in the config or use `join("their.ip.address")` — both accept
     `host:port` too (e.g. a Railway TCP-proxy endpoint like `xyz.proxy.rlwy.net:31702`).
   - **Set name** — type a nickname with the D-pad (Up/Down change the letter, Left/Right
     move the cursor, **A** confirms, **B** backspaces).
   - **Set skin** — change how you look to other players. Use **Left/Right** to cycle
     through a curated set of the game's own overworld sprites (you keep looking normal to
     yourself; everyone else sees the skin). You can also type `setskin(id)` in the
     scripting box to use any raw overworld graphics id.

That's it. Up to 4 players (host + 3) can see, walk around, trade and battle with each
other in the overworld. Everyone must use the same port (default `4096`); the host may
need to port-forward it for players over the internet.

**Changing your name or skin mid-session.** Once you're hosting or connected, pressing
**Select** opens an in-session menu with **Set name**, **Set skin** and **Disconnect** — so
you can re-style or rename yourself without leaving the game. Skin changes appear to everyone
live; a name change is sent out to the other players too.

### Dedicated server (optional)

Instead of one player hosting from inside their game, you can run a small **standalone
server** that everyone connects to. Nobody plays "the host", and the session stays up even
if people come and go — better for bigger or longer-running lobbies.

1. Easiest: **deploy the [`server/`](server/) folder to Railway** — point a Railway
   service at this repo with Root Directory `server`, enable a TCP proxy on port 4096,
   done. Full steps (plus Docker and VPS options) are in **[server/README.md](server/README.md)**.

   Or run it yourself on a machine that stays on (a VPS, spare PC or Raspberry Pi) with
   Lua + luasocket (Debian/Ubuntu: `sudo apt install lua5.4 lua-socket`):

   ```sh
   lua server/GBA-PK-Server.lua            # port 4096, up to 8 players
   lua server/GBA-PK-Server.lua 4096 16    # custom port / player cap
   lua server/GBA-PK-Server.lua -v         # verbose (log every relay)
   lua server/GBA-PK-Server.lua 4096 32 --local=7   # big lobby: map-local past 7/room
   ```

   No ROM or emulator is needed on the server. Self-hosting needs the port (TCP, default
   `4096`) forwarded/open, exactly as a peer host would.
2. Each **player** just picks **Set IP** → the server's address, then **Join**. That's it —
   there's no separate "host". The mod detects a dedicated server automatically and won't add
   a phantom host player.

**Regions.** One server hosts **both game families at once**: FireRed/LeafGreen players
share the Kanto room, Ruby/Sapphire/Emerald players share the Hoenn room. Gameplay stays
within your region (you can't trade across families — the games can't do that), but **chat
and join/leave notices are shared**, so it's one community. To "travel", save, load your
other region's ROM and join again — the server keeps your name and rooms you by the game
you're now playing.

**Big lobbies.** Above `--local=N` players in a room (default 7), the server switches to
**map-local visibility**: you only see and sync with players on your current map (up to 8 at
once — the renderer's limit), and walking onto a map introduces whoever is there. Small
lobbies keep full visibility automatically. Use `channel("name")` to split off a private
lobby within your region, and `duel()` to queue for matched battles — the server pairs
queued players and announces the match in chat.

Peer hosting with `host()` still works exactly as before; the dedicated server is just an
alternative. See **[ROADMAP.md](ROADMAP.md)** for where multiplayer is headed.

**Chat.** On mGBA 0.11+, just press **T** in a session (configurable via `ChatKey` at the
top of the script): a Gen-3 style compose box opens at the bottom of the game screen and
you **type with your real keyboard** — Enter sends, Esc cancels. While the box is open your
keystrokes are muted for the game, so keys that double as controls never move your
character. Messages appear in the console and in an on-screen feed that fades after a few
seconds. (`say("your message")` in the scripting box works everywhere, including mGBA
0.10.x, with a dedicated server or a peer host.)
The server announces joins and leaves in chat, keeps nicknames unique (a duplicate shows as
`NAME(id)` to others), and exchanges heartbeats with clients so idle sessions stay alive and
a dead server is noticed within seconds. If your connection drops, the mod **reconnects
automatically** and the server gives you your player id and name back (it holds them for
2 minutes) — everyone else just sees "NAME reconnected".

**Chat from outside the game.** There's also a **chat companion** you can run in a terminal
(handy for a second monitor, or for friends who just want to talk):

```sh
python3 chat/gba-pk-chat.py tramway.proxy.rlwy.net:31702 YourName
```

It connects to the same server as a chat-only player: what you type shows up in everyone's
in-game chat feed (as `Name (CHAT): text`), and in-game chat prints in your terminal.
Python 3 only, no dependencies. It uses one player slot on the server.

**Discord bridge.** Connect your server's chat to a Discord channel with
`chat/gba-pk-discord.py`, so people on phones (or anywhere) can follow along and talk back:

```sh
# one-way (game -> Discord), no dependencies: paste a channel webhook URL
python3 chat/gba-pk-discord.py your.server:4096 --webhook https://discord.com/api/webhooks/...

# two-way (game <-> Discord), needs `pip install discord.py` and a bot token
python3 chat/gba-pk-discord.py your.server:4096 --bot BOT_TOKEN --discord-channel 123456789012345678
```

In two-way mode, Discord messages appear in everyone's in-game feed as
`Discord (CHAT): Name: text`, and all in-game chat (plus join/leave notices) flows to the
channel. Like the chat companion, it occupies one player slot.

**Web chat — phones just open a URL.** Every server can also serve a phone-friendly chat
page (`server/webchat.py`, bundled into the Docker/Railway image): give your Railway
service an HTTP domain and `https://your-app.up.railway.app` *is* the chat — pick a name,
type, and it lands in every player's in-game feed as `Web (CHAT): Name: text`, with all
in-game chat flowing back live. No app, no account. See [server/README.md](server/README.md).

**Playing on Android?** No Android GBA emulator can load the mod directly (no scripting
support in any of them), but real desktop mGBA — scripting and all — can run *on* an
Android device through Winlator/GameHub Lite (Windows build, mGBA 0.11, full mod) or
Termux + proot (Linux build). **[ANDROID.md](ANDROID.md)** walks through every option,
including the chat-only ones (web page above, Discord bridge, Termux companion) and why
we don't fork an Android emulator. On the PC itself you never leave the game to chat —
press the chat key and type.

**Your identity persists.** The mod stores your name and server identity in a small
`GBA-PK.identity` file next to the script, and the server remembers you in
`GBA-PK-Server.accounts` — so you can restart the emulator, your PC or the server and come
back as yourself ("Welcome back, NAME"), with your nickname protected even while offline.

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
| `say("msg")` | Send a chat message to everyone in the session |
| `chat()` | Open the typed chat box (mGBA 0.11+; or just press the chat key, default `T`) |
| `channel("name")` | Switch to a named channel on a dedicated server (empty = main) |
| `duel()` | Queue for a matched battle on a dedicated server |
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
