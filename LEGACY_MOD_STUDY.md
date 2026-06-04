# Legacy "Witcher Online" Mod — Deep Study (2026-06-01 night)

How the base mod's multiplayer sync actually works, so we can REUSE its proven infrastructure
for our NPC co-op (equipment, animations, combat) instead of reinventing it. Source files:
`...\local\client.ws` (175KB, host-side state collection) and `...\local\remotePlayer.ws`
(237KB, the `r_RemotePlayer` ghost that applies synced state).

---

## 1. Wire protocol (from the protocol agent)

**Split-packet architecture.** Host WS getters `wo_get`/`wo_get2`/`wo_get3` `Log()` the player
state; the DLL splits on a `half` marker into UPDATE1A/1B (+2A/2B), UDP→server→broadcast 20Hz;
the receiving DLL reassembles all four chunks and calls `wo_update()` once. Multi-word values
(item names, chat) are wrapped in `_s ... _e` block markers so spaces survive tokenization.

**update1A (≈50 fields, every cycle, latency-critical)** — pos XYZW, heading, speed, area,
inGame, **heldItem ("steel"/"silver"/"none")**, **offhandItem ("torch"/"none")**, inCombat,
isSwimming, curState, jump/climb/dive/fall, lastLight/Heavy/Dodge/Roll times, isGuarded,
lastHit/Parry/Finisher, signType+lastSign, isSailing/isMounted/horseSpeed, aimingCrossbow,
isLadder, currentState, bombSelected, isAlive, emote+time, chat+time, chillOutAnim, yaw,
stamina, swirling, rend, channeling, menuName, lastAction+time.

**update1B (≈23 fields)** — the FULL equipment by item-NAME: **steel, silver, armor, gloves,
pants, boots, head, hair, steelScab, silverScab, crossbow, mask** + riding/trade/horse/morph.

**update2A/2B (every 30 cycles)** — CPC (custom-player-character) appearance templates.

**Transient channels (one-shot, not stored):** `UPDATE_HIT` (our combat hits), `UPDATE_EXEC`
(our item/time/weather relay — self-echo filtered, guard `code.startsWith("wo_")`). Stored:
`UPDATE_NPC` (our NPC sync, one payload field).

**KEY INSIGHT for equipment:** the mod ALREADY tracks, per player: a coarse held state
(heldItem/offhandItem: which sword is drawn, torch in offhand) AND the full equipment item
names. The exact same fields/patterns are what an NPC needs. We don't need to invent the data
model — copy it.

**Safest way to extend the wire (agent's recommendation):** add a NEW opcode (e.g.
`UPDATE_NPC_EXT`) rather than appending to UPDATE1A/1B (which would change field counts and can
crash old `wo_update()` parsing). New opcode = isolated failure domain, backward compatible.
Mirror the existing UPDATE_NPC plumbing (WS getter `wo_get_npc_ext` → DLL `pushPayload` →
server `updateNpcExtFields` broadcast → WS `wo_npc_ext_update`). **BUT** — for per-NPC held
items we can likely just append tokens to our OWN NPC chunk (we own that format), no new opcode
needed; the new-opcode advice matters only if touching the base mod's UPDATE1A/1B.

---

## 2. Equipment & appearance sync (from the equipment agent) — THE FIX FOR OUR WEAPON PROBLEM

**How the mod sidesteps string→name = the SAME exec-binder we use.** The equipment item NAMES
travel as string tokens inside the `wo_update(id, ...)` exec call the DLL injects; `wo_update`'s
parameters are declared `: name`, so the engine binds string→name at the call (identical to our
`wo_give_item`). Then everything is `name`-typed and `AddAnItem(name)` just works. So: to give a
marionette real equipment, the names must arrive via an **exec call with `name` params**, NOT as
part of a plain string payload (our `wo_npc_update` payload is a string blob → can't convert).

**HOST reads equipment (client.ws ~4192):** per slot,
`inv.GetItemEquippedOnSlot(EES_SteelSword/EES_SilverSword/EES_Armor/EES_Gloves/EES_Pants/EES_Boots/
EES_Quickslot2(mask)/EES_RangedWeapon, out id)` → `inv.GetItemName(id) : name`. Head via
`CHeadManagerComponent.GetCurHeadName()`. Hair/scabbards via `inv.GetItemsByCategory('hair' /
'steel_scabbards' / 'silver_scabbards')` then pick the one that `IsItemHeld||IsItemEquipped||
IsItemMounted`. **Drawn-weapon state:** `inv.GetItemEquippedOnSlot(EES_SilverSword,out s)&&
inv.IsItemHeld(s)` → "silver"; steel → "steel"; else "none". Torch offhand similarly.

**GUEST applies (remotePlayer.ws `EquipNewItem` @1894 — the key helper):**
```
EquipNewItem(inv, out lastItem : name, newItem : name, optional mount : bool, optional hide : bool):
  if lastItem != '' && lastItem != newItem:   // remove old
     ids = inv.GetItemsByName(lastItem); if ids: (mount? inv.UnmountItem(ids[0],true) : owner.UnequipItem(ids[0])); inv.RemoveItemByName(lastItem,1)
  ids = inv.GetItemsByName(newItem)
  if ids empty:
     ids = inv.AddAnItem(newItem, 1)          // name -> real item (the whole trick)
     mount ? inv.MountItem(ids[0]) : ((CActor)inv.GetOwner()).EquipItem(ids[0])
  ent = inv.GetItemEntityUnsafe(ids[0]); if ent: ent.SetHideInGame(hide)
  lastItem = newItem
```
`updateEquippedItems` calls it per slot every frame (cheap: no-op when lastItem==newItem). hair
uses mount=true; armor/gloves/pants/boots/head/mask use equip (mount=false).

**DRAWN vs SHEATHED (this is likely why OUR sword was invisible):**
- `inv.MountItem(id, true)` = **weapon DRAWN / in hand (visible)**  ← we used `MountItem(id,false)` = holstered.
- `((CActor)owner).EquipItem(id)` = **sheathed/stored**.
**Torch:** `ids = inv.GetItemsByName('Torch_work'); if empty inv.AddAnItem('Torch_work',1);
inv.MountItem(ids[0], true)` to hold it; to drop: `EquipItem` + `UnmountItem(id,true)`.

**CPC appearance overlays (non-equipment look):** `updateTemplate(path:string, prev)` →
`(CAppearanceComponent)ghost.GetComponentByClassName('CAppearanceComponent')` →
`ExcludeAppearanceTemplate(prev)` + `LoadResourceAsync(path,true)` + `IncludeAppearanceTemplate(t)`.
(We already use ApplyAppearance for the base variant — this is the layered-template alternative.)

### DELIVERABLE — proper NPC equipment sync (the real fix)
1. **HOST**, per broadcast NPC, read its equipped weapon/armor names (GetItemEquippedOnSlot/
   GetItemName) + drawn state. For monsters there's usually nothing (their weapon is in-model).
2. **Transmit names via the exec binder, NOT the string payload.** Add `exec function
   wo_npc_equip(key : name, item : name, mount : int)` and have the host enqueue
   `WO_EnqueueExec("wo_npc_equip('host:5','No Mans Land sword 2', 1)")` per NPC item (names bind
   via the engine — same as wo_give_item). Guest `wo_npc_equip` finds the marionette by key and
   runs the EquipNewItem logic on it.  *(Alternative: a new UPDATE_NPC_EXT opcode per the protocol
   doc — heavier. The relay path reuses what we have.)*
3. **GUEST** applies with `EquipNewItem`; use `MountItem(id,true)` for drawn weapons / torch,
   `EquipItem(id)` for sheathed/armor.

### IMMEDIATE small win for the current "guard has no sword" bug
Our V60-62 added `'No Mans Land sword 2'` then `MountItem(id, false)` (holstered) — the mod shows a
held weapon with `MountItem(id, TRUE)`. Switching our added-sword mount to `true` (drawn) is the
most likely one-line fix to make it visible. (Confirm the item name via the HUD `arm[add=N]` diag
first — if add=0 the name's still wrong; the mod proves `AddAnItem(name)` works for valid names.)

## 3. Animation, combat & signs sync (from the animation agent)

**The universal anim primitive** (reusable for ANY actor incl. our marionettes):
```
actor.GetRootAnimatedComponent().PlaySlotAnimationAsync(
    animName : name, 'NPC_ANIM_SLOT', SAnimatedComponentSlotAnimationSettings(fadeIn, fadeOut));
```
The ghost runs a **queue** (`r_AnimRequest`: anim/duration/fadeIn/fadeOut/overrideNow/type/loop)
via queueAnim → playAnimNow. `type` classifies (locomotion/attack/hit/sign/emote/chillout) so
protected actions (attack/dodge/roll/parry/finisher/sign/jump) aren't interrupted by locomotion.
For a LOOP: re-queue with fadeIn/Out=0 when `currentAnimEndTime` passes.

**Locomotion = synced `speed` → anim** (NOT direction; direction comes from position/moveEntity):
speed 0=idle, ≤0.4 `sword_movement_slow_walk`, ≤0.7 `_walk`, ≤1.0 `_run`, >1.0 `_sprint` (loop).
This is exactly what our `WO_MoveMarionette` approximates via SetGameplayRelativeMoveSpeed.

**Combat replay** — host sends timestamps (lastLight/HeavyTime, lastDodge/Roll/Parry/Finisher,
lastHit, lastSign); ghost detects a CHANGE → queues a random anim of that family, `overrideNow`:
- Light sword: `man_geralt_sword_attack_fast_<1-9>_lp/rp_40ms` (1.6s)
- Heavy sword: `man_geralt_sword_attack_strong_<1-10>_lp/rp_70ms` (2.0s)
- Fist: `man_fistfight_attack_fast_*` / `_heavy_*`
- Hit reaction: `man_geralt_sword_hit_front_*` (1.5s), fist `man_fistfight_hit_*`
- Dodge: `man_geralt_sword_dodge_<dir>_350m`; Roll: `man_geralt_sword_dodge_roll_rp_f/b_01`
- Parry: `man_geralt_sword_parry_f_*_lp`; Finisher: `mp_man_finisher_0<1-8>_lp/rp`, monster `man_ger_crawl_finish`
- Rend: `man_geralt_sword_attack_heavy_special_rp_start/end`

**Signs** — by `signType` + `lastSign` change → cast anim. Combat: `man_ger_sword_<igni/aard/axii/
quen/yrden>_front_lp` (~1.7s); fist variants `man_fistfight_<sign>_front`; channel loops exist.
**IMPORTANT: the mod plays only the ANIMATION — it does NOT spawn sign FX/particles.** For our
"see partner cast Igni" feature we'd add `PlayEffect(...)` ourselves (REDkit research §4d).

**Emotes/chillout** — 24 emotes (meditation_idle01, vanilla_sitting_on_ground_loop, dance, cheer,
beg, cry, greeting…), looped via re-queue. This is the template for **action-anim sync** (sawing/
sitting/kneeling): host sends an action token, guest loops the matching slot anim.

**Damage model — the ghost is deliberately INVULNERABLE and never shows being hit**
(`SetCanPlayHitAnim(false)` + `AIM_Invulnerable` at spawn). Hit anims only play when the synced
`lastHit` *timestamp* changes (the remote player got hit in THEIR world), not from local damage.
So "monster hits guest" damage/feedback is entirely NEW work (no reusable damage path) — see §4.

**RECIPE — make a marionette play a specific action/attack anim:** spawn → `SetCanPlayHitAnim(false)`
+ collisions off + `AIM_Invulnerable` → `GetRootAnimatedComponent().PlaySlotAnimationAsync(anim,
'NPC_ANIM_SLOT', settings)`; loop by re-queue. For monster attack swings, reuse humanoid attack
anims on humanoid monsters, or find monster-specific attack anim names in the animations data.

## 4. Monster-attacks-guest (engine + our exec relay) — the headline feature

The agent's plan maps cleanly onto OUR exec relay (host → guest typed call). No new RPC system
needed — we already have `wo_*` exec injection.

**MVP design (fully scripted, recommended — avoids the hostile-marionette vanish bug entirely):**

1. **HOST detects an attack opportunity.** A host monster is near the guest's ghost (we already
   collect NPCs near each `MPEntity` ghost in `wo_get_npcs`). Per monster, if within ~2.5m of a
   ghost and an attack cooldown elapsed → it's an attack tick. (Optionally also play the monster's
   real attack anim on the host so the HOST sees the swing.)
2. **HOST sends the hit to the guest via the exec relay:** `WO_EnqueueExec("wo_take_damage(" +
   dmg + ", " + reactType + ")")`. (reactType: 0=light,1=heavy.) This is identical plumbing to
   `wo_give_item` — proven to work cross-device.
3. **GUEST applies it** — `exec function wo_take_damage(amt : float, react : int)`:
   - `GetWitcherPlayer().GetAbilityManager().GainStat(BCS_Vitality, -amt)` — real HP loss.
   - hit feedback: a hit-react anim + hit FX + controller rumble (`theInput.SetVibration(0.6,0.2)`
     — VERIFY signature) so it feels like a hit, not a silent number.
   - **CLAMP — never die in co-op:** if resulting Vitality ≤ 0, GainStat back up to 1 (or a
     "downed" state). Avoids the single-player death/game-over.
4. **Show the monster's swing on the guest's marionette** (visual polish): the host also sends
   "this NPC is attacking" (a token in the NPC chunk or via the relay) → guest plays a monster
   attack slot-anim on the marionette (`PlaySlotAnimationAsync(monsterAttackAnim,'NPC_ANIM_SLOT')`).
   Need monster attack anim names (find in animations data; humanoid attacks reuse the §3 list).

**Damage API (alternative to GainStat):** a full `W3DamageAction` with victim=guest player +
`theGame.damageMgr.ProcessAction()` gives engine-driven hit reaction/FX/death — but it's heavier
and risks the death state. For co-op, **direct `GainStat(BCS_Vitality, -amt)` + manual feedback +
HP clamp is simpler and safer.** (`W3DamageAction.Initialize(att, vict, cause, src, EHRT_*,
CPS_*, isMelee, isRanged, isSign, isEnv, ...)` is the signature if we ever want the full path.)

**Why NOT make the ghost AI-targetable (Option A):** it needs the ghost gameplay-visible +
hostile + colliders, re-introduces the exact conditions that make things unstable, and couples us
to real combat AI timing. The scripted MVP keeps marionettes friendly and drives everything over
the wire — consistent with our confirmed guiding principle.

**Caveats / verify before coding:** `theInput.SetVibration`, `GetEffectManager().PlayEffect`,
the exact `GainStat`/`GetAbilityManager` accessor on the player, and player hit-react anim names
were given by the agent but should be grepped/confirmed (agent included some pseudocode). The
core loop (host proximity → `wo_take_damage` relay → guest GainStat+clamp) is solid and reuses
proven infra.

**Effort:** the damage loop is SMALL (relay + one exec fn + clamp). The polish (host swing detect,
guest marionette attack anim, FX/rumble) is the bulk. A first playable "monsters chip your HP when
they're on you" MVP is achievable quickly.

---

## Reusable infrastructure summary
- The **exec relay** (UPDATE_EXEC) we built is the right channel for ALL typed cross-player actions
  (items ✓, time/weather ✓, and future: `wo_npc_equip(key,item,mount)`, `wo_take_damage(amt,react)`).
  The mod itself rides the engine exec-binder for `name` params — we independently rebuilt the same.
- The mod's **equipment-by-name** (`EquipNewItem` + AddAnItem(name) + MountItem(true)/EquipItem) is
  directly reusable for NPC gear, weapons (drawn/sheathed), and torches.
- The mod's **anim queue** (`PlaySlotAnimationAsync('NPC_ANIM_SLOT')`) is the template for NPC action
  anims (sawing/sitting) and monster attack swings; anim NAME lists are in §3.
- **monster-attacks-guest** needs no new transport — host proximity → `wo_take_damage` relay → guest
  GainStat + clamp. All APIs known.

## Prioritized next actions (morning)
1. **One-line weapon fix:** in WO_MountWeapons, change the added-sword mount to `MountItem(id, TRUE)`
   (drawn) instead of `false` (holstered) — per the mod, `true` = visible in hand. (First confirm the
   HUD `arm[add=N]` shows add>=1; if add=0 the item name is still wrong.)
2. **Time/weather:** finish debugging via the V63 HUD `WO host/recv` lines (already deployed).
3. **Sign FX** (easy, fun): detect guest sign cast (signType is already in the player wire) on the
   host side / or guest broadcasts it, and `PlayEffect` at the position. Pure visual.
4. **Full NPC equipment** (medium): `wo_npc_equip` relay (host reads NPC gear → per-NPC relay exec →
   guest EquipNewItem). Fixes weapons/torches/armor properly, not just a generic sword.
5. **Monster-attacks-guest** (headline): the `wo_take_damage` MVP loop, then polish.
