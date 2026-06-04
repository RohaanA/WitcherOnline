# Combat AI research — "NPC attacks the guest" (the headline frontier)

Deep-dive (2026-06-04, 4 parallel research agents over the cooked W3 scripts + REDkit) into why
host NPCs **circle the guest's ghost but never swing**, and how to make the host's real combat AI
actually melee-attack it (the user chose the "pure engine AI" path over scripted attacks).

All cooked scripts are UTF-16 → search with PowerShell `Select-String`, not ripgrep.
Cooked root: `D:\SteamLibrary\steamapps\common\The Witcher 3\content\content0\scripts`.

## The mechanism (how W3 melee is gated)

W3 melee is governed by a **ticket system**. An attacker may only swing once it has been granted a
`TICKET_Melee` from its **TARGET's `CCombatDataComponent`**. Until then it holds `TICKET_Approach`
and circles. So "circle but never swing" = the melee ticket is never granted (or never requested).

The full gate chain (ordered), with the API to satisfy each from a host mod script:

| # | Gate | Proof (file:line) | Satisfy from script |
|---|------|-------------------|---------------------|
| 0 | Target noticed, alive, hostile, in ~10m | btTaskCombatTargetSelection.ws:54,83,146,180 | `npc.NoticeActor(t)`; `npc.SetAttitude(t, AIA_Hostile)`; keep `t.IsAlive()` |
| 1 | NPC runs its combat BT → calls `ObtainTicketFromCombatTarget('TICKET_Melee',N)` | combat.ws:1715; btTicket.ws:356 | NPC must actually be in its real combat tree (it is — it circles) |
| **2** | **`ShouldAskForTicket()` true → requires `target.GetGameplayVisibility()` for non-player targets** | **btTicket.ws:160** | **`target.SetGameplayVisibility(true)`** |
| 3 | Target's `TICKET_Melee` pool has free slots, not blocked | btTicket.ws:13; combat.ws:2557 (block) | `cd.TicketSourceOverrideRequest('TICKET_Melee',400,0.0)` |
| 4 | NPC in range / reachable | btTicket.ws:398-453; btTaskAttack.ws:253 | valid navmesh + correct synced position |
| **5** | **`btTaskAttack.IsAvailable()` → same `!target.GetGameplayVisibility()` veto** (`unavailableWhenInvisibleTarget` default true) | **btTaskAttack.ws:57,520** | **`target.SetGameplayVisibility(true)`** |
| 6 | (no encounter/reaction-manager gate — reaction is post-swing) | btTaskAttack.ws:181 | nothing |

**The standout: gate 2 + gate 5 are the SAME flag** — `btTicket.ws:160`:
```
if ( target != thePlayer && !target.GetGameplayVisibility() && !owner.HasTag('regis') )
    return false;
```
For any target that is **not the local `thePlayer`**, gameplay-invisible ⇒ no melee ticket requested
AND the attack task is unavailable. This is exactly why it works in single-player (target = thePlayer,
exempt) but not for a remote-player ghost. Three of four agents flagged this independently.

## The hard problem: the ghost may have NO ticket pool

The guest ghost is spawned by the base mod from `dlc\dlc_mpmod\data\entities\geralt_npc.w2ent`
(base mod client.ws:2056). Findings about it:
- Runtime class: **`CNewNPC`** (template root `entityClass.CNewNPC`).
- Has: `CMovingPhysicalAgentComponent` (navmesh), `CR4HumanoidCombatComponent`, inventory, appearance.
- **Has NO baked combat AI tree**, and **`CCombatDataComponent` is NOT serialized in the template**
  (neither is it in a normal bandit template — it's **engine-created when an NPC's combat AI activates**).
- Because the ghost has no combat AI, the engine likely **never attaches a `CCombatDataComponent`**, so
  `g.GetComponentByClassName('CCombatDataComponent')` probably returns **NULL** → there is no melee
  ticket pool to flood, and gate 3 can't be satisfied from script.
- WitcherScript has **no API to add a native `CCombatDataComponent`** to an entity. It's engine-only.

So the pure-AI melee may be blocked not by our config but by the ghost's nature (a no-AI puppet).
**The decisive unknown is the in-game `CD=Y/n` reading** (added to the host HUD in V80).

## What V80 ships (the combined pure-AI fix + diagnostic)

`WO_MakeGhostsAttackable()` (host, every ~1s) now:
1. **`g.SetGameplayVisibility(true)` EVERY cycle** (was once) — the key melee gate; base mod sets the
   ghost invisible at spawn AND on dismountHorse, so re-assert it. (remotePlayer.ws:993, 5521.)
2. `AIM_Immortal` + heal to full each cycle (real HP lives on the guest; host ghost never dies / never
   hits a low-HP finisher).
3. **Ticket pool flood** (Melee/Charge/Special/Approach, +400 @ 0.0 importance, clear-before-reissue to
   avoid leaking request ids) + `ForceTicketImmediateImportanceUpdate('TICKET_Melee')` — the shipped
   horseRiding.ws enable-pattern. **No-ops if the ghost has no CCombatDataComponent.**
4. **Diagnostic** → host HUD `ghost[...]`: `CD=Y vis=1 atk=N` (component found, pool exists, N attackers
   registered) or `CD=n vis=1` (no component — pure-AI path is engine-blocked).

`WO_ApplyHitChunk()` (forwarded guest hit) now also force-targets the ghost on the struck NPC:
`SetAttitude(ghost, AIA_Hostile)` + `NoticeActor(ghost)` + `SignalGameplayEventParamObject('ForceTarget',
ghost)` + `SignalGameplayEvent('AI_RequestCombatEvaluation')` — the shipped quest pattern
(quest_attitude.ws ForceTargetQuest; aiStorage.ws NewTempHostileActor).

## DECISION TREE — read the host HUD `ghost[...]` first

- **`CD=Y vis=1 atk=N` (N>0) and NPC now SWINGS** → solved. Next: damage-to-guest (read the ghost's HP
  loss on the host each hit → relay → guest `GainStat(BCS_Vitality,-dmg)` + clamp HP≥1).
- **`CD=Y vis=1 atk=0`** → component exists but no attacker registered: target-selection/force-target
  issue. Reinforce ForceTarget every cycle for NPCs in combat near the ghost; check attitude.
- **`CD=Y vis=1` but still circles** → ticket importance/range; try a NEGATIVE importance mod
  (`TicketSourceOverrideRequest('TICKET_Melee', 400, -10000.0)`) to drop the gate below any attacker.
- **`CD=n`** (most likely per the template evidence) → the ghost has no ticket pool; the pure-AI melee
  is engine-blocked. Options, in order:
  1. **Give the ghost a real combat presence** so the engine creates the component — but geralt_npc has
     no combat AI tree, so this needs a different/combat-capable template or attaching an AI. Risky
     (CLAUDE.md: hostile/combat NPC with collisions off "dives/burrows and vanishes").
  2. **Proxy punching-bag**: host spawns a real combat NPC (has a CCombatDataComponent) pinned at the
     ghost's position, hostile+immortal; host NPCs attack IT (positions match so it looks right); read
     its HP loss as the damage-to-guest signal. Heavier but robust and keeps the real AI swinging.
  3. **Scripted attack fallback** (the user deferred this, but it's the guaranteed-visible path): for a
     host NPC in combat + in melee range + facing the ghost, force a real attack — the cleanest damage
     primitive is `btTaskDealDamage.ws:32-42` (`W3Action_Attack` with attacker=NPC, victim=ghost) — and
     drive the swing animation via the NPC's attack (our V77 IsAttacking sync then mirrors it to the
     guest). Not pure-AI, but host-authoritative and reliable.

## Key file:line index (for the next session)
- Ticket gate: `btTicket.ws:160` (visibility veto), `:13-23` (pools), `:104-166` (ShouldAskForTicket),
  `:356-466` (melee importance). Block pattern: `combat.ws:2540-2596` (BlockAllCombatTickets).
- Enable pattern: `horseRiding.ws:558-571` (TicketSourceOverrideRequest 400/0.0 + clear on dismount).
- Attack task: `btTaskAttack.ws:53-63` (IsAvailable visibility veto), `:65-184` (swing setup), `:253`
  (SlideTowards). Target selection: `btTaskCombatTargetSelection.ws:29-70` (ForceTarget/SetCombatTarget),
  `:83` (IsDangerous score), `:194-243` (event handlers incl. 'ForceTarget'/'UnforceTarget').
- Force-fight pattern: `quest_attitude.ws:65-101` (NoticeActor + 'ForceTarget'); `aiStorage.ws:170-189`
  (SetAttitude AIA_Hostile + 'AI_RequestCombatEvaluation').
- Component API: `components.ws` CCombatDataComponent (`TicketSourceOverrideRequest`,
  `TicketSourceClearRequest`, `ForceTicketImmediateImportanceUpdate`, `GetAttackersCount`,
  `GetTicketSourceOwners`). Accessor: `GetComponentByClassName('CCombatDataComponent')` (the typed
  `GetCombatDataComponent()` is r4Player-only).
- Scripted-damage primitive: `btTaskDealDamage.ws:32-42`; `btTaskTackle.ws:59-61`.
- Visibility: `actor.ws:1187-1194` (Set/GetGameplayVisibility), `:1501` (OnSpawned sets it true).
- Ghost spawn/config: base mod `remotePlayer.ws:983-1005` (spawnGhost), `:5521` (dismount re-hides).
