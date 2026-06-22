# Witcher Online — Co-op / NPC-sync fork

> A fork of [Witcher Online](https://www.nexusmods.com/witcher3/mods/11590) that adds the one thing its
> README says is missing: **"Co-op, world, and NPC sync."** It turns the presence-only multiplayer into a
> Dark-Souls-style **shared world** where a guest sees and fights the host's NPCs.

**Status:** working cross-device prototype (PC host ↔ Steam Deck guest over WiFi). **Actively looking for
collaborators** — see [CONTRIBUTING.md](CONTRIBUTING.md) and **[Where help is needed](#where-help-is-needed-)** below.

💬 Base-mod community: [Witcher Online Discord](https://discord.gg/AGXXvGNnH8)

---

## Why this fork

The upstream mod is intentionally **presence-only** — you see other players "on the path", but every player
has their own private copy of the world: NPCs, monsters, quests. This fork goes past that line with a
**host-authoritative shared world**:

- The **host (PC)** owns the real NPCs and the AI.
- The **guest (Deck)** hides its own NPCs and instead sees the host's NPCs as synced **"marionette" copies**
  it can walk among, loot, and fight.
- The host's single AI is the only authority; guests **mirror** it — no divergent per-client AI.

## What works today

- **Shared NPCs:** the guest renders the host's nearby NPCs with the **correct type & appearance**, pulled
  from REDkit ground-truth (the `mon_*` ability fingerprint + entity templates), not guesswork — this fixes
  type collisions like wild_dog vs pet dog. Smooth movement (the base mod's 1-second `SlideTo` mover),
  rotation, HP, and equipment (weapons in-hand / sheathed on the hip, torches) all sync.
- **Shared mechanics:** kill-loot by monster type, **cross-device item transfer**, and **time-of-day +
  weather sync** — all riding a *verbatim exec relay* that breaks WitcherScript's string→name wall via the
  engine's exec-arg binder (the same trick the console's `additem` uses).
- **The headline — host NPCs fight the guest:**
  - Combat **stance + draw + attack-swing** animations mirrored onto the guest's marionettes via slot
    animations, driven only by the host's synced `IsAttacking()` (no local AI).
  - Host NPCs actually **commit melee attacks** against the remote-player ghost. The blocker turned out to
    be W3's combat **ticket system** (`btTicket.ws`): a non-player target that is gameplay-invisible never
    gets a `TICKET_Melee`, so it only circles. Re-asserting `SetGameplayVisibility(true)` every frame +
    forcing the combat target unlocks real attacks.
  - **Damage relayed back to the guest** (floored so you never die in co-op).

## Installation & Setup

You do not need to build the mod yourself. Download the ready-to-play files from the **[Releases](../../releases)** tab on GitHub.

### 1. Download Files
- **For the Host (PC):** Download `WitcherOnline-Host.zip`
- **For the Guest (Deck/Friend):** Download `WitcherOnline-Guest.zip`

### 2. Network Setup (Tailscale Example)
Since the server uses UDP port 40000, the easiest way to play together without port forwarding your router is using a free Virtual LAN tool like [Tailscale](https://tailscale.com/).
1. Both the Host and the Guest must install Tailscale and log in to the same Tailscale network.
2. Once connected, copy the **Host's Tailscale IP Address** (it usually starts with `100.x.x.x`).

### 3. Install the Mod
1. Extract your downloaded zip file.
2. Copy the **contents** of the `game` folder directly into your Witcher 3 installation directory (e.g., `C:\Program Files (x86)\Steam\steamapps\common\The Witcher 3\`).
3. Open `<game_directory>\bin\WitcherOnline\config.xml` in a text editor.
   - **Host:** Set `<ServerIP>` to `127.0.0.1`
   - **Guest:** Set `<ServerIP>` to the **Host's Tailscale IP Address**.
4. In Steam, right-click The Witcher 3 -> Properties -> Launch Options, and add: `-net -debugscripts`

### 4. Start the Server (Host Only)
Extract the `server` folder anywhere on your PC. Double-click `start_server.bat` to launch the relay server. Keep this window open while playing!

## Architecture

```
The Witcher 3 (host = PC)                       The Witcher 3 (guest = Deck)
  WitcherScript mod  ── TCP :37001 ──┐       ┌── TCP :37001 ──  WitcherScript mod
  WitcherOnlineClient.asi (C++ DLL)  │       │   WitcherOnlineClient.asi
            └──────── UDP :40000 ────┴───────┴──── UDP :40000 ────────┘
                            WitcherServer.java (relay — rebroadcasts state)
```

- **WitcherScript** has all the game logic but can't network — it emits state via `Log(...)` and receives
  commands when the DLL injects `exec function` calls.
- **C++ DLL** bridges the game (debug-scripts TCP) and the relay (UDP).
- **Java relay** is a dumb rebroadcaster.

All the co-op logic lives in
[`spike_marionette.ws`](witcher/mods/modWitcherOnline/content/scripts/local/spike_marionette.ws).

## Where help is needed 🙏

- **Netcode reliability (top priority):** the base player-presence sync — the host spawning the guest's
  "ghost" — is **intermittent across restarts**. Sometimes the host never spawns the guest's ghost and
  co-op silently breaks, because the whole feature hinges on that ghost existing on the host. Needs people
  who know the **DLL ↔ relay** path.
- **WitcherScript / behavior-graph internals:** richer combat mirroring, monster attack anims (the Geralt
  slot anims only cover humanoids), workspot / action-animation sync.
- **Testing** on more hardware and with more than two players.

## Build & run

See **[CLAUDE.md](CLAUDE.md)** for exact toolchain paths and build/deploy commands, and **[SPIKE.md](SPIKE.md)**
for the full design log. Short version:

- **Java relay:** `javac -d server/build server/src/*.java && java -cp server/build WitcherServer` (UDP 40000)
- **C++ DLL:** build `client/MultiplayerClient.sln` (Release / x64) → copy `WitcherOnlineClient.asi` into the
  game's `bin/x64` + `bin/x64_dx12`.
- **Mod:** the co-op script is `spike_marionette.ws`; `WO_IS_GUEST()` is the single role flag (PC=false,
  guest=true). `deploy-coop.ps1` automates the host/guest deploy.
- **Steam launch options:** `-net -debugscripts`.

## Design & research docs

Hard-won knowledge — read before substantial work:

| Doc | What's in it |
|-----|--------------|
| [SPIKE.md](SPIKE.md) | Canonical design log, WitcherScript gotchas, roadmap. |
| [COMBAT_AI_RESEARCH.md](COMBAT_AI_RESEARCH.md) | The combat **ticket system** and how host NPCs attack the guest. |
| [REDKIT_COOP_RESEARCH.md](REDKIT_COOP_RESEARCH.md) | REDkit data findings (types, loot, appearances). |
| [LEGACY_MOD_STUDY.md](LEGACY_MOD_STUDY.md) | How the base mod's sync / equipment / animation pipeline works. |
| [CLAUDE.md](CLAUDE.md) | Architecture + build/deploy + WitcherScript gotchas (quick reference). |

## Credits

Built on **[Witcher Online](https://github.com/rejuvenate7/WitcherOnline)** by **rejuvenate7** and its
contributors, which itself builds on **werasik2aa**'s
[multiplayer implementation](https://github.com/werasik2aa/Witcher3-Multiplayer). The upstream README (base
mod features, install, MMO mode) is preserved in **[UPSTREAM_README.md](UPSTREAM_README.md)**.

This fork is a community effort to take Witcher Online into true co-op. If that's something you want — come
help. 🐺
