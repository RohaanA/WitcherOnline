# Contributing

Thanks for looking at the co-op fork! This is a research-grade prototype that's gone surprisingly far on
top of a presence-only mod, and it could use more hands. This guide gets you oriented fast.

## TL;DR for the impatient

- **All the co-op logic is one file:** [`witcher/mods/modWitcherOnline/content/scripts/local/spike_marionette.ws`](witcher/mods/modWitcherOnline/content/scripts/local/spike_marionette.ws).
- **Read [SPIKE.md](SPIKE.md) and [CLAUDE.md](CLAUDE.md) first** — they encode the hard-won gotchas.
- You need **two machines** (or two PCs) running The Witcher 3 to test — there is no single-machine path
  and no automated test suite. Verification is in-game.

## The big idea (host-authoritative marionettes)

The upstream mod syncs *players* as "ghosts" but keeps each player's world private. This fork makes the
**host** authoritative for NPCs and has the **guest** replace its own NPCs with synced copies of the host's:

- **Host (`WO_IS_GUEST()==false`)** broadcasts its nearby NPCs (position, type, appearance, HP, equipment,
  combat/attack flags) over a `UPDATE_NPC` channel we own.
- **Guest (`WO_IS_GUEST()==true`)** hides its own vanilla NPCs and spawns **marionettes** — friendly
  `DoNothing` puppets driven entirely over the wire (position via `SlideTo`, animation via slot anims,
  combat reactions via synced flags). Guests run **no NPC AI**; they mirror the host.

This keeps a single source of truth (the host) and avoids two clients simulating divergent worlds.

## Repo layout

| Path | What it is |
|------|-----------|
| `witcher/mods/modWitcherOnline/content/scripts/local/spike_marionette.ws` | **All co-op logic** (the file you'll edit most). |
| `witcher/mods/.../local/client.ws`, `remotePlayer.ws` | Upstream mod scripts — read for reusable patterns (the ghost mover, equipment, anim pipeline). |
| `client/` | The C++ DLL (`DebugExecClient`, `dllmain.cpp`) — bridges game ↔ relay. |
| `server/src/` | The Java relay (`WitcherServer.java`, ~1.3k lines). |
| `deploy-coop.ps1` | One-command host/guest deploy. |
| `tools/wo_log_server.py` | Tiny HTTP server: serves files to the guest AND collects its `scriptslog` for off-device debugging. |
| `*.md` research docs | See the table in the [README](README.md). |

## Key concepts you must know

1. **String→name unlock.** WitcherScript can't convert a string to a `name` in expressions, but the
   engine's exec-arg binder *does* when invoking `exec function f(x : name)`. The DLL injects exec calls,
   so the host builds `wo_give_item('Drowner brain', 1)` and the guest's engine binds the string→name. This
   powers items, weather, and any typed cross-player action (the `UPDATE_EXEC` "verbatim exec relay").
2. **The NPC wire chunk is ours** — extend it freely:
   `<id> <x_cm> <y_cm> <z_cm> <alive> <yaw> <hp%> <appearance> <type> <held> <combat> <attack>`. **Never**
   change the upstream `UPDATE1A/1B...` player packets' field counts — that crashes `wo_update()`.
3. **REDkit is ground truth.** Before hardcoding an item name, mount slot, monster type, or loot table,
   grep the REDkit `r4data` (templates `.w2ent`, item/loot defs `def_item_*.xml`). Guessing has burned us
   repeatedly; the data has answered every time. See [REDKIT_COOP_RESEARCH.md](REDKIT_COOP_RESEARCH.md).
4. **Combat is gated by a ticket system.** Host NPCs only melee a target that's gameplay-visible and holds
   a `TICKET_Melee`. Details in [COMBAT_AI_RESEARCH.md](COMBAT_AI_RESEARCH.md).

## WitcherScript gotchas (each cost real debugging time)

- `var` declarations must be at the **top** of a function, never mid-body.
- You **can't assign to a field of a function's return value** (`theGame.GetX().field = y` → "L-value
  required"); cache it in a local first.
- UTF-8 `.ws` files **must have no BOM** — a BOM breaks the parser (the deploy script handles this).
- `exec function`s are callable only from the console / debug-scripts TCP, not from normal WS code.
- **Never** set a synced marionette `SetAttitude(..., AIA_Hostile)` — with collisions off it dives/burrows
  and vanishes. Marionettes stay friendly puppets; drive everything explicitly.
- Cooked game scripts (`...\content\content0\scripts\`) are **UTF-16** — search with PowerShell
  `Select-String`, not ripgrep. The mod's own scripts and `.w2ent` ASCII are grep-able.

## Building & deploying

See [CLAUDE.md](CLAUDE.md) for exact paths. In short:

- **Java relay:** `javac -d server/build server/src/*.java && java -cp server/build WitcherServer`
- **C++ DLL (use PowerShell, not bash — MSYS mangles `/p:`):**
  `& $msbuild client\MultiplayerClient.sln /p:Configuration=Release /p:Platform=x64 /p:OutDir=build\`,
  then copy `WitcherOnlineClient.asi` into the game's `bin\x64` and `bin\x64_dx12`.
- **WS-only changes** (the common case) need no rebuild — `deploy-coop.ps1` pushes host + guest copies.
- Steam launch options on both: `-net -debugscripts`. DLL config: `witcher/bin/WitcherOnline/config.xml`
  (give each player a **distinct Username** — same-username collides in the relay).

## Testing & debugging without squinting at the HUD

The in-game HUD shows a version string (`V## ...`) but fades fast. `tools/wo_log_server.py` collects the
guest's `scriptslog.txt` onto the host so you can read both sides' logs off-device. The mod logs structured
markers (`WO_HB` heartbeat with version + ghost count, `WO_GHOST` combat diagnostics, `wo_npc` chunks) you
can grep.

## Good first contributions

- **Netcode reliability (highest impact):** make the host reliably spawn the guest's ghost across restarts
  (see "Where help is needed" in the README). This is the current blocker.
- Monster combat anims (the humanoid Geralt slot anims don't fit monsters).
- Cleanup of diagnostic/HUD spam once features stabilize.
- Multi-guest support (today's code assumes a single guest in a few places).

## Workflow

Fork → branch → PR. Describe what you tested in-game (this project lives or dies on real two-device tests).
Questions are very welcome — ping in the [Discord](https://discord.gg/AGXXvGNnH8) or open a PR/issue on the
fork.
