# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A fork of the **Witcher Online** mod (a presence-only multiplayer mod for The Witcher 3: Wild Hunt)
that adds **true co-op NPC sync** on top of it — a "Dark Souls" shared-world model where the GUEST
hides its own NPCs and instead sees the HOST's NPCs as synced "marionette" copies it can fight,
loot, and share a world with. The upstream mod intentionally syncs only player ghosts; this fork
goes past that line.

All the co-op work lives in **`witcher/mods/modWitcherOnline/content/scripts/local/spike_marionette.ws`**.
The other big mod scripts (`client.ws`, `remotePlayer.ws`) are the upstream mod — read them for
reusable patterns, but the co-op logic is in spike_marionette.ws.

**Read these design docs before substantial work** (they encode hours of hard-won knowledge):
`SPIKE.md`, `LEGACY_MOD_STUDY.md`, `REDKIT_COOP_RESEARCH.md`, `CODE_REVIEW_V57.md`.

## Architecture: three processes, two devices

```
The Witcher 3 (witcher3.exe)                 The Witcher 3 (witcher3.exe)
  WitcherScript (.ws mod)        PC=HOST        WitcherScript (.ws mod)     Deck=GUEST
     ↕ TCP :37001 (-debugscripts)                  ↕ TCP :37001
  WitcherOnlineClient.asi (C++ DLL)             WitcherOnlineClient.asi
     ↕ UDP :40000                                  ↕ UDP :40000 (WiFi)
        └──────────────► WitcherServer.java (Java relay, runs on PC) ◄──────────┘
                          rebroadcasts all player/NPC/event packets every 50ms
```

- **WitcherScript** has all game logic but can't do networking. It emits state via `Log("<tag> ...")`
  and receives commands when the DLL injects `exec function` calls.
- **C++ DLL** (`client/`) is the bridge: reads the game over the W3 debug-scripts TCP protocol
  (`DebugExecClient`), talks UDP to the server (`g_client`, ASIO). `dllmain.cpp` is the main loop.
- **Java server** (`server/`) is a dumb relay: stores each player's last state, rebroadcasts to all.

### Roles
`WO_IS_GUEST()` in spike_marionette.ws is the single role flag: PC=`false` (host), Deck=`true`
(guest). The deploy script flips it for the Deck build. Almost all asymmetry derives from it.

### Wire protocol (key opcodes, tab-separated UDP)
- `UPDATE1A/1B/2A/2B/3` — player ghost state (upstream mod; `_s..._e` wraps spaced values, `half`
  splits the packet). **Never change these field counts** — it crashes the upstream `wo_update()`.
- `UPDATE_NPC` — our NPC sync (stored, rebroadcast). Chunk: `<id> <x_cm> <y_cm> <z_cm> <alive> <yaw>
  <hp%> <appearance> <type>`, chunks joined by `|`; we own this format, extend it freely.
- `UPDATE_HIT` — our combat hits (transient, immediate broadcast, not stored).
- `UPDATE_EXEC` — our **verbatim exec relay** (transient): the host enqueues exec code strings
  (`wo_give_item('Drowner brain',1)`); the receiving DLL injects them as-is. This is the channel for
  any typed cross-player action.

### The string→name unlock (critical, reused everywhere)
WitcherScript has **no runtime string→name conversion in expressions**. BUT the engine's exec-arg
binder converts a string token to a `name` when invoking an `exec function f(x : name)` (that's how
the console's `additem` works). The DLL injects exec calls over the same channel, so the host builds
`wo_give_item('Item Name', 1)` and the guest's engine binds the string→name. This is how items,
weather names, and (planned) NPC equipment cross the wire as names.

## Build & deploy

**Toolchain paths** (see `memory` notes / `SPIKE.md`):
- JDK 21: `C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot\bin\{java,javac}.exe`
- MSBuild: `C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe`
- Game: `D:\SteamLibrary\steamapps\common\The Witcher 3\` (next-gen, Steam)
- REDkit (data/templates): `D:\SteamLibrary\steamapps\common\The Witcher 3 REDkit\r4data\`

**Build the Java server:**
```
javac -d server/build server/src/*.java
java -cp server/build WitcherServer          # binds UDP 40000
```

**Build the C++ DLL — use PowerShell, NOT bash** (MSYS mangles `/p:` MSBuild args into paths):
```powershell
& $msbuild client\MultiplayerClient.sln /p:Configuration=Release /p:Platform=x64 /p:OutDir=build\
# -> client\build\WitcherOnlineClient.asi
```
Deploy the .asi to BOTH `bin\x64\` and `bin\x64_dx12\` under the game dir.

**Deploy WitcherScript (the common case — WS-only changes need no rebuild):**
Run `deploy-coop.ps1`. It copies the repo spike file to the PC game dir (host, `WO_IS_GUEST=false`),
writes a guest copy (`WO_IS_GUEST=true`, **UTF-8 no BOM**) to Downloads under a stable name, copies
the built .asi to the PC bin dirs + Downloads, and prints the 3 Deck `curl` lines. The Deck pulls
via curl (cache-immune); both devices then restart the game (WS recompiles on load — no hot reload).

**Required Steam launch options:** `-net -debugscripts` (opens the TCP :37001 the DLL needs).
DLL connection config: `witcher/bin/WitcherOnline/config.xml` (Username/ServerIP/Port).

**There is no test suite.** Verification is in-game on PC+Deck. The on-screen HUD shows a version
string (`V## g=Y/n ...`) bumped each iteration — confirm the running build by reading it. Diagnostic
values are surfaced in that HUD line or written to the game's `scriptslog.txt`.

## WitcherScript gotchas (each cost real debugging time)
- **`var` declarations must be at the top of a function**, never mid-body.
- **Can't assign to a field of a function's return value**: `theGame.GetX().field = y` → `L-value
  required`. Cache `var s = theGame.GetX(); s.field = y;`.
- **UTF-8 files MUST be written without a BOM** — a BOM breaks the WS parser (the deploy script
  handles this; never `Out-File -Encoding utf8` in PS 5.1, which adds a BOM).
- **`exec function`** is callable only from the console / debug-script TCP, not from regular WS code.
- **Never set a synced marionette `SetAttitude(..., AIA_Hostile)`** — a hostile monster marionette
  dives/burrows and VANISHES (collisions are off). Marionettes stay friendly DoNothing puppets;
  drive everything (position, anim, damage) explicitly over the wire.
- Marionette movement mirrors the upstream ghost mover: a long `AdjustmentDuration(ticket, 1.0)`
  SlideTo re-issued every frame (heavy damping = smooth), teleport only on huge desync.
- Cooked game scripts at `...\content\content0\scripts\` are **UTF-16** — search them with PowerShell
  `Select-String`, not ripgrep/Grep. The mod's own scripts and `.w2ent` ASCII are grep-able.
