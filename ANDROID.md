# GBA-PK on Android

The short version: **there is no Android GBA emulator we can simply plug the mod into**,
but there are two real ways to run *actual desktop mGBA* — scripting and all — on an
Android device, plus easy chat-only options. This page is honest about which is which.

## Why no Android emulator "just works"

The mod is a Lua script that needs mGBA's scripting API (memory read/write every frame,
sockets, input hooks, drawing). On Android:

- **RetroArch's mGBA core** can't load scripts — libretro cores don't expose mGBA's
  scripting. RetroArch does have a [UDP network-command interface](https://docs.libretro.com/development/retroarch/network-control-interface/)
  that can peek/poke memory from outside, but it isn't frame-synced (and has
  [known bugs](https://github.com/libretro/RetroArch/issues/16392)) — fine for a trainer
  or tracker, nowhere near enough to render other players every frame.
- **Standalone Android emulators** (My Boy!, John GBA, Pizza Boy…) are closed source with
  no scripting. The one unofficial mGBA Android port is dead.
- **Adding scripting to an open one (or porting mGBA ourselves)** is the
  fork-and-maintain trap this project explicitly stays out of — see the scope decision in
  [ROADMAP.md](ROADMAP.md). If official mGBA ever ships an Android frontend with script
  loading, the mod should largely just work there; that's the upstream path we watch.

## Option A — Windows mGBA under Winlator / GameHub Lite (full mod)

Wine-based Windows emulation layers for Android (Winlator, GameHub Lite) can run the
regular **Windows mGBA 0.11** build, scripting included — a community report of exactly
this (an mGBA netplay build with scripts, for Battle Network) is
[mgba-emu/mgba#3743](https://github.com/mgba-emu/mgba/issues/3743); the one trick noted
there is setting the Windows version to **Windows 7** in the emulation settings, since
"mgba 0.11+ don't like 10/11".

- GBA emulation is light, so emulator-inside-emulator is realistic on a mid-range phone.
- Load `GBA-PK.lua` from the scripting window as on PC; the on-screen menu, chat feed and
  typed chat all come along (Winlator has an on-screen keyboard and touch/controller
  mapping).
- *Status: community-proven for mGBA 0.11 + scripts in general; we haven't verified the
  full mod on real hardware ourselves yet. Reports welcome.*

## Option B — Linux mGBA under Termux (full mod, no Windows layer)

[Termux](https://en.wikipedia.org/wiki/Termux) + `proot-distro` Debian +
[Termux-X11](https://ivonblog.com/en-us/posts/termux-x11/) runs ordinary ARM-Linux
desktop apps on Android — including Debian's `mgba-qt` package.

- Debian stable currently ships mGBA **0.10**, so the mod runs at 0.10 level: full
  multiplayer, but the menu lives in the scripting console tab and chat is
  `say()`/companion-only (no on-screen overlay or typed chat until 0.11 lands in the
  distro).
- A Bluetooth controller or Termux-X11's touch keyboard drives the game.
- *Status: standard, well-documented tooling; we haven't benchmarked it ourselves.*

## Option C — chat only (easy)

No emulator at all, still in the conversation:

- **Web chat page** — if the server host enabled it, open the server's HTTP URL in any
  browser, pick a name, done (see [server/README.md](server/README.md)).
- **Discord bridge** — `chat/gba-pk-discord.py` connects the session's chat to a Discord
  channel; phones already have Discord.
- **Keyboard companion in Termux** — `chat/gba-pk-chat.py` is stdlib Python and runs fine
  in plain Termux.

## Practical notes for A/B

You still need your own ROM and save on the device, same as on PC. Sessions are the same
server, same protocol — an Android player through Winlator/Termux is just another client;
the server can't tell the difference.
