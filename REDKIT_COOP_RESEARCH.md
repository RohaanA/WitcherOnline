# REDkit / Script-API Research for True Co-op (2026-06-01)

Goal: "shared world participation" co-op. This documents what the game's scripts/data make
possible — especially things we previously thought were blocked. Sources: cooked scripts at
`...\The Witcher 3\content\content0\scripts` (UTF-16) and REDkit data `...\REDkit\r4data`.

> **Note:** REDkit ships NO `.ws` scripts (r4data is data only: characters/ templates,
> gameplay/ defs, living_world, quests). The script API surface == the cooked game scripts.
> REDkit's value to us is its **data** (templates, loot tables) + the **uncooked binaries**
> whose ASCII we can grep to learn entity structure (that's how we found the `mon_*` type
> fingerprints and loot-container names).

---

## 0. TL;DR — three things we thought were impossible but aren't

1. **Appearance VARIANT matching** (dog_05, the exact guard outfit, etc.). `SetAppearance(name)`
   exists on CActor. We can't string→name in WS expressions, but the **engine's exec-arg binder
   does** — exactly how our `wo_give_item('Drowner brain',…)` works. So a `wo_set_app(tag,'dog_05')`
   injected by the DLL would set the precise variant. **This closes most remaining visual fidelity.**
2. **Dealing damage TO the guest** (the core of "monster attacks me"). `thePlayer.GainStat(BCS_Vitality, -dmg)`
   directly subtracts HP; `SetCanPlayHitAnim(true)` + the damage manager play the hit reaction.
3. **Scripted attacks without combat AI.** `W3Action_Attack` + `theGame.damageMgr.ProcessAction()`
   applies a full attack (damage + hit anim + FX) on command — no need to make the marionette
   hostile (which makes it vanish). The host's real NPC attacks; we RPC the hit to the guest.

---

## 1. Appearance variant matching (HIGH value, LOW-MED effort)

**APIs** (actor.ws / appearanceComponent.ws):
- `CActor.SetAppearance( appearanceName : name )`
- `CAppearanceComponent.ApplyAppearance( appearanceName : string )` ← takes a **string**! reachable via
  `(CAppearanceComponent)ghost.GetComponentByClassName('CAppearanceComponent')`. If this works at
  runtime it sidesteps the binder trick entirely — **worth testing first**, it's the cleanest path.
- `GetAppearance() : name` (already used host-side).

**Design:** host already sends `a.GetAppearance()` per NPC. Guest, after spawning the template,
calls `ApplyAppearance(theAppearanceString)` (string form) — if that fails, fall back to the DLL
injecting `wo_set_app(npcTag, 'dog_05')` (name-binder path). Either way the marionette gets the
exact variant instead of the template default. Fixes "all guards look the same / wrong outfit".

**Effort:** small if `ApplyAppearance(string)` works (pure WS, one call in WO_CreateRemoteMarionette).
Medium if we need the binder path (DLL must tag each marionette and inject per-NPC — more plumbing).

---

## 2. Monster attacks the guest — "combat Step 2" (HIGH value, HIGH effort)

The long-standing frontier. Prior dead-end: making the marionette hostile to get real combat AI
→ drowners vanish. The viable design avoids AI entirely and **scripts** the attack + syncs the hit.

**Damage to the player (guest side):**
- `thePlayer.GainStat(BCS_Vitality, -dmg)` — direct HP subtraction (cleanest).
- or `thePlayer.SetHealth(GetHealth() - dmg)`; `GetStat(BCS_Vitality)`.
- `SetCanPlayHitAnim(true)` then a `W3DamageAction` through `theGame.damageMgr.ProcessAction()`
  to get the real hit reaction + screen FX, OR just play a hit anim + GainStat for a lighter touch.

**Scripted attack (host side, on the real NPC — for the attack animation):**
- `W3Action_Attack.Init(attacker, victim, cause, weaponId, attackName, src, EHRT_*, canParry,
  canDodge, skillName, swingType, swingDir, isMelee, isRanged, isSign, isEnv, …)`
- `action.AddDamage(theGame.params.DAMAGE_NAME_BLUDGEONING, dmgVal)`
- `theGame.damageMgr.ProcessAction(action); delete action;`
- Pattern reference: `btTaskDealDamage.ws` `DealDamage()`. Hit reaction types `EHRT_Light/Heavy/...`.

**End-to-end flow (no marionette hostility):**
1. Host's REAL NPC fights the guest's ghost (the ghost is already on the host; it just needs to be
   a valid target — `SetGameplayVisibility(true)`, kept `AIM_Invulnerable` so it can't actually die).
   `WO_MakeGhostsAttackable()` already does most of this. The host NPC plays its real attack anim.
2. When the host NPC's attack connects on the ghost (anim event / OnTakeDamage on the ghost), host
   reads the damage and **RPCs it to the guest** via the exec relay: `wo_take_damage(<amount>)`.
3. Guest `exec function wo_take_damage(amt : float)` → `thePlayer.GainStat(BCS_Vitality, -amt)` +
   `SetCanPlayHitAnim(true)` + a local hit reaction/FX. Guest now actually takes damage.
- The marionette on the guest stays a friendly puppet — its attack **animation** can be shown by
  having the host also send "this NPC is attacking now" so the guest plays a slot attack anim on the
  marionette (`PlaySlotAnimationAsync`/`RaiseEvent`) purely for visuals, synced to the damage tick.

**Immortality channels** (types.ws): `AIM_None/Immortal/Invulnerable/Unconscious`; channels
`AIC_Default/Combat/Scene/SyncedAnim/IsAttackableByPlayer(128)…`. `AIC_IsAttackableByPlayer`
is interesting for making the ghost attackable on one channel while invulnerable on another.

**Effort:** high — needs the ghost-as-target wiring to reliably trigger host NPC attacks, a damage
RPC (trivial via the existing exec relay), and guest-side feedback. But every piece is now known.

---

## 3. Animation / action control (enables both #2 visuals and workspot actions)

- `CEntity.RaiseEvent(name)` / `RaiseForceEvent(name)` — fire a named anim event (e.g. 'DrawWeapon').
- `GetRootAnimatedComponent() : CAnimatedComponent`, then
  `PlaySlotAnimationAsync(anim : name, slot : name, settings)` — play an explicit animation in a slot
  (this is exactly how the base mod animates player-ghost emotes in 'NPC_ANIM_SLOT').
- `SetBehaviorVariable(name, float)` — drive behavior-graph state (attack type, etc.).
- Latent: `ActionPlaySlotAnimation`, `ActionMatchTo`, `ActionSlideToWithHeading` — for scripted
  sequences (use non-latent in our per-frame render path).
- Equipment visuals: `inv.MountItem(id, toHand, force)` / `UnmountItem(id)` (we use MountItem for
  weapons); `DrawWeaponAndAttackLatent(itemId)`.

---

## 4. Workspot / action animations + world-state sync

### 4a. Workspot / action animations (sawing, sitting, praying) — ⭐ most-wanted, HARD
- NPC contextual actions = **job trees** at **action points** (AP). `EJobTreeType` includes
  `EJTT_Praying, EJTT_Sitting, EJT_PlayingMusic, EJTT_CatOnLap, EJTT_InfantInHand, …`
- APIs (jobTree.ws / actionPointManager.ws): `CActionPointManager.GetJobTree(apID) : CJobTree`,
  `GetGoToPosition(apID, out pos, out rot)`, `GetActionExecutionPosition(...)`, `GetFriendlyAPName(apID)`.
- **THE GAP:** these are all **read-only**. There is **no exported `SetJobTree()` / `PlayWorkspot()`**
  to *command* an NPC into a named action from script — it's C++-side only. So we cannot directly
  tell the guest's marionette "sit at this AP".
- **Workarounds (in order of practicality):**
  1. **Animation replay** (recommended, ties into §3): the host detects the NPC's current job-tree
     *type* (we may be able to infer it) and sends a token; the guest plays a matching looping
     `PlaySlotAnimationAsync('<sit/saw/pray anim>', 'NPC_ANIM_SLOT')` on the marionette. Not the real
     workspot, but visually "this NPC is sitting/sawing". Needs a small token→anim table (find anim
     names per action in the animations/ data). This is the same technique the base mod uses for
     player-ghost emotes — proven.
  2. **Spawn the marionette directly onto a local AP** and let ITS OWN community pick a workspot —
     loses host fidelity (random action), low control.
  3. Patch a custom native setter — out of scope.
- **Verdict:** HARD for *faithful* sync, but **MEDIUM for "good enough"** via anim replay (#1).
  This is the path to finally showing sawing/sitting/kneeling on the guest.

### 4b. Time of day & weather — EASY, high immersion ✅
- `GetGameTime() : GameTime`, `SetGameTime(time, callEvents)`, `GameTimeCreate(d,h,m,s)`,
  `GameTimeHours/Days`. `RequestWeatherChangeTo(weatherName : name, blendTime : float, questPause : bool)`,
  `GetWeatherConditionName() : name`, `GetRainStrength/GetSnowStrength/IsSkyClear`.
- **Design:** host broadcasts time + weather-name (via the exec relay or an NPC-style field) every
  game-minute / on change; guest calls `SetGameTime(...)` + `RequestWeatherChangeTo(name, ~5, false)`.
  Weather name is a `name` → use the exec-binder relay (`wo_set_weather('WT_Rain', 5)`).
- **Verdict:** EASY, cheap, makes the shared world feel genuinely shared (same sky/rain). Good early win.

### 4c. Doors & containers — MEDIUM, world consistency
- `W3Door.Open()/Close()/Toggle(force)/IsOpened()/CanBeOpened()`; door state is a `saved var isOpened`.
- `W3Container.TakeAllItems()/HasQuestItem()`, events `OnItemTaken/OnItemGiven`, `inv` autobind.
- **Design:** sync door open/close by id (host opens → guest calls Open() on the matching door).
  Containers are trickier (item flow / who-loots-what) — pairs with the existing loot system.
- **Verdict:** MEDIUM. Doors are the easy half; container item-sync needs care.

### 4d. Sign / spell FX replication — EASY, visual ✅
- `PlayEffect(effectName : name, optional target)`, `PlayEffectOnBone(fx, bone, target)`,
  `StopEffect`, `IsEffectActive`. Signs = `W3SignEntity` (ESignType Igni/Aard/Quen/Yrden).
- **Design:** when a player casts a sign, broadcast `{signType, position}`; each peer spawns the
  visual via `PlayEffect()` at that spot. Pure cosmetic — no projectile/damage logic needed.
- **Verdict:** EASY. Lets you SEE your partner cast Igni/Aard. Nice co-op flavor.

### 4e. Spawn / community + monster data
- Community spawns NPCs via `CCommunitySystem` / spawn trees; we already suppress the guest's own
  NPCs and replicate the host's via `CreateEntity()` — this confirms the model is sound. Verdict: MEDIUM (current approach is the right one).
- `theGame.GetMonsterParamsForActor(actor, out mc, ...)` gives `EMonsterCategory` + blood type at
  runtime — a cleaner type signal than appearance for grouping/FX. Verdict: EASY (complements the mon_* fingerprint).

---

## 5. Quick API reference (by subsystem)

| Need | API | File |
|---|---|---|
| Set exact appearance | `SetAppearance(name)` / `ApplyAppearance(string)` | actor.ws / appearanceComponent.ws |
| Damage the player | `GainStat(BCS_Vitality, -dmg)` / `SetHealth` | actor.ws |
| Apply a full attack | `W3Action_Attack.Init(...)` + `damageMgr.ProcessAction` | attackAction.ws / damageManager.ws |
| Hit reaction | `SetCanPlayHitAnim(true)`, `EHRT_*` | actor.ws / types.ws |
| Play an animation | `GetRootAnimatedComponent().PlaySlotAnimationAsync` / `RaiseEvent` | components.ws / entity.ws |
| Behavior var | `SetBehaviorVariable(name, float)` | components.ws |
| Move/rotate | `GetMovementAdjustor().SlideTo/RotateTo/AdjustmentDuration` | movementAdjustor.ws |
| Locomotion anim | `SetGameplayMoveDirection`, `SetGameplayRelativeMoveSpeed`, `SetMoveType` | movingAgentComponent.ws |
| Equipment | `MountItem/UnmountItem` | inventoryComponent.ws |
| Classify | `IsHuman/IsAnimal/IsMonster/GetMonsterCategory`, `IsInCombat` | actor.ws |
| Type fingerprint | `GetCharacterStats().GetAbilities(out)` → `mon_*` | characterStats.ws |
| Attitude (AVOID hostile on marionettes) | `SetAttitude`, `SetTemporaryAttitudeGroup` | actor.ws |
| Immortality | `SetImmortalityMode(AIM_*, AIC_*)` | actor.ws / types.ws |
| Time of day | `GetGameTime`, `SetGameTime(t, callEvents)`, `GameTimeCreate` | gameTime.ws |
| Weather | `RequestWeatherChangeTo(name, blend, questPause)`, `GetWeatherConditionName` | environment.ws |
| Sign/spell FX | `PlayEffect(name, target)`, `PlayEffectOnBone`, `StopEffect` | entity.ws / signEntity.ws |
| Doors | `W3Door.Open/Close/Toggle/IsOpened` | door.ws |
| Containers | `W3Container.TakeAllItems/HasQuestItem`, `OnItemTaken` | container.ws |
| Workspot (READ-ONLY — no setter) | `CActionPointManager.GetJobTree/GetGoToPosition` | jobTree.ws / actionPointManager.ws |
| Monster params | `theGame.GetMonsterParamsForActor(a, out mc, ...)` → EMonsterCategory | npc.ws |

---

## 6. Recommended roadmap (by value / effort)

**Quick wins (EASY, do first — cheap, high immersion):**
1. **Exact loot by type** — we already have the `mon_*` fingerprint + loot tables; trivial upgrade of
   `WO_GrantLootForAppearance` → by-type (also fixes wild_dog getting no loot). Pure WS.
2. **Time + weather sync** (§4b) — `SetGameTime` + `RequestWeatherChangeTo` via the exec relay.
   Same sky/rain on both = the world finally feels shared. Small.
3. **Sign FX replication** (§4d) — see your partner cast Igni/Aard via `PlayEffect`. Small, fun.
4. **Appearance variants** (§1) — test `ApplyAppearance(string)` first; if it works it's the biggest
   visual fidelity win for the least effort (exact outfits/variants instead of template defaults).

**Medium:**
5. **Workspot action sync via anim replay** (§4a #1) — finally show sawing/sitting/kneeling on the
   guest. Needs an action→anim-name table; no faithful workspot API exists, so it's a visual approximation.
6. **Doors** (§4c) — sync open/close state. Container item-sync later.

**Headline (HARD, the real co-op depth):**
7. **Monster attacks the guest** (§2) — host scripts the attack + RPCs damage; guest does
   `GainStat(BCS_Vitality, -dmg)` + hit anim. All APIs now known; significant plumbing, but this is
   the feature that turns "shared world" into "shared combat".

**Guiding principle confirmed by the research:** keep marionettes friendly puppets; never rely on
their AI. Drive everything explicitly (position, anim, damage) over the wire — the engine exposes
enough setters (movement, PlaySlotAnimation, GainStat, PlayEffect, SetGameTime, SetAppearance) to
script a convincing shared world; the only true gap is direct workspot commanding (work around with anim replay).
