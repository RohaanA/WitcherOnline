# Code Review — spike_marionette.ws (V57 cleanup pass, 2026-06-01)

Reviewed & cleaned the main co-op script. Backup of the pre-cleanup working file:
`...\local\spike_marionette.v56.bak` — restore it if V57 misbehaves.

## What was removed (dead code, ~292 lines)
All verified unreferenced (brace balance preserved 142/142, zero dangling refs):

| Removed | Why dead |
|---|---|
| `WO_FindSpikeMarionette`, `WO_DoSpawnMarionette`, `wo_spike_spawn`, `wo_spike_marionettize_near`, `wo_spike_move_rel`, `wo_spike_aggro`, `WO_DoDestroyAll`/`wo_spike_destroy`, `WO_DoSwitchHostile` | Spike #1-2 manual console test commands — superseded by the network NPC sync. Never called by the DLL. |
| `wo_spike_net10hz`, `wo_spike_render60hz`, `WO_StartSmoothMotion`, `WO_StopSmoothMotion` | Spike #3 old "smooth motion" demo (orbiting test marionette). Superseded by `wo_npc_render60hz` + `WO_MoveMarionette`. |
| `WO_SpikeState.curr_pos / target_pos / has_state` | Only read by the removed smooth-motion timers. |
| `WO_GiveHeadIfHumanoid` | Defined, never called. (We spawn real templates that already have heads.) |

## Live architecture (what remains, in order)
- **Role/util:** `WO_IS_GUEST` (deploy flips), `WO_GameBusy`, `WO_StopAI`, `WO_StartsWith`, `WO_StrContains`.
- **Type/loot/weapon:** `WO_MonsterTemplate` (appearance→template), `WO_GetMonsterTypeAbility` (mon_* fingerprint — EXACT type), `WO_TemplateForType` (type→template, preferred), `WO_TemplateForAppearance`, `WO_GrantLootForAppearance` + `WO_GrantItem`, `WO_MountWeapons`.
- **Marionette:** `WO_ApplyMarionetteSuppression` (immortal + collisions off + DoNothing + friendly + mount weapons), `WO_CreateRemoteMarionette`, `WO_MoveMarionette` (1s SlideTo — mirrors the base mod's ghost mover).
- **Host broadcast:** `WO_HostNpcRegistry` (+cached `types[]`), `WO_AssignNpcId`, `WO_IsBroadcastableNpc`, `WO_CollectNpcsNear`, `wo_get_npcs`.
- **Guest receive/render:** `WO_RemoteNpcEntry/Registry`, `WO_ParseNpcChunk`, `wo_npc_update`, `wo_npc_render60hz` (timer), `WO_DetectAndForwardHits`, `WO_DoGuestCleanup`, OnSpawned wraps.
- **Combat/hits:** `WO_HitQueue`, `WO_EnqueueHit`, `wo_get_pending_hits`, `wo_apply_hit`, `WO_ApplyHitChunk`, `WO_GetGuestGhost`.
- **Exec relay (item transfer):** `WO_ExecQueue`, `WO_EnqueueExec`, `WO_QueueGiveItem`, `wo_give_item` (name-param!), `wo_get_pending_exec`.
- **Combat-coop scaffolding:** `WO_MakeGhostsAttackable` (host marks guest ghost as a combat target — currently invulnerable, Step 2 pending).
- **Dev test harness (flags default false):** `WO_TEST_DROP`, `WO_TEST_LOCAL_NPCS`, `WO_TestAppearanceAt`, jump wrap.

## Remaining minor cleanup (low priority, left in to avoid untested-edit risk)
- Dead `WO_RemoteNpcEntry` fields after V56: `curr_pos`, `has_state` (written, never read), `hidden_prox` (unused), `smooth_interval` (EMA computed every update but unused since V56 fixed the slide to 1s), `face_yaw`/`face_init` (V56 rotates to `e.yaw` directly). Removing them is safe but requires also deleting their writes in `WO_CreateRemoteMarionette`/`WO_ParseNpcChunk`.
- `WO_SPIKE_AUTO_ENABLED()` — dead one-liner, harmless.
- The file header comment is garbled (cyrillic stripped to spaces in an earlier ASCII pass) — cosmetic.
- `WO_DoHitNearestRemote` — older manual hit helper; superseded by `WO_DetectAndForwardHits`. Verify unused before removing (may still be a console aid).

## Optimization notes
- **GetMonsterTypeAbility is cached** once per NPC in `WO_HostNpcRegistry.types[]` — good, no per-broadcast ability enumeration.
- `wo_get_npcs` does `GetActorsInRange` for the host + each ghost then an O(n²) dedup. Fine for current N (<~30). If NPC counts grow, switch dedup to a tag-based "already added this frame" mark.
- `wo_npc_render60hz` runs `WO_MoveMarionette` per entry at 60 Hz — the per-frame `Cancel`+`CreateNewRequest`+`SlideTo` is what the base mod does for its ghost, so it's proven OK.
- `smooth_interval` EMA in the parser is now dead work (computed, never read) — removing it is a tiny per-update win.
- Host registry (`actors[]`/`types[]`) grows unbounded over a session (never pruned). Long sessions = slow `WO_AssignNpcId` linear scan + memory. Consider periodic compaction of dead/never-seen entries.

## Risk / gotchas baked into the code (don't regress)
- **NEVER set a marionette `SetAttitude(..., AIA_Hostile)`** → drowners dive/burrow and VANISH (collisions off). Confirmed twice (V41, V47). HP-bar-via-attitude is permanently out.
- **No runtime string→name in WS expressions.** Item/appearance names off the wire can't be converted in script — BUT the engine's exec-arg binder converts them when the DLL injects `exec function f(x : name)`. That's how `wo_give_item` works and is the key to future name-based features.
- Marionettes are `AIM_Immortal`; death is host-driven (`alive=0` → `Kill`). Never apply a local damage action to them (V43: it killed them in one hit).
- Deck deploy: UTF-8 **no BOM** (BOM breaks the WS parser). `deploy-coop.ps1` handles it.

## Verdict
Core sync (position/type/kill/loot/item-transfer) is solid and the movement now uses the proven ghost-mover technique. The file is ~280 lines lighter and the live path is clear. Biggest open frontiers remain **monster-attacks-guest** (Step 2 damage sync) and **action/workspot animations** — see REDKIT_COOP_RESEARCH.md.
