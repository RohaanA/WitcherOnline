// Spike: AI suppression + NPC sync
//      test harness.
//
// -:     , hook   
//   5    .     ,
//    WO_SPIKE_AUTO_ENABLED.
//
//  (   ):
//   wo_spike_spawn                   5     
//   wo_spike_marionettize_near      NPC ()     
//   wo_spike_move_rel x y z            
//   wo_spike_aggro                   hostile
//   wo_spike_destroy                  spike'
//
// :    WS   Pause/BlockAllActions.  
//     (immortal + no collision + friendly + speed=0).

//   false  -   .
function WO_SPIKE_AUTO_ENABLED() : bool { return true; }

// ROLE: PC = host (false), Deck = guest (true).
// Change to true before deploying to Deck.
function WO_IS_GUEST() : bool { return false; }

// True when the game isn't in normal gameplay (paused, menu, cutscene, loading).
// Used to skip co-op logic so we don't process damage / spawn / move while frozen.
function WO_GameBusy() : bool
{
    return theGame.IsPaused()
        || !theGame.IsActive()
        || theGame.IsCurrentlyPlayingNonGameplayScene()
        || theGame.IsDialogOrCutscenePlaying();
}

// Force a "do nothing" AI so the NPC stops wandering / idle behaviors and becomes a
// pure puppet. The locomotion graph still responds to SetGameplayRelativeMoveSpeed +
// SlideTo, so walk/idle animations play correctly under our control.
function WO_StopAI(actor : CActor)
{
    var doNothing : CAIDoNothingAction;
    if (!actor) return;
    doNothing = new CAIDoNothingAction in actor;
    doNothing.OnCreated();
    actor.ForceAIBehavior( doNothing, BTAP_AboveEmergency2 );
}

// Map a monster appearance to its REDkit template path, or "" if it's NOT a monster
// (human/animal). Single source of truth for "is this a monster" + "which template".
// Paths verified present in REDkit r4data\characters\npc_entities\monsters\.
// Order: longer/more-specific prefixes before shorter ones they'd shadow.
function WO_MonsterTemplate(app : string) : string
{
    if (WO_StartsWith(app, "drowned_dead")) return "characters\npc_entities\monsters\drowner_lvl1.w2ent";
    if (WO_StartsWith(app, "drowner"))      return "characters\npc_entities\monsters\drowner_lvl1.w2ent";
    if (WO_StartsWith(app, "rotfiend"))     return "characters\npc_entities\monsters\rotfiend_lvl1.w2ent";
    if (WO_StartsWith(app, "alghoul"))      return "characters\npc_entities\monsters\alghoul_lvl1.w2ent";
    if (WO_StartsWith(app, "ghoul"))        return "characters\npc_entities\monsters\ghoul_lvl1.w2ent";
    if (WO_StartsWith(app, "nekker"))       return "characters\npc_entities\monsters\nekker_lvl1.w2ent";
    if (WO_StartsWith(app, "wild_dog"))     return "characters\npc_entities\monsters\wild_dog_lvl1.w2ent";
    if (WO_StartsWith(app, "werewolf"))     return "characters\npc_entities\monsters\werewolf_lvl1.w2ent";
    if (WO_StartsWith(app, "warg"))         return "characters\npc_entities\monsters\wolf_lvl1.w2ent";
    if (WO_StartsWith(app, "wolf"))         return "characters\npc_entities\monsters\wolf_lvl1.w2ent";
    if (WO_StartsWith(app, "bear"))         return "characters\npc_entities\monsters\bear_berserker_lvl1.w2ent";
    if (WO_StartsWith(app, "harpy"))        return "characters\npc_entities\monsters\harpy_lvl1.w2ent";
    if (WO_StartsWith(app, "siren"))        return "characters\npc_entities\monsters\siren_lvl1.w2ent";
    if (WO_StartsWith(app, "fogling"))      return "characters\npc_entities\monsters\fogling_lvl1.w2ent";
    if (WO_StartsWith(app, "foglet"))       return "characters\npc_entities\monsters\fogling_lvl1.w2ent";
    if (WO_StartsWith(app, "arachas"))      return "characters\npc_entities\monsters\arachas_lvl1.w2ent";
    if (WO_StartsWith(app, "nightwraith"))  return "characters\npc_entities\monsters\nightwraith_lvl1.w2ent";
    if (WO_StartsWith(app, "noonwraith"))   return "characters\npc_entities\monsters\noonwraith_lvl1.w2ent";
    if (WO_StartsWith(app, "wraith"))       return "characters\npc_entities\monsters\wraith_lvl1.w2ent";
    if (WO_StartsWith(app, "grave_hag"))    return "characters\npc_entities\monsters\hag_grave_lvl1.w2ent";
    if (WO_StartsWith(app, "water_hag"))    return "characters\npc_entities\monsters\hag_water_lvl1.w2ent";
    if (WO_StartsWith(app, "hag"))          return "characters\npc_entities\monsters\hag_water_lvl1.w2ent";
    if (WO_StartsWith(app, "vampire_katakan")) return "characters\npc_entities\monsters\vampire_katakan_lvl1.w2ent";
    if (WO_StartsWith(app, "katakan"))      return "characters\npc_entities\monsters\vampire_katakan_lvl1.w2ent";
    if (WO_StartsWith(app, "vampire_ekima")) return "characters\npc_entities\monsters\vampire_ekima_lvl1.w2ent";
    if (WO_StartsWith(app, "ekimmara"))     return "characters\npc_entities\monsters\vampire_ekima_lvl1.w2ent";
    if (WO_StartsWith(app, "forktail"))     return "characters\npc_entities\monsters\forktail_lvl1.w2ent";
    if (WO_StartsWith(app, "wyvern"))       return "characters\npc_entities\monsters\wyvern_lvl1.w2ent";
    if (WO_StartsWith(app, "cockatrice"))   return "characters\npc_entities\monsters\cockatrice_lvl1.w2ent";
    if (WO_StartsWith(app, "gryphon"))      return "characters\npc_entities\monsters\gryphon_lvl1.w2ent";
    if (WO_StartsWith(app, "griffin"))      return "characters\npc_entities\monsters\gryphon_lvl1.w2ent";
    if (WO_StartsWith(app, "troll"))        return "characters\npc_entities\monsters\troll_cave_lvl1.w2ent";
    if (WO_StartsWith(app, "cyclop"))       return "characters\npc_entities\monsters\cyclop_lvl1.w2ent";
    if (WO_StartsWith(app, "golem"))        return "characters\npc_entities\monsters\golem_lvl1.w2ent";
    if (WO_StartsWith(app, "gargoyle"))     return "characters\npc_entities\monsters\gargoyle_lvl1.w2ent";
    if (WO_StartsWith(app, "basilisk"))     return "characters\npc_entities\monsters\basilisk_lvl1.w2ent";
    return "";
}

// Hostile monster (gets hostile attitude so its health bar shows) vs peaceful human/animal.
function WO_IsMonsterAppearance(app : string) : bool
{
    return WO_MonsterTemplate(app) != "";
}

// Grant one item to the local player's inventory (informs GUI -> shows "+N <item>").
function WO_GrantItem(itemName : name, qty : int)
{
    if (GetWitcherPlayer() && GetWitcherPlayer().inv)
        GetWitcherPlayer().inv.AddAnItem(itemName, qty);
}

// Instanced shared-kill loot: when a synced monster dies, grant the GUEST curated loot for
// that monster type. Item CNames are verified literals from the game's def_loot_monsters.xml
// (we can't convert wire strings -> name at runtime; literals sidestep that entirely).
function WO_GrantLootForAppearance(app : string)
{
    if (app == "") return;

    if (WO_StartsWith(app, "drowned_dead")) { WO_GrantItem('Drowner brain', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "drowner"))      { WO_GrantItem('Drowner brain', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "rotfiend"))     { WO_GrantItem('Rotfiend blood', 1); WO_GrantItem('Monstrous brain', 1); return; }
    if (WO_StartsWith(app, "alghoul"))      { WO_GrantItem('Alghoul bone marrow', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "ghoul"))        { WO_GrantItem('Ghoul blood', 1); WO_GrantItem('Monstrous brain', 1); return; }
    if (WO_StartsWith(app, "nekker"))       { WO_GrantItem('Nekker blood', 1); WO_GrantItem('Nekker claw', 1); return; }
    if (WO_StartsWith(app, "werewolf"))     { WO_GrantItem('Werewolf saliva', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "wolf"))         { WO_GrantItem('Wolf pelt', 1); WO_GrantItem('Raw meat', 1); return; }
    if (WO_StartsWith(app, "warg"))         { WO_GrantItem('Wolf pelt', 1); WO_GrantItem('Raw meat', 1); return; }
    if (WO_StartsWith(app, "bear"))         { WO_GrantItem('Raw meat', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "harpy"))        { WO_GrantItem('Harpy feathers', 1); WO_GrantItem('Harpy talon', 1); return; }
    if (WO_StartsWith(app, "nightwraith"))  { WO_GrantItem('Wraith essence', 1); WO_GrantItem('Specter dust', 1); return; }
    if (WO_StartsWith(app, "noonwraith"))   { WO_GrantItem('Wraith essence', 1); WO_GrantItem('Specter dust', 1); return; }
    if (WO_StartsWith(app, "wraith"))       { WO_GrantItem('Wraith essence', 1); WO_GrantItem('Specter dust', 1); return; }
    if (WO_StartsWith(app, "fogling"))      { WO_GrantItem('Fogling teeth', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "foglet"))       { WO_GrantItem('Fogling teeth', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "grave_hag"))    { WO_GrantItem('Hag teeth', 1); WO_GrantItem('Venom extract', 1); return; }
    if (WO_StartsWith(app, "water_hag"))    { WO_GrantItem('Water Hag teeth', 1); WO_GrantItem('Venom extract', 1); return; }
    if (WO_StartsWith(app, "hag"))          { WO_GrantItem('Water Hag teeth', 1); WO_GrantItem('Venom extract', 1); return; }
    if (WO_StartsWith(app, "forktail"))     { WO_GrantItem('Dragon scales', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "wyvern"))       { WO_GrantItem('Dragon scales', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(app, "cockatrice"))   { WO_GrantItem('Monstrous feather', 1); WO_GrantItem('Monstrous blood', 1); return; }

    // Any other monster type -> a generic monster ingredient so a shared kill still drops something.
    if (WO_IsMonsterAppearance(app)) { WO_GrantItem('Monstrous blood', 1); return; }
    // Humans / animals -> no loot.
}

// EXACT loot keyed off the monster's mon_* fingerprint (precise — also covers wild_dog, which
// shares the "dog" appearance and so got no appearance-based loot). Preferred over appearance.
function WO_GrantLootForType(t : string)
{
    if (t == "" || t == "-") return;
    if (WO_StartsWith(t, "mon_drowner"))    { WO_GrantItem('Drowner brain', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(t, "mon_evil_dog"))   { WO_GrantItem('Raw meat', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(t, "mon_werewolf"))   { WO_GrantItem('Werewolf saliva', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(t, "mon_wolf"))       { WO_GrantItem('Wolf pelt', 1); WO_GrantItem('Raw meat', 1); return; }
    if (WO_StartsWith(t, "mon_nekker"))     { WO_GrantItem('Nekker blood', 1); WO_GrantItem('Nekker claw', 1); return; }
    if (WO_StartsWith(t, "mon_alghoul"))    { WO_GrantItem('Alghoul bone marrow', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(t, "mon_ghoul"))      { WO_GrantItem('Ghoul blood', 1); WO_GrantItem('Monstrous brain', 1); return; }
    if (WO_StartsWith(t, "mon_rotfiend"))   { WO_GrantItem('Rotfiend blood', 1); WO_GrantItem('Monstrous brain', 1); return; }
    if (WO_StartsWith(t, "mon_bear"))       { WO_GrantItem('Raw meat', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(t, "mon_harpy"))      { WO_GrantItem('Harpy feathers', 1); WO_GrantItem('Harpy talon', 1); return; }
    if (WO_StartsWith(t, "mon_nightwraith")){ WO_GrantItem('Wraith essence', 1); WO_GrantItem('Specter dust', 1); return; }
    if (WO_StartsWith(t, "mon_noonwraith")) { WO_GrantItem('Wraith essence', 1); WO_GrantItem('Specter dust', 1); return; }
    if (WO_StartsWith(t, "mon_wraith"))     { WO_GrantItem('Wraith essence', 1); WO_GrantItem('Specter dust', 1); return; }
    if (WO_StartsWith(t, "mon_fogling"))    { WO_GrantItem('Fogling teeth', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(t, "mon_water_hag"))  { WO_GrantItem('Water Hag teeth', 1); WO_GrantItem('Venom extract', 1); return; }
    if (WO_StartsWith(t, "mon_hag"))        { WO_GrantItem('Water Hag teeth', 1); WO_GrantItem('Venom extract', 1); return; }
    if (WO_StartsWith(t, "mon_forktail"))   { WO_GrantItem('Dragon scales', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(t, "mon_wyvern"))     { WO_GrantItem('Dragon scales', 1); WO_GrantItem('Monstrous blood', 1); return; }
    if (WO_StartsWith(t, "mon_cockatrice")) { WO_GrantItem('Monstrous feather', 1); WO_GrantItem('Monstrous blood', 1); return; }
    WO_GrantItem('Monstrous blood', 1);
}

function WO_GetXpForType(t : string) : int
{
    if (t == "" || t == "-") return 0;
    if (WO_StartsWith(t, "mon_drowner"))    return 15;
    if (WO_StartsWith(t, "mon_evil_dog"))   return 10;
    if (WO_StartsWith(t, "mon_werewolf"))   return 50;
    if (WO_StartsWith(t, "mon_wolf"))       return 10;
    if (WO_StartsWith(t, "mon_nekker"))     return 15;
    if (WO_StartsWith(t, "mon_alghoul"))    return 30;
    if (WO_StartsWith(t, "mon_ghoul"))      return 20;
    if (WO_StartsWith(t, "mon_rotfiend"))   return 25;
    if (WO_StartsWith(t, "mon_bear"))       return 30;
    if (WO_StartsWith(t, "mon_harpy"))      return 20;
    if (WO_StartsWith(t, "mon_nightwraith"))return 40;
    if (WO_StartsWith(t, "mon_noonwraith")) return 40;
    if (WO_StartsWith(t, "mon_wraith"))     return 30;
    if (WO_StartsWith(t, "mon_fogling"))    return 35;
    if (WO_StartsWith(t, "mon_water_hag"))  return 35;
    if (WO_StartsWith(t, "mon_hag"))        return 30;
    if (WO_StartsWith(t, "mon_forktail"))   return 50;
    if (WO_StartsWith(t, "mon_wyvern"))     return 50;
    if (WO_StartsWith(t, "mon_cockatrice")) return 50;
    return 10;
}

// Apply the host NPC's EXACT appearance variant (e.g. dog_05, the precise guard outfit) to the
// spawned marionette. ApplyAppearance takes a STRING (no string->name wall) — REDkit finding.
// Behind a flag so it can be disabled instantly if a variant glitches a mesh.
function WO_APPLY_VARIANTS() : bool { return true; }

function WO_ApplyVariant(actor : CActor, appStr : string)
{
    var ac : CAppearanceComponent;
    if (!WO_APPLY_VARIANTS()) return;
    if (!actor || appStr == "" || appStr == "dead" || appStr == "-") return;
    ac = (CAppearanceComponent)actor.GetComponentByClassName('CAppearanceComponent');
    if (ac)
        ac.ApplyAppearance(appStr);
}

// Is this a human that should carry a weapon (guard/soldier/bandit/hunter...)? Their weapon
// is given by WORLD PLACEMENT (community/encounter), NOT the base template — so a bare-template
// marionette is unarmed and we must ADD one.
function WO_IsArmedHuman(app : string) : bool
{
    return WO_StrContains(app, "guard")     || WO_StrContains(app, "soldier")
        || WO_StrContains(app, "bandit")    || WO_StrContains(app, "deserter")
        || WO_StrContains(app, "mercenary") || WO_StrContains(app, "witch_hunter")
        || WO_StrContains(app, "nilfgaard") || WO_StrContains(app, "hunter")
        || WO_StrContains(app, "warrior")   || WO_StrContains(app, "pirate");
}

// Make the marionette visibly carry what the host NPC carries (held class from the wire):
// "s"=weapon, "t"=torch, "-"=nothing. Monsters carry their own weapon in the template -> mount it.
// Humans spawn bare (weapon is world-placed, not in template) -> add the matching literal item and
// put it IN HAND (MountItem toHand=true, the mod's visible-weapon flag; fists are skipped).
// Returns true when "settled"; false only if the add failed (inventory not ready) -> caller retries.
function WO_MountWeapons(actor : CActor, held : string) : bool
{
    var inv : CInventoryComponent;
    var items, ids : array<SItemUniqueId>;
    var i, n : int;
    var dm : CDefinitionsManagerAccessor;
    var ss : WO_SpikeState;
    var itnm : name;
    var settled : bool;

    inv = actor.GetInventory();
    if (!inv) return false;
    dm = theGame.GetDefinitionsManager();

    // Mount any real (non-fist) weapon already in the template (monsters carry theirs).
    inv.GetAllItems(items);
    n = 0;
    for (i = 0; i < items.Size(); i += 1)
    {
        itnm = inv.GetItemName(items[i]);
        if (dm.IsItemWeapon(itnm) && dm.GetItemCategory(itnm) != 'fist')
        {
            actor.EquipItem(items[i]);
            inv.MountItem(items[i], true, true);   // toHand=true -> DRAWN/in hand
            n += 1;
        }
    }
    if (n > 0)
        return true;

    // Host-provided held class -> add matching literal items and put them IN HAND. We do NOT try to
    // sheathe on the body: each NPC model places its scabbard differently (hip vs back) via its own
    // setup, which we can't replicate by adding items to a bare template -> a sheathed item just
    // floats at the default attach point. The hand bone IS consistent across humanoids, so in-hand
    // is the only reliable placement. (Real per-NPC on-body gear would need spawning the NPC's full
    // configured entity, not a bare template.)
    if (held == "-" || held == "")
        return true;

    settled = true;
    if (WO_StrContains(held, "t"))
    {
        ids = inv.AddAnItem('Torch_work', 1, true, true);
        if (ids.Size() > 0) { actor.EquipItem(ids[0]); inv.MountItem(ids[0], true, true); }
        else settled = false;
    }
    if (WO_StrContains(held, "s"))
    {
        // NPC sword: equip_slot 'l_hip_weapon_slot' -> EquipItem sheathes it on the HIP correctly
        // (scabbard visual baked into the item). Start SHEATHED (peaceful); WO_UpdateHeldPose draws
        // it to the hand (hold_slot 'r_weapon') when the NPC is in combat.
        ids = inv.AddAnItem('NPC No Mans Land sword 1', 1, true, true);
        if (ids.Size() > 0)
            actor.EquipItem(ids[0]);
        else settled = false;
    }

    ss = theGame.WO_GetSpikeState();
    ss.arm_dbg = "held=" + held;
    return settled;
}

// Switch a marionette between PEACEFUL (sword sheathed on hip, torch in hand) and COMBAT (sword
// drawn in hand, torch stowed), mirroring the host NPC's IsInCombat state. Called when e.inCombat
// changes. Items are found by name (added by WO_MountWeapons).
function WO_UpdateHeldPose(e : WO_RemoteNpcEntry)
{
    var inv : CInventoryComponent;
    var mac : CMovingAgentComponent;
    var sw, to : array<SItemUniqueId>;

    if (!e || !e.actor) return;
    if (!WO_StrContains(e.held, "s")) return;   // only NPCs with a sword change pose
    inv = e.actor.GetInventory();
    mac = e.actor.GetMovingAgentComponent();
    if (!inv) return;

    sw = inv.GetItemsByName('NPC No Mans Land sword 1');
    to = inv.GetItemsByName('Torch_work');

    if (e.inCombat)
    {
        // EnableCombatMode puts the locomotion/behavior graph into COMBAT mode (combat stance +
        // combat walk/run). 'SelectedWeapon'=1 then drives the draw animation. Both are engine
        // mechanisms (movingAgentComponent.EnableCombatMode + btTaskRequiredItems' var), not hacks.
        if (mac) mac.EnableCombatMode(true);
        e.actor.SetBehaviorVariable('SelectedWeapon', 1, true);
        if (to.Size() > 0) { inv.UnmountItem(to[0], true); e.actor.UnequipItem(to[0]); }   // stow torch
        if (sw.Size() > 0) inv.MountItem(sw[0], true, true);          // ensure sword visible in hand
    }
    else
    {
        if (mac) mac.EnableCombatMode(false);
        e.actor.SetBehaviorVariable('SelectedWeapon', 0, true);       // sheathe + leave combat stance
        if (sw.Size() > 0) e.actor.EquipItem(sw[0]);                  // sword back on hip
        if (to.Size() > 0) { e.actor.EquipItem(to[0]); inv.MountItem(to[0], true, true); }   // torch in hand
    }
}

// PHASE 1 of the animation mirror (the mod's approach): drive a COMBAT STANCE slot animation on the
// marionette. When the host NPC is in combat AND roughly stationary, play a looping sword-alert idle
// in 'NPC_ANIM_SLOT' (overrides the puppet's neutral pose with a combat stance). When moving or out
// of combat, clear the slot so native locomotion (walk/idle) plays. Host-authoritative: driven only
// by the synced inCombat state, no local AI. Called every render frame for sworded marionettes.
function WO_ANIM_SYNC_ENABLED() : bool { return true; }

// Rotate through confirmed fast-attack anims (client.ws lightAttackAnims) so repeated swings vary.
function WO_AttackAnimForIndex(idx : int) : name
{
    var m : int;
    m = idx % 4;
    if (m == 0) return 'man_geralt_sword_attack_fast_1_lp_40ms';
    if (m == 1) return 'man_geralt_sword_attack_fast_2_rp_40ms';
    if (m == 2) return 'man_geralt_sword_attack_fast_3_lp_40ms';
    return 'man_geralt_sword_attack_fast_1_rp_40ms';
}

function WO_DriveCombatAnim(e : WO_RemoteNpcEntry, now : float)
{
    var rac : CAnimatedComponent;
    var want, swing : name;

    if (!WO_ANIM_SYNC_ENABLED()) return;
    if (!e || !e.actor) return;
    if (!WO_StrContains(e.held, "s")) return;   // only NPCs that carry a sword

    rac = e.actor.GetRootAnimatedComponent();
    if (!rac) return;

    // (1) ATTACK SWING — one-shot on the RISING EDGE of the host's IsAttacking() flag. Takes
    // precedence over the stance idle for the swing's duration. This mirrors the host NPC's
    // actual swings (host-authoritative: the guest never decides to attack, only replays it).
    if (e.is_attacking && !e.was_attacking && e.inCombat)
    {
        e.was_attacking = true;
        swing = WO_AttackAnimForIndex(e.swing_idx);
        e.swing_idx += 1;
        rac.PlaySlotAnimationAsync(swing, 'NPC_ANIM_SLOT', SAnimatedComponentSlotAnimationSettings(0.15, 0.25));
        e.cur_anim = swing;
        e.swing_until = now + 0.9;   // hold the swing ~0.9s, then resume the stance
        return;
    }
    if (!e.is_attacking)
        e.was_attacking = false;

    if (now < e.swing_until)
        return;   // let the current swing play out before anything else

    // (2) STANCE idle while standing in combat; clear slot (native walk, sword stays in hand) when
    // moving or out of combat.
    if (e.inCombat && VecLength(e.velocity) < 0.6)
        want = 'man_geralt_sword_alert_idle_left';
    else
        want = '';

    if (want == e.cur_anim && now < e.anim_end)
        return;   // already playing; not yet time to re-queue the loop

    if (want == '')
    {
        if (e.cur_anim != '')
        {
            rac.PlaySlotAnimationAsync('', 'NPC_ANIM_SLOT', SAnimatedComponentSlotAnimationSettings(0.3, 0.3));
            e.cur_anim = '';
        }
        return;
    }

    rac.PlaySlotAnimationAsync(want, 'NPC_ANIM_SLOT', SAnimatedComponentSlotAnimationSettings(0.3, 0.0));
    e.cur_anim = want;
    e.anim_end = now + 1.4;   // sword-alert idle is ~1.5s; re-queue just before it ends to loop
}

function WO_ApplyMarionetteSuppression(actor : CActor, appearance : string)
{
    if (!actor)
        return;

    // Immortal: hits register (host applies the real damage) but it won't die locally.
    actor.SetImmortalityMode( AIM_Immortal, AIC_Default, true );
    actor.EnableCollisions( false );
    actor.EnableCharacterCollisions( true );   // melee can connect

    // STABLE MODEL: every marionette (monster OR human) is a DoNothing puppet driven by
    // position sync (SlideTo). Live combat AI on monsters (V38/V41) made them wander off /
    // burrow / vanish because collisions are off and the AI tree fights our control — reverted.
    // Guest combat still works: guest swing -> forward hit -> host damages real NPC -> aggro.
    if (actor.GetMovingAgentComponent())
        actor.GetMovingAgentComponent().SetGameplayRelativeMoveSpeed( 0 );
    WO_StopAI( actor );

    // ALL marionettes (monster + human) = FRIENDLY puppets. DO NOT set hostile attitude:
    // a hostile monster marionette VANISHES on the guest (drowner dive/burrow fires and with
    // collisions off it sinks out of view). Confirmed twice — V41 (hostile+live AI) and V47
    // (hostile+DoNothing for HP bars) both made drowners disappear. HP-bar-via-hostile-attitude
    // is RULED OUT; keep them friendly and visible.
    actor.SetTemporaryAttitudeGroup( 'friendly_to_player', AGP_Default );
    // Weapons are handled in WO_CreateRemoteMarionette + retried in the render loop (so we can
    // track completion and survive the appearance rebuild that can clear an early mount).
}

// State stored  singleton (     ).
class WO_SpikeState
{
    public var render_tick_count : int;
    public var cleanup_tick_count : int;
    public var cleanup_last_scanned : int;
    public var cleanup_total_hidden : int;
    public var last_seen_attack : float;   // last player attack timestamp we forwarded
    public var npc_update_events : int;    // running count of NPC chunk updates (for rate readout)
    public var npc_rate_last_events : int; // snapshot at last HUD tick
    public var npc_rate_last_time : float;  // engine time at last HUD tick
    public var npc_rate_hz : int;          // measured updates/sec (all NPCs), shown in HUD
    public var arm_dbg : string;           // last armed-human weapon-add result (HUD diagnostic)
    public var ghost_tkt_melee : int;      // ghost CCombatDataComponent melee-ticket override request id (-0 = none)
    public var ghost_tkt_charge : int;     // ghost charge-ticket override request id
    public var ghost_tkt_special : int;    // ghost special-ticket override request id
    public var ghost_tkt_approach : int;   // ghost approach-ticket override request id
    public var ghost_tkt_active : bool;    // an override is currently issued (clear before re-issue)
    public var ghost_dbg : string;         // HOST combat-target diagnostic (CD=Y/n vis=.. atk=..) for HUD
    public var party_size : int;           // server-broadcast party size for difficulty scaling
}

@addField(CR4Game) public var wo_spike_state : WO_SpikeState;

@addMethod(CR4Game)
public function WO_GetSpikeState() : WO_SpikeState
{
    if (!this.wo_spike_state)
    {
        this.wo_spike_state = new WO_SpikeState in this;
    }
    return this.wo_spike_state;
}

// =============================================================================
// Spike #4  Network NPC sync end-to-end
// =============================================================================
//
// Wire format (string    UPDATE_NPC ):
//   "<id> <x_cm> <y_cm> <z_cm> <alive>|<id> <x_cm> <y_cm> <z_cm> <alive>|..."
//    (int)    float  WS.
//
// :
//   HOST:  wo_get_npcs("<myname>")    NPC, Log("wo_npc <payload>")
//           debug-script TCP
//          C++ DLL ExecTagged "wo_npc"  BuildPacket("UPDATE_NPC", username, [payload])
//           UDP 40000
//          Java server PlayerSession.updateNpcFields = [payload]
//           broadcast UDP  
//   GUEST: C++ DLL HandleServerPacket  ExecNoWaitLatest("wo_npc_update", host, payload)
//           debug-script TCP
//          WS wo_npc_update(host, payload)    / remote marionettes

// ---- Host side: NPC registry   ID ----

class WO_HostNpcRegistry
{
    public var actors : array<CActor>;  // index  CActor; ID = index + 1
    public var killed : array<int>;     // npcIds killed this frame, to broadcast alive=0 once
    public var types : array<string>;   // cached monster type token (mon_*) per npc id, "" if none
    public var held : array<string>;    // cached held-item class per npc id: "t"=torch "s"=sword "-"=none
}

// Read what the REAL host NPC is carrying, as a coarse class the guest recreates with literals
// (flags, not names -> no string->name wall). Computed ONCE per NPC. Combined: "ts" torch+sword,
// "t" torch only, "s" weapon only, "-" none. (Guest holds torch in hand + sword sheathed for "ts".)
function WO_HostHeldClass(a : CActor) : string
{
    var inv : CInventoryComponent;
    var items : array<SItemUniqueId>;
    var i : int;
    var dm : CDefinitionsManagerAccessor;
    var nm, cat : name;
    var hasTorch, hasWeapon : bool;
    var cls : string;

    if (!a) return "-";
    inv = a.GetInventory();
    if (!inv) return "-";
    dm = theGame.GetDefinitionsManager();
    inv.GetAllItems(items);

    hasTorch = false;
    hasWeapon = false;
    for (i = 0; i < items.Size(); i += 1)
    {
        nm = inv.GetItemName(items[i]);
        cat = dm.GetItemCategory(nm);
        if (cat == 'torch' || cat == 'lights' || nm == 'Torch_work' || nm == 'Torch' || nm == 'Torch_work_right')
            hasTorch = true;
        else if (dm.IsItemWeapon(nm) && cat != 'fist')
            hasWeapon = true;
    }

    cls = "";
    if (hasTorch)  cls += "t";
    if (hasWeapon) cls += "s";
    if (cls == "") cls = "-";
    return cls;
}

// True if 's' contains substring 'sub'.
function WO_StrContains(s : string, sub : string) : bool
{
    var a, b : string;
    return StrSplitFirst(s, sub, a, b);
}

// Read an NPC's monster-type fingerprint ability (e.g. 'mon_evil_dog' for a wild dog,
// 'mon_drowner' for a drowner). This is the EXACT type — unlike appearance, it distinguishes
// wild_dog from pet dog. Filters out the secondary mon_* abilities (_weapon/_head/_tail/
// _wing/_base/_ngnerf). Returns "" for humans/animals (no mon_ ability).
function WO_GetMonsterTypeAbility(a : CActor) : string
{
    var cs : CCharacterStats;
    var abils : array<name>;
    var i : int;
    var s : string;

    if (!a) return "";
    cs = a.GetCharacterStats();
    if (!cs) return "";
    cs.GetAbilities(abils, false);

    for (i = 0; i < abils.Size(); i += 1)
    {
        s = NameToString(abils[i]);
        if (!WO_StartsWith(s, "mon_")) continue;
        if (WO_StrContains(s, "_weapon")) continue;
        if (WO_StrContains(s, "_head"))   continue;
        if (WO_StrContains(s, "_tail"))   continue;
        if (WO_StrContains(s, "_wing"))   continue;
        if (WO_StrContains(s, "_base"))   continue;
        if (WO_StrContains(s, "_ngnerf")) continue;
        return s;   // the specific type ability
    }
    return "";
}

@addField(CR4Game) public var wo_host_npc_registry : WO_HostNpcRegistry;

@addMethod(CR4Game)
public function WO_GetHostNpcRegistry() : WO_HostNpcRegistry
{
    if (!this.wo_host_npc_registry)
        this.wo_host_npc_registry = new WO_HostNpcRegistry in this;
    return this.wo_host_npc_registry;
}

function WO_AssignNpcId(actor : CActor) : int
{
    var reg : WO_HostNpcRegistry;
    var i, freeSlot : int;
    reg = theGame.WO_GetHostNpcRegistry();

    // Fast path: actor already registered.
    for (i = 0; i < reg.actors.Size(); i += 1)
    {
        if (reg.actors[i] == actor)
            return i + 1;
    }

    // Fix 2: Slot reuse — fills dead/null slots before growing the array.
    // Prevents unbounded memory growth over long sessions (the registry never shrinks otherwise).
    freeSlot = -1;
    for (i = 0; i < reg.actors.Size(); i += 1)
    {
        if (!reg.actors[i])
        {
            freeSlot = i;
            break;
        }
    }

    if (freeSlot >= 0)
    {
        reg.actors[freeSlot] = actor;
        reg.types[freeSlot] = WO_GetMonsterTypeAbility(actor);
        reg.held[freeSlot] = WO_HostHeldClass(actor);
        WO_ScaleNpcHp(actor);
        return freeSlot + 1;
    }

    // No free slot: grow the array (only when every slot is occupied by a live NPC).
    reg.actors.PushBack(actor);
    reg.types.PushBack(WO_GetMonsterTypeAbility(actor));
    reg.held.PushBack(WO_HostHeldClass(actor));
    
    // Scale NPC HP upward based on party size (only host's true NPCs)
    WO_ScaleNpcHp(actor);
    
    return reg.actors.Size();
}

function WO_ScaleNpcHp(actor : CActor)
{
    var state : WO_SpikeState;
    var maxHp : float;
    state = theGame.WO_GetSpikeState();
    if (state.party_size > 1 && !actor.HasTag('wo_party_scaled'))
    {
        actor.AddTag('wo_party_scaled');
        maxHp = actor.GetStatMax(BCS_Vitality);
        actor.AbilityManager().SetStatPointMax(BCS_Vitality, maxHp * state.party_size);
        actor.ForceSetStat(BCS_Vitality, maxHp * state.party_size);
    }
}

// Fix 2: Periodic GC for the host NPC registry. Nulls slots whose actor is no longer
// alive or valid, freeing them for reuse by WO_AssignNpcId. Runs every ~10s from the
// render timer (render_tick_count % 600). Logs freed count to scriptslog for verification.
function WO_HostNpcRegistryGC()
{
    var reg : WO_HostNpcRegistry;
    var i, freed : int;
    reg = theGame.WO_GetHostNpcRegistry();
    freed = 0;
    for (i = 0; i < reg.actors.Size(); i += 1)
    {
        if (reg.actors[i] && !reg.actors[i].IsAlive())
        {
            reg.actors[i] = NULL;
            reg.types[i] = "";
            reg.held[i] = "";
            freed += 1;
        }
    }
    if (freed > 0)
        Log("WO_NPC_GC: freed " + freed + " dead slots (registry size=" + reg.actors.Size() + ")");
}

// Kill switch   false    host emit (  spike #1-3   )
function WO_NPC_SYNC_HOST_ENABLED() : bool { return true; }

// Should this actor be broadcast as a syncable NPC?
function WO_IsBroadcastableNpc(a : CActor) : bool
{
    if (!a) return false;
    if (a == thePlayer) return false;
    if (a.HasTag('wo_remote_npc')) return false;   // don't re-broadcast network NPCs
    if (a.HasTag('wo_ghost_player')) return false;  // players handled by UPDATE1A
    if (a.HasTag('MPEntity')) return false;         // remote-player ghosts/horses/boats
    if (a.HasTag('online_horse')) return false;
    if (a.HasTag('wo_horse')) return false;
    if (!a.IsAlive()) return false;
    return true;
}

// Add actors in range of 'center' to 'list', skipping ones already present (dedup).
function WO_CollectNpcsNear(center : CActor, list : array<CActor>) : array<CActor>
{
    var found : array<CActor>;
    var i, j : int;
    var dup : bool;
    if (!center) return list;
    found = GetActorsInRange(center, 50.0, 30);
    for (i = 0; i < found.Size(); i += 1)
    {
        if (!WO_IsBroadcastableNpc(found[i])) continue;
        dup = false;
        for (j = 0; j < list.Size(); j += 1)
        {
            if (list[j] == found[i]) { dup = true; break; }
        }
        if (!dup)
            list.PushBack(found[i]);
    }
    return list;
}

// IMPORTANT: must ALWAYS Log a "wo_npc" line (bare tag when empty), otherwise the
// DLL's ExecTagged waits the full timeout every cycle -> huge per-cycle latency.
exec function wo_get_npcs(playerId : string)
{
    var actors : array<CActor>;
    var ghosts : array<CEntity>;
    var i, n_emitted, npc_id : int;
    var pos : Vector;
    var payload : string;
    var a : CActor;
    var npc : CNewNPC;
    var reg : WO_HostNpcRegistry;

    // Guest has no own NPCs to broadcast; also skip while paused/cutscene (NPCs frozen,
    // nothing meaningful to send). Always emit the marker so the DLL doesn't time out.
    if (WO_IS_GUEST() || !WO_NPC_SYNC_HOST_ENABLED() || WO_GameBusy())
    {
        Log("wo_npc");
        return;
    }

    // Fix 4: Host-side render timer watchdog. DLL calls wo_get_npcs every poll cycle so
    // this is a reliable bootstrap trigger — fires well before the first jump.
    if (!thePlayer.HasTag('wo_timers_started'))
    {
        thePlayer.AddTag('wo_timers_started');
        WO_EnsureTimers();
        GetWitcherPlayer().DisplayHudMessage("WO: timers bootstrapped from host poll");
    }

    // Collect NPCs near the host player AND near each guest ghost, so the guest sees
    // the NPCs around ITS OWN position (e.g. monsters that aggro'd the ghost), not just
    // the ones around the host.
    actors = WO_CollectNpcsNear(thePlayer, actors);
    theGame.GetEntitiesByTag('MPEntity', ghosts);
    for (i = 0; i < ghosts.Size(); i += 1)
        actors = WO_CollectNpcsNear((CActor)ghosts[i], actors);

    reg = theGame.WO_GetHostNpcRegistry();
    n_emitted = 0;
    for (i = 0; i < actors.Size(); i += 1)
    {
        a = actors[i];
        if (!a) continue;

        npc_id = WO_AssignNpcId(a);
        pos = a.GetWorldPosition();

        // Per-NPC chunk: "<id> <x_cm> <y_cm> <z_cm> <alive> <yawDeg> <hp%> <appearance> <type> <held>"
        // <type> = exact monster fingerprint (mon_*) or "-"; <held> = "s"/"t"/"-" held-item class.
        if (n_emitted > 0)
            payload += "|";
        payload += npc_id;
        payload += " ";
        payload += (int)(pos.X * 100.0);
        payload += " ";
        payload += (int)(pos.Y * 100.0);
        payload += " ";
        payload += (int)(pos.Z * 100.0);
        payload += " 1 ";   // alive (dead were skipped above)
        payload += (int)a.GetHeading();   // facing yaw in degrees
        payload += " ";
        payload += (int)(a.GetStatPercents(BCS_Vitality) * 100.0);   // hp 0..100
        payload += " ";
        payload += a.GetAppearance();
        payload += " ";
        if (reg.types[npc_id - 1] != "")
            payload += reg.types[npc_id - 1];   // exact type token
        else
            payload += "-";
        payload += " ";
        payload += reg.held[npc_id - 1];        // held-item class (cached)
        payload += " ";
        if (a.IsInCombat())                     // combat flag (DYNAMIC — recomputed each broadcast)
            payload += "c";
        else
            payload += "-";
        payload += " ";
        // attack flag (DYNAMIC) — true during a real swing; drives the guest's one-shot swing anim.
        // IsAttacking() reads combatStorage.GetIsAttacking() on the host's real combat NPC.
        npc = (CNewNPC)a;
        if (npc && npc.IsAttacking())
            payload += "a";
        else
            payload += "-";
        n_emitted += 1;

        if (StrLen(payload) > 900)   // server warns at 1200 bytes; leave headroom
            break;
    }

    // Emit alive=0 chunks for NPCs killed since last broadcast so guests despawn them
    // immediately. Format per chunk: "<id> 0 0 0 0 0 dead".
    reg = theGame.WO_GetHostNpcRegistry();
    for (i = 0; i < reg.killed.Size(); i += 1)
    {
        if (n_emitted > 0)
            payload += "|";
        payload += reg.killed[i];
        
        // Embed XP value in the hp_pct field of the alive=0 broadcast so guest gets XP
        var xp : int;
        if (reg.killed[i] - 1 >= 0 && reg.killed[i] - 1 < reg.types.Size())
            xp = WO_GetXpForType(reg.types[reg.killed[i] - 1]);
        else
            xp = 10;
            
        payload += " 0 0 0 0 0 " + IntToString(xp) + " dead - - - -";   // x y z alive yaw hp(XP) appearance type held combat attack
        n_emitted += 1;
    }
    reg.killed.Clear();

    if (n_emitted > 0)
        Log("wo_npc " + payload);
    else
        Log("wo_npc");   // empty marker — never make the DLL wait for a timeout
}

// ---- Guest side: remote NPC state + render ----

class WO_RemoteNpcEntry
{
    public var key : string;            // hostId + ":" + npcId
    public var actor : CActor;
    public var curr_pos : Vector;
    public var target_pos : Vector;
    public var alive : bool;
    public var last_update : float;
    public var has_state : bool;
    public var update_count : int;
    public var hidden_prox : bool;   // hidden because it's clipping into the local player
    public var yaw : float;          // synced facing (degrees) for when standing still
    public var last_interval : float; // seconds between the last two updates (for adaptive slide)
    public var smooth_interval : float; // EMA of last_interval — stable slide duration (anti-jitter)
    public var velocity : Vector;       // EMA world velocity (m/s) — for extrapolation during packet gaps
    public var face_yaw : float;     // smoothed facing we actually rotate toward (anti-jitter)
    public var face_init : bool;     // face_yaw seeded yet?
    public var appearance : string;  // captured at spawn — needed for loot-on-death (dead chunk has app="dead")
    public var npcType : string;     // captured mon_* fingerprint — exact loot-on-death + future
    public var weap_done : bool;     // weapon mounted/added yet? (retried in render until settled)
    public var weap_tries : int;     // throttle/cap the weapon-mount retries
    public var held : string;        // host-provided held-item class: "s"=sword "t"=torch "-"=none
    public var inCombat : bool;      // synced combat state — drives draw-sword / stow-torch pose
    public var pose_init : bool;     // has the combat pose been applied at least once?
    public var cur_anim : name;      // combat slot-anim currently playing ('' = none / native locomotion)
    public var anim_end : float;     // engine time to re-queue the looping combat anim
    public var is_attacking : bool;  // synced host IsAttacking() — drives one-shot swing anim
    public var was_attacking : bool; // previous frame's is_attacking, for rising-edge detection
    public var swing_until : float;  // engine time the current swing anim holds until (then resume stance)
    public var swing_idx : int;      // rotates through the attack anim variants
}

class WO_RemoteNpcRegistry
{
    public var entries : array<WO_RemoteNpcEntry>;
}

@addField(CR4Game) public var wo_remote_npc_state : WO_RemoteNpcRegistry;

@addMethod(CR4Game)
public function WO_GetRemoteNpcState() : WO_RemoteNpcRegistry
{
    if (!this.wo_remote_npc_state)
        this.wo_remote_npc_state = new WO_RemoteNpcRegistry in this;
    return this.wo_remote_npc_state;
}

function WO_FindRemoteByKey(key : string) : WO_RemoteNpcEntry
{
    var rns : WO_RemoteNpcRegistry;
    var i : int;
    rns = theGame.WO_GetRemoteNpcState();
    for (i = 0; i < rns.entries.Size(); i += 1)
    {
        if (rns.entries[i].key == key)
            return rns.entries[i];
    }
    return NULL;
}

function WO_FindRemoteByActor(actor : CActor) : WO_RemoteNpcEntry
{
    var rns : WO_RemoteNpcRegistry;
    var i : int;
    rns = theGame.WO_GetRemoteNpcState();
    for (i = 0; i < rns.entries.Size(); i += 1)
    {
        if (rns.entries[i].actor == actor)
            return rns.entries[i];
    }
    return NULL;
}

// GUEST: when the local player damages a marionette, forward the hit to the host so it
// applies damage to the REAL NPC. The marionette itself is immortal (no local death);
// the host's broadcast (alive=0) despawns it when the real NPC dies.
// (Hit detection is poll-based in wo_npc_render60hz via WO_DetectAndForwardHits — see
//  below. We avoid wrapping the OnTakeDamage event, which doesn't expose wrappedMethod.)

// Map an NPC appearance name to a template path. Uses only known-good templates;
// the appearance's first token (split on '_') picks the category.
// Returns "" for "treat as human" (caller uses humanoid ghost template).
// true: spawn the NPC's REAL vanilla template (found via REDkit) so guards look like
// guards, villagers like villagers, etc. The template's default appearance is a valid
// variant of that type — good enough without per-variant SetAppearance.
function WO_USE_REAL_TEMPLATES() : bool { return true; }

function WO_StartsWith(s : string, prefix : string) : bool
{
    var before, after : string;
    if (StrSplitFirst(s, prefix, before, after))
        return before == "";   // prefix found at index 0
    return false;
}

// Map an NPC appearance name to its real vanilla template path (depot-relative).
// Paths confirmed via REDkit: each template's .w2ent contains the listed appearances.
function WO_TemplateForAppearance(app : string) : string
{
    var monsterPath : string;

    if (!WO_USE_REAL_TEMPLATES())
        return "characters\npc_entities\monsters\drowner_lvl1.w2ent";

    // Monsters — full table (drowner, wolf, nekker, ghoul, wraith, hag, ...).
    monsterPath = WO_MonsterTemplate(app);
    if (monsterPath != "")
        return monsterPath;

    // Humans (Velen / Novigrad / Skellige crowd)
    if (WO_StartsWith(app, "nml_baron_guard"))
        return "characters\npc_entities\crowd_npc\nml_soldier\nml_baron_guard_lvl1.w2ent";
    if (WO_StartsWith(app, "village_woman"))
        return "characters\npc_entities\crowd_npc\nml_villager\nml_villager_woman.w2ent";
    if (WO_StartsWith(app, "nml_villager"))   // nml_villager_crowd_* and __mh* live here
        return "characters\npc_entities\crowd_npc\nml_villager\nml_villager.w2ent";
    if (WO_StartsWith(app, "citizen"))
        return "characters\npc_entities\crowd_npc\novigrad_citizen\novigrad_citizen.w2ent";
    if (WO_StartsWith(app, "skellige_villager_woman"))
        return "characters\npc_entities\crowd_npc\skellige_villager\skellige_villager_woman.w2ent";
    if (WO_StartsWith(app, "skellige_boy"))
        return "characters\npc_entities\crowd_npc\skellige_villager\skellige_child_boy.w2ent";

    // Animals
    if (WO_StartsWith(app, "cat"))
        return "characters\npc_entities\animals\cat.w2ent";
    if (WO_StartsWith(app, "dog"))
        return "characters\npc_entities\animals\dog.w2ent";
    if (WO_StartsWith(app, "pig"))
        return "characters\npc_entities\animals\pig.w2ent";
    if (WO_StartsWith(app, "horse"))
        return "characters\npc_entities\animals\horse\horse_background_no_saddle.w2ent";

    // Unknown -> villager (humanoid, complete) is a safer default than a drowner for
    // the mostly-human world; falls back to drowner only if that fails to load.
    return "characters\npc_entities\crowd_npc\nml_villager\nml_villager.w2ent";
}

// Map an EXACT monster type fingerprint (mon_*) to its template — this is precise and
// resolves appearance collisions (mon_evil_dog -> wild_dog, NOT the pet dog). Returns ""
// if the type isn't a known monster (then caller falls back to appearance mapping).
function WO_TemplateForType(t : string) : string
{
    if (t == "" || t == "-") return "";
    if (WO_StartsWith(t, "mon_drowner"))    return "characters\npc_entities\monsters\drowner_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_evil_dog"))   return "characters\npc_entities\monsters\wild_dog_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_wolf"))       return "characters\npc_entities\monsters\wolf_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_warg"))       return "characters\npc_entities\monsters\wolf_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_werewolf"))   return "characters\npc_entities\monsters\werewolf_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_nekker"))     return "characters\npc_entities\monsters\nekker_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_alghoul"))    return "characters\npc_entities\monsters\alghoul_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_ghoul"))      return "characters\npc_entities\monsters\ghoul_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_rotfiend"))   return "characters\npc_entities\monsters\rotfiend_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_bear"))       return "characters\npc_entities\monsters\bear_berserker_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_harpy"))      return "characters\npc_entities\monsters\harpy_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_siren"))      return "characters\npc_entities\monsters\siren_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_fogling"))    return "characters\npc_entities\monsters\fogling_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_arachas"))    return "characters\npc_entities\monsters\arachas_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_nightwraith"))return "characters\npc_entities\monsters\nightwraith_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_noonwraith")) return "characters\npc_entities\monsters\noonwraith_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_wraith"))     return "characters\npc_entities\monsters\wraith_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_grave_hag"))  return "characters\npc_entities\monsters\hag_grave_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_water_hag"))  return "characters\npc_entities\monsters\hag_water_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_hag"))        return "characters\npc_entities\monsters\hag_water_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_katakan"))    return "characters\npc_entities\monsters\vampire_katakan_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_ekimmara"))   return "characters\npc_entities\monsters\vampire_ekima_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_forktail"))   return "characters\npc_entities\monsters\forktail_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_wyvern"))     return "characters\npc_entities\monsters\wyvern_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_cockatrice")) return "characters\npc_entities\monsters\cockatrice_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_gryphon"))    return "characters\npc_entities\monsters\gryphon_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_griffin"))    return "characters\npc_entities\monsters\gryphon_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_troll"))      return "characters\npc_entities\monsters\troll_cave_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_cyclop"))     return "characters\npc_entities\monsters\cyclop_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_golem"))      return "characters\npc_entities\monsters\golem_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_gargoyle"))   return "characters\npc_entities\monsters\gargoyle_lvl1.w2ent";
    if (WO_StartsWith(t, "mon_basilisk"))   return "characters\npc_entities\monsters\basilisk_lvl1.w2ent";
    return "";
}

function WO_CreateRemoteMarionette(key : string, pos : Vector, appearance : string, npcType : string, held : string) : WO_RemoteNpcEntry
{
    var template : CEntityTemplate;
    var path : string;
    var rot : EulerAngles;
    var tagList : array<name>;
    var actor : CActor;
    var e : WO_RemoteNpcEntry;
    var rns : WO_RemoteNpcRegistry;

    // Prefer EXACT type (mon_* fingerprint); fall back to appearance mapping for humans/animals.
    path = WO_TemplateForType(npcType);
    if (path == "")
        path = WO_TemplateForAppearance(appearance);
    template = (CEntityTemplate)LoadResource(path, true);
    if (!template)   // fallback to drowner if mapped path failed to load
    {
        Log("WO_NPC type=" + npcType + " app=" + appearance + " path=" + path + " LOAD_FAILED -> drowner");
        template = (CEntityTemplate)LoadResource("characters\npc_entities\monsters\drowner_lvl1.w2ent", true);
    }
    else
    {
        Log("WO_NPC type=" + npcType + " app=" + appearance + " path=" + path + " loaded OK");
    }
    if (!template) return NULL;

    rot.Pitch = 0; rot.Yaw = 0; rot.Roll = 0;
    tagList.Clear();
    tagList.PushBack('wo_remote_npc');

    actor = (CActor)theGame.CreateEntity(template, pos, rot, true, true, false, PM_DontPersist, tagList);
    if (!actor) return NULL;

    // Apply the EXACT host appearance variant BEFORE suppression/weapon-mount (ApplyAppearance
    // can reset components). Gives the precise outfit/variant instead of the template default.
    WO_ApplyVariant(actor, appearance);

    // Friendly DoNothing puppet + mount weapons.
    WO_ApplyMarionetteSuppression(actor, appearance);

    e = new WO_RemoteNpcEntry in theGame;
    e.key = key;
    e.actor = actor;
    e.appearance = appearance;
    e.npcType = npcType;
    e.held = held;
    e.weap_done = WO_MountWeapons(actor, held);   // retried in render until settled
    e.curr_pos = pos;
    e.target_pos = pos;
    e.alive = true;
    e.last_update = theGame.GetEngineTimeAsSeconds();
    e.has_state = true;

    rns = theGame.WO_GetRemoteNpcState();
    rns.entries.PushBack(e);
    return e;
}

// Parse one NPC chunk: "<id> <x_cm> <y_cm> <z_cm> <alive> <yawDeg> <hpPct> <appearance>"
function WO_ParseNpcChunk(hostId : string, chunk : string)
{
    var rem, tok, appearance, npcType, npcHeld, npcCombat, npcAttack : string;
    var npc_id, x_cm, y_cm, z_cm, alive_int, yaw_deg, hp_pct : int;
    var pos, newVel : Vector;
    var key : string;
    var e : WO_RemoteNpcEntry;
    var nowSec, iv, velMag : float;
    var ss2 : WO_SpikeState;

    rem = chunk;
    if (!StrSplitFirst(rem, " ", tok, rem)) return;
    npc_id = StringToInt(tok, -1);
    if (npc_id < 0) return;

    if (!StrSplitFirst(rem, " ", tok, rem)) return;
    x_cm = StringToInt(tok, 0);

    if (!StrSplitFirst(rem, " ", tok, rem)) return;
    y_cm = StringToInt(tok, 0);

    if (!StrSplitFirst(rem, " ", tok, rem)) return;
    z_cm = StringToInt(tok, 0);

    if (!StrSplitFirst(rem, " ", tok, rem)) return;
    alive_int = StringToInt(tok, 1);

    if (!StrSplitFirst(rem, " ", tok, rem)) return;
    yaw_deg = StringToInt(tok, 0);

    // hp, then appearance (token), then type (token), then held (remaining; older chunks omit it)
    hp_pct = 100;
    appearance = "";
    npcType = "";
    npcHeld = "-";
    npcCombat = "-";
    npcAttack = "-";
    if (StrSplitFirst(rem, " ", tok, rem))
    {
        hp_pct = StringToInt(tok, 100);
        if (StrSplitFirst(rem, " ", tok, rem))
        {
            appearance = tok;
            if (StrSplitFirst(rem, " ", tok, rem))
            {
                npcType = tok;
                // held token, then combat token, then attack = remainder (older chunks omit some)
                if (StrSplitFirst(rem, " ", tok, rem))
                {
                    npcHeld = tok;
                    if (StrSplitFirst(rem, " ", tok, rem))
                    {
                        npcCombat = tok;
                        npcAttack = rem;
                    }
                    else
                    {
                        npcCombat = rem;
                    }
                }
                else
                {
                    npcHeld = rem;
                }
            }
            else
            {
                npcType = rem;
            }
        }
        else
        {
            appearance = rem;
        }
    }
    else
    {
        appearance = rem;
    }

    pos.X = x_cm / 100.0;
    pos.Y = y_cm / 100.0;
    pos.Z = z_cm / 100.0;
    pos.W = 1.0;

    key = hostId + ":" + npc_id;
    e = WO_FindRemoteByKey(key);

    // alive=0 -> the real NPC died on the host. Kill the marionette properly so it plays
    // a death animation and leaves a corpse (matching the host), instead of vanishing.
    if (alive_int == 0)
    {
        if (e && e.actor)
        {
            // Instanced shared-kill loot: the guest gets curated loot for this monster type
            // (from the game's own loot tables) the moment the host's NPC dies. Host loots
            // its real corpse normally. Guest-only; once per death (guarded by e.actor).
            if (WO_IS_GUEST())
            {
                // Prefer EXACT loot by mon_* fingerprint (precise, covers wild_dog); fall back
                // to appearance mapping for humans/animals (type "-"/"-1"/"" = not a monster).
                if (WO_StartsWith(e.npcType, "mon_"))
                    WO_GrantLootForType(e.npcType);
                else
                    WO_GrantLootForAppearance(e.appearance);
                    
                if (hp_pct > 0)
                    GetWitcherPlayer().AddPoints( EExperiencePoint, hp_pct, true );
            }

            e.actor.SetImmortalityMode(AIM_None, AIC_Default, true);
            e.actor.Kill('wo_death', true, thePlayer);
            e.actor = NULL;
        }
        return;
    }

    if (!e)
        e = WO_CreateRemoteMarionette(key, pos, appearance, npcType, npcHeld);

    if (e)
    {
        nowSec = theGame.GetEngineTimeAsSeconds();
        // Inter-update interval (seconds) — drives adaptive slide so motion never freezes.
        // EMA-smooth it so the slide duration is stable instead of jumping with each uneven
        // round-trip (uneven duration was the residual per-NPC jitter).
        if (e.last_update > 0.0 && nowSec > e.last_update)
        {
            e.last_interval = nowSec - e.last_update;
            if (e.smooth_interval <= 0.0)
                e.smooth_interval = e.last_interval;
            else
                e.smooth_interval = e.smooth_interval * 0.7 + e.last_interval * 0.3;

            // World velocity from displacement over the interval, for extrapolation during
            // packet gaps (keeps fast movers — running dogs — gliding instead of freezing).
            iv = e.last_interval;
            if (iv < 0.05) iv = 0.05;
            newVel = (pos - e.target_pos) * (1.0 / iv);
            velMag = VecLength(newVel);
            if (velMag > 9.0)   // teleport-sized jump -> don't extrapolate a bogus velocity
            {
                newVel.X = 0.0; newVel.Y = 0.0; newVel.Z = 0.0;
            }
            // EMA the velocity so it's stable.
            e.velocity.X = e.velocity.X * 0.5 + newVel.X * 0.5;
            e.velocity.Y = e.velocity.Y * 0.5 + newVel.Y * 0.5;
            e.velocity.Z = e.velocity.Z * 0.5 + newVel.Z * 0.5;
        }

        e.target_pos = pos;
        e.yaw = yaw_deg;
        e.alive = true;
        e.last_update = nowSec;
        e.update_count += 1;

        // Combat pose: when the host NPC's IsInCombat flips, draw the sword / stow the torch
        // (or reverse). Re-pose only on change (or first sight) to avoid re-mounting every frame.
        if (!e.pose_init || e.inCombat != (npcCombat == "c"))
        {
            e.inCombat = (npcCombat == "c");
            e.pose_init = true;
            WO_UpdateHeldPose(e);
        }

        // Per-frame attack flag (rising edge -> one-shot swing anim, handled in WO_DriveCombatAnim).
        e.is_attacking = (npcAttack == "a");

        // Global rate counter for the HUD readout (updates/sec across all NPCs).
        ss2 = theGame.WO_GetSpikeState();
        ss2.npc_update_events += 1;

        // Sync health so the floating health bar (on hostile monster marionettes) is accurate.
        // SetHealthPerc expects 0..1; we transmit 0..100.
        if (e.actor && hp_pct >= 0)
            e.actor.SetHealthPerc( hp_pct / 100.0 );
    }
}

exec function wo_party_update(countStr : string)
{
    var state : WO_SpikeState;
    var count : int;
    
    count = StringToInt(countStr);
    if (count < 1) count = 1;
    
    state = theGame.WO_GetSpikeState();
    state.party_size = count;
}

exec function wo_npc_update(hostId : string, payload : string)
{
    var rem, chunk : string;

    if (hostId == "" || payload == "")
        return;

    // Don't spawn/update marionettes while the guest is paused/in menu/cutscene.
    if (WO_GameBusy())
        return;

    // Bootstrap timers from here (guaranteed to run on guest when packets arrive).
    if (!thePlayer.HasTag('wo_timers_started'))
    {
        thePlayer.AddTag('wo_timers_started');
        WO_EnsureTimers();
        GetWitcherPlayer().DisplayHudMessage("WO: timers bootstrapped from npc_update");
    }

    rem = payload;
    while (StrSplitFirst(rem, "|", chunk, rem))
    {
        WO_ParseNpcChunk(hostId, chunk);
    }
    // tail (last NPC after final |, or whole payload if no |)
    if (StrLen(rem) > 0)
        WO_ParseNpcChunk(hostId, rem);
}

// Move a marionette using the EXACT technique the base mod uses for its (perfectly smooth)
// player ghost — see r_RemotePlayer.moveEntity: a long 1-second SlideTo re-issued every
// frame heavily damps all packet jitter into a smooth glide, with a huge teleport threshold
// so it almost never pops. No extrapolation needed — the long slide IS the smoothing.
function WO_MoveMarionette(e : WO_RemoteNpcEntry)
{
    var actor : CActor;
    var mac : CMovingAgentComponent;
    var adjustor : CMovementAdjustor;
    var ticket : SMovementAdjustmentRequestTicket;
    var entpos, targpos : Vector;
    var dist, moveHeading, velMag : float;
    var moving : bool;

    actor = e.actor;
    if (!actor) return;

    mac = actor.GetMovingAgentComponent();
    if (!mac)
    {
        actor.TeleportWithRotation(e.target_pos, actor.GetWorldRotation());
        return;
    }

    targpos = e.target_pos;
    entpos = actor.GetWorldPosition();
    dist = VecDistance(entpos, targpos);
    moving = (dist > 0.04);
    moveHeading = VecHeading(targpos - entpos);
    velMag = VecLength(e.velocity);   // synced velocity, used only to pick walk vs run anim

    // Only a MASSIVE desync hard-teleports (mod's ghost uses 200). Otherwise ALWAYS slide —
    // never freeze, never pop. This is the key difference from our old 25m threshold.
    if (dist > 200.0)
    {
        actor.Teleport(targpos);
        return;
    }

    // Drive the native locomotion graph: move direction for strafe blend, speed scaled by
    // real velocity so a running NPC plays a run cycle and a walking one a walk.
    if (moving)
    {
        mac.SetGameplayMoveDirection(moveHeading);
        mac.SetGameplayRelativeMoveSpeed( ClampF(velMag / 5.0, 0.4, 1.0) );
    }
    else
    {
        mac.SetGameplayRelativeMoveSpeed(0.0);
    }

    adjustor = mac.GetMovementAdjustor();
    adjustor.Cancel(adjustor.GetRequest('wo_npc_move'));
    ticket = adjustor.CreateNewRequest('wo_npc_move');
    adjustor.AdjustmentDuration(ticket, 1.0);           // 1s slide — the ghost-smoothness secret
    adjustor.AdjustLocationVertically(ticket, true);    // follow ground height
    adjustor.ScaleAnimationLocationVertically(ticket, true);
    adjustor.RotateTo(ticket, e.yaw);                   // rotate toward the host's synced facing
    adjustor.SlideTo(ticket, targpos);
}

// NOTE: a local cosmetic W3DamageAction on the marionette to "show the hit" was tried
// (V43) and KILLED the immortal marionette in one swing -> it despawned before the guest
// could land the 2-3 hits the host NPC needs, so the real NPC survived. Reverted. Any
// future guest-side hit feedback must use a pure animation slot, NOT a damage action.

// GUEST hit detection (poll-based): when the local player performs a light/heavy attack
// (tracked by the base mod), forward a hit to every marionette within a melee cone in
// front of the player. The host then applies damage to the real NPC.
function WO_DetectAndForwardHits()
{
    var ss : WO_SpikeState;
    var atk : float;
    var rns : WO_RemoteNpcRegistry;
    var i : int;
    var ppos, fwd, toNpc : Vector;
    var dist, dot : float;
    var rem, host, npcIdStr : string;
    var npcId : int;

    ss = theGame.WO_GetSpikeState();
    atk = MaxF(theGame.r_getMultiplayerClient().getLastLightTime(),
               theGame.r_getMultiplayerClient().getLastHeavyTime());

    if (atk <= ss.last_seen_attack)   // no new attack since last frame
        return;
    ss.last_seen_attack = atk;

    ppos = thePlayer.GetWorldPosition();
    fwd = thePlayer.GetWorldForward();
    rns = theGame.WO_GetRemoteNpcState();

    for (i = 0; i < rns.entries.Size(); i += 1)
    {
        if (!rns.entries[i] || !rns.entries[i].actor) continue;
        toNpc = rns.entries[i].actor.GetWorldPosition() - ppos;
        dist = VecLength2D(toNpc);
        if (dist > 3.0 || dist < 0.01) continue;          // melee range
        dot = (fwd.X * toNpc.X + fwd.Y * toNpc.Y) / dist; // cos angle to facing
        if (dot < 0.3) continue;                          // ~within front cone

        rem = rns.entries[i].key;
        if (StrSplitFirst(rem, ":", host, npcIdStr))
        {
            npcId = StringToInt(npcIdStr, -1);
            if (npcId >= 0)
                WO_EnqueueHit(host, npcId, 35);   // ~2-3 hits to kill (was 100 = one-shot)
        }
    }
}

// ---- 60Hz render   remote NPCs ----
@addMethod(CR4Player)
timer function wo_npc_render60hz(dt : float, id : int)
{
    var rns : WO_RemoteNpcRegistry;
    var e : WO_RemoteNpcEntry;
    var i, alive_count : int;
    var now, nearDist, d : float;
    var ss : WO_SpikeState;
    var msg, nearApp : string;
    var ppos : Vector;

    // Skip all marionette movement/cleanup while paused/menu/cutscene.
    if (WO_GameBusy())
        return;

    rns = theGame.WO_GetRemoteNpcState();
    now = theGame.GetEngineTimeAsSeconds();
    alive_count = 0;
    ppos = thePlayer.GetWorldPosition();
    nearDist = 9999.0;
    nearApp = "";

    for (i = 0; i < rns.entries.Size(); i += 1)
    {
        e = rns.entries[i];
        if (!e || !e.actor) continue;

        // Despawn stale (no update for 5 sec)
        if (now - e.last_update > 5.0)
        {
            e.actor.Destroy();
            e.actor = NULL;
            continue;
        }

        // Track the nearest marionette's appearance/type for the HUD diagnostic.
        d = VecDistance(ppos, e.actor.GetWorldPosition());
        if (d < nearDist)
        {
            nearDist = d;
            nearApp = e.appearance + " held=" + e.held + " cbt=" + e.inCombat + " atk=" + e.is_attacking + " anim=" + e.cur_anim;
        }

        // All marionettes are position-synced puppets (smooth SlideTo from host coords).
        WO_MoveMarionette(e);
        WO_DriveCombatAnim(e, now);   // overlay combat-stance slot anim when the host NPC is fighting
        alive_count += 1;

        // Retry weapon mount until settled (armed humans whose inventory wasn't ready at spawn,
        // or whose early mount got cleared by the appearance rebuild). Throttled + capped.
        if (!e.weap_done && e.weap_tries < 90)
        {
            e.weap_tries += 1;
            if (e.weap_tries % 15 == 1)
                e.weap_done = WO_MountWeapons(e.actor, e.held);
        }
    }

    // GUEST: detect the local player's melee swings and forward hits to marionettes in
    // front (host applies the damage to the real NPC).
    if (WO_IS_GUEST())
        WO_DetectAndForwardHits();

    // Fold cleanup INTO render timer (guaranteed co-run). Every ~60 ticks (~1s).
    ss = theGame.WO_GetSpikeState();
    ss.render_tick_count += 1;
    if (ss.render_tick_count % 60 == 0)
    {
        if (WO_IS_GUEST())
            WO_DoGuestCleanup();
        else
            WO_MakeGhostsAttackable();   // HOST: let hostile NPCs attack the guest's ghost

        // Fix 2: Host NPC registry GC every ~10s (600 ticks @ 60Hz). Prevents unbounded growth.
        if (!WO_IS_GUEST() && ss.render_tick_count % 600 == 0)
            WO_HostNpcRegistryGC();

        // Measure NPC update rate (updates/sec across all NPCs) over the elapsed window.
        if (ss.npc_rate_last_time > 0.0 && now > ss.npc_rate_last_time)
        {
            ss.npc_rate_hz = (int)((ss.npc_update_events - ss.npc_rate_last_events)
                                   / (now - ss.npc_rate_last_time));
        }
        ss.npc_rate_last_events = ss.npc_update_events;
        ss.npc_rate_last_time = now;
    }

    // Refresh the HUD ~2x/sec so the diagnostic stays readable (DisplayHudMessage fades fast).
    if (ss.render_tick_count % 30 == 0)
    {
        msg = "V84 g=";
        if (WO_IS_GUEST()) msg += "Y"; else msg += "n";
        msg += " npc=" + alive_count;
        msg += " near[" + nearApp + "]";   // nearest marionette appearance/type
        if (WO_IS_GUEST())
            msg += " arm[" + ss.arm_dbg + "]";
        else
            msg += " ghost[" + ss.ghost_dbg + "]";   // HOST: combat-target diagnostic (CD=Y/n vis atk)
        GetWitcherPlayer().DisplayHudMessage(msg);

        // Unconditional heartbeat to scriptslog (readable off-device): confirms which build loaded and
        // how many guest ghosts (MPEntity) this side sees — independent of combat or ghost presence.
        WO_LogHeartbeat(alive_count);
    }

    // HOST: broadcast time-of-day + weather to guests every ~3s (near-immediate on connect; the
    // guest only actually re-sets when off by >3 min, so the frequent send is cheap). render_tick_count
    // is per-frame @60Hz -> 180 ticks ~ 3s. WO_BroadcastTimeWeather self-gates to host+gameplay.
    if (ss.render_tick_count % 180 == 0)
        WO_BroadcastTimeWeather();
}

// HOST side (Step 1 of combat co-op): reconfigure the remote player's ghost so the
// host's hostile NPCs perceive and attack it. The ghost sits at the guest's synced
// position, so monsters chase/attack the guest's location; the guest sees them via
// NPC sync and can fight back (spike #5 hit reg). Damage TO the guest = Step 2.
function WO_COMBAT_COOP_ENABLED() : bool { return true; }

// Unconditional version+connectivity beacon. Logged ~2x/sec by both host and guest so the running
// build and the MPEntity-ghost count are visible off-device, regardless of combat/ghost state.
function WO_LogHeartbeat(npcAlive : int)
{
    var ghEnts : array<CEntity>;
    theGame.GetEntitiesByTag('MPEntity', ghEnts);
    Log("WO_HB V84 guest=" + WO_IS_GUEST() + " ghosts=" + ghEnts.Size() + " npc=" + npcAlive);
}

function WO_MakeGhostsAttackable()
{
    var ghosts : array<CEntity>;
    var i : int;
    var g : CActor;
    var cd : CCombatDataComponent;
    var ss : WO_SpikeState;
    var ghMax, ghCur, lostPct : float;
    var near : array<CActor>;
    var npc2 : CNewNPC;
    var j : int;
    var atkNear : bool;

    if (!WO_COMBAT_COOP_ENABLED())
        return;

    ss = theGame.WO_GetSpikeState();
    theGame.GetEntitiesByTag('MPEntity', ghosts);
    for (i = 0; i < ghosts.Size(); i += 1)
    {
        g = (CActor)ghosts[i];
        if (!g) continue;

        // One-time combat setup per ghost.
        if (!g.HasTag('wo_ghost_combatized'))
        {
            g.AddTag('wo_ghost_combatized');
            g.SetBaseAttitudeGroup(thePlayer.GetAttitudeGroup());   // same group as host Geralt -> monsters hostile
            // AIM_Immortal (NOT Invulnerable): the NPC's attacks LAND (damage clamped to keep HP>=1,
            // hit reactions play) so combat-AI treats the ghost as a real, hittable target. (Invulnerable
            // applied 0 damage; but the PRIMARY melee gate turned out to be gameplay-visibility + the
            // ticket pool, see below.) The ghost still can't die (HP floored at 1); the HP it loses on the
            // host is the future "damage to guest" signal (read it -> relay -> guest GainStat).
            g.SetImmortalityMode(AIM_Immortal, AIC_Default, true);
            g.SetCanPlayHitAnim(true);                              // visible reaction when hit
        }

        // PER CYCLE — gameplay visibility is THE melee gate. btTicket.ws:160 (ShouldAskForTicket) and
        // btTaskAttack.ws:57 (IsAvailable) BOTH refuse to attack a non-player target whose
        // GetGameplayVisibility() is false -> the NPC only circles (TICKET_Approach), never swings.
        // The base mod sets the ghost invisible at spawn AND on dismountHorse, so re-assert true every
        // cycle (cheap) rather than once, to survive those clobbers.
        g.SetGameplayVisibility(true);

        // DAMAGE-TO-GUEST (Step 2): the guard's melee animation plays but deals NO real damage to the
        // ghost — the base mod spawns the ghost with collisions OFF, so the swing's hit-trace finds no
        // body and the ghost's HP never drops (lost stays 0). So drive guest damage off the ATTACK EVENT
        // instead of the ghost's HP: if any host NPC within melee range of the ghost is mid-swing
        // (IsAttacking) and in combat, relay one damage tick to the guest. The guest applies it to its
        // real player, floored at 5% so it never dies. ~1 tick per ~1s cycle while you're being attacked.
        atkNear = false;
        near = GetActorsInRange(g, 3.5, 16);
        j = 0;
        while (j < near.Size())
        {
            npc2 = (CNewNPC)near[j];
            if (npc2 && (CActor)npc2 != g && npc2.IsAlive() && npc2.IsInCombat() && npc2.IsAttacking())
            {
                atkNear = true;
                break;
            }
            j += 1;
        }
        if (atkNear)
            WO_EnqueueExec("wo_take_damage(7)");

        // Also still measure real HP loss (covers any attacker that DOES land collision damage), then heal
        // the ghost back to full so it never slips into a low-HP finisher/defeat state.
        ghMax = g.GetStatMax(BCS_Vitality);
        ghCur = g.GetStat(BCS_Vitality);
        lostPct = 0.0;
        if (ghMax > 0.0)
        {
            lostPct = ((ghMax - ghCur) / ghMax) * 100.0;
            if (lostPct > 20.0) lostPct = 20.0;
            if (lostPct >= 2.0)
                WO_EnqueueExec("wo_take_damage(" + (int)lostPct + ")");
        }
        g.GainStat(BCS_Vitality, 100000.0);

        // THE TICKET POOL: an attacker must draw a 'TICKET_Melee' from its TARGET's CCombatDataComponent
        // before it may strike. Flood the pool (horseRiding.ws pattern: +400 tickets, importance 0.0) so any
        // attacker freely gets permission. NOTE (research): the ghost is a geralt_npc.w2ent with NO baked
        // combat AI, so it likely has NO CCombatDataComponent at all (cd==NULL) -> this block no-ops and the
        // pure-AI melee is blocked at the engine. The ghost_dbg HUD readout below tells us which world we're
        // in (CD=Y means the pool exists and this override is the fix; CD=n means we need a different path).
        // Clear the prior override before re-issuing so requests don't leak/stack.
        cd = (CCombatDataComponent)g.GetComponentByClassName('CCombatDataComponent');
        if (cd)
        {
            if (ss.ghost_tkt_active)
            {
                cd.TicketSourceClearRequest('TICKET_Melee',    ss.ghost_tkt_melee);
                cd.TicketSourceClearRequest('TICKET_Charge',   ss.ghost_tkt_charge);
                cd.TicketSourceClearRequest('TICKET_Special',  ss.ghost_tkt_special);
                cd.TicketSourceClearRequest('TICKET_Approach', ss.ghost_tkt_approach);
            }
            ss.ghost_tkt_melee    = cd.TicketSourceOverrideRequest('TICKET_Melee',    400, 0.0);
            ss.ghost_tkt_charge   = cd.TicketSourceOverrideRequest('TICKET_Charge',   400, 0.0);
            ss.ghost_tkt_special  = cd.TicketSourceOverrideRequest('TICKET_Special',  400, 0.0);
            ss.ghost_tkt_approach = cd.TicketSourceOverrideRequest('TICKET_Approach', 400, 0.0);
            ss.ghost_tkt_active = true;
            // Force an immediate re-grant so attacks can start this frame (combat.ws does this on its
            // block path; cheap to also do on the enable path).
            cd.ForceTicketImmediateImportanceUpdate('TICKET_Melee');
            ss.ghost_dbg = "CD=Y vis=" + g.GetGameplayVisibility() + " atk=" + cd.GetAttackersCount() + " atkNear=" + atkNear + " lost=" + (int)lostPct;
        }
        else
        {
            ss.ghost_dbg = "CD=n vis=" + g.GetGameplayVisibility() + " atkNear=" + atkNear + " lost=" + (int)lostPct;
        }

        // Also emit to scriptslog so the diagnostic is readable off-device (the in-game HUD is hard to
        // read). Runs ~1x/sec (this whole function is called every 60 render ticks).
        Log("WO_GHOST " + ss.ghost_dbg);
    }
}

// Scan nearby actors, hide vanilla on guest. Also sweeps for orphaned marionettes
// (wo_remote_npc entities with no matching live registry entry). Called from render timer.
function WO_DoGuestCleanup()
{
    var nearby : array<CActor>;
    var i, hidden : int;
    var a : CActor;
    var ss : WO_SpikeState;
    var rns : WO_RemoteNpcRegistry;
    var e : WO_RemoteNpcEntry;
    var tagEnts : array<CEntity>;
    var orphanActor : CActor;

    ss = theGame.WO_GetSpikeState();
    nearby = GetActorsInRange(thePlayer, 80.0, 100);
    ss.cleanup_last_scanned = nearby.Size();
    hidden = 0;

    for (i = 0; i < nearby.Size(); i += 1)
    {
        a = nearby[i];
        if (!a) continue;
        if (a == thePlayer) continue;
        if (a.HasTag('wo_remote_npc')) continue;
        if (a.HasTag('wo_spike_marionette')) continue;
        if (a.HasTag('wo_ghost_player')) continue;
        if (a.HasTag('wo_guest_hidden')) continue;

        a.AddTag('wo_guest_hidden');
        // SetHideInGame actually removes the rendered mesh (SetGameplayVisibility only
        // toggles gameplay flag, mesh stays visible). Belt-and-suspenders both.
        a.SetHideInGame(true);
        a.SetGameplayVisibility(false);
        a.SetImmortalityMode(AIM_Invulnerable, AIC_Default, true);
        a.EnableCollisions(false);
        a.EnableCharacterCollisions(false);
        if (a.GetMovingAgentComponent())
        {
            a.GetMovingAgentComponent().SetGameplayRelativeMoveSpeed(0);
        }
        a.SetTemporaryAttitudeGroup('friendly_to_player', AGP_Default);
        WO_StopAI(a);   // stop hidden NPC's AI (no point ticking wander/combat while invisible)
        hidden += 1;
    }
    ss.cleanup_total_hidden += hidden;

    // Fix 3: Orphan marionette GC. Destroy any wo_remote_npc entity whose actor handle is
    // no longer tracked in the remote NPC registry. This catches entities that were not
    // properly cleaned up on rapid test-cycle resets (fast jumps etc.).
    rns = theGame.WO_GetRemoteNpcState();
    theGame.GetEntitiesByTag('wo_remote_npc', tagEnts);
    for (i = 0; i < tagEnts.Size(); i += 1)
    {
        orphanActor = (CActor)tagEnts[i];
        if (!orphanActor) continue;
        e = WO_FindRemoteByActor(orphanActor);
        if (!e)
        {
            // No registry entry — this is a leaked marionette. Destroy it.
            orphanActor.Destroy();
        }
    }
}

// (cleanup folded into wo_npc_render60hz — see WO_DoGuestCleanup above)

// ---- Guest-side vanilla NPC cleanup ----
// On guest, suppress every vanilla NPC so we only see host's broadcasted NPCs (Dark Souls model).
@wrapMethod(CNewNPC)
function OnSpawned(spawnData : SEntitySpawnData)
{
    var isProtected : bool;
    wrappedMethod(spawnData);

    if (WO_IS_GUEST())
    {
        isProtected = this.HasTag('wo_remote_npc')
                   || this.HasTag('wo_spike_marionette')
                   || this.HasTag('wo_ghost_player');

        if (!isProtected)
        {
            // Vanilla NPC on guest: hide it + suppress AI + make untouchable
            this.AddTag('wo_guest_hidden');
            this.SetHideInGame(true);
            this.SetGameplayVisibility(false);
            this.SetImmortalityMode(AIM_Invulnerable, AIC_Default, true);
            this.EnableCollisions(false);
            this.EnableCharacterCollisions(false);
            if (this.GetMovingAgentComponent())
            {
                this.GetMovingAgentComponent().SetGameplayRelativeMoveSpeed(0);
            }
            this.SetTemporaryAttitudeGroup('friendly_to_player', AGP_Default);
        }
    }
}

// ---- Triggers ----
// Auto-start render timer on spawn.
function WO_NPC_SYNC_RENDER_ENABLED() : bool { return true; }

@wrapMethod(CR4Player)
function OnSpawned(spawnData : SEntitySpawnData)
{
    wrappedMethod(spawnData);
    thePlayer.RemoveTag('wo_timers_started');  // re-arm bootstrap each load
    WO_EnsureTimers();
    GetWitcherPlayer().DisplayHudMessage("WO: OnSpawned fired, timers ensured");
}

// Idempotent: start render + guest-cleanup timers. Safe to call repeatedly.
function WO_EnsureTimers()
{
    // Single timer — cleanup is folded into render60hz on guest.
    thePlayer.RemoveTimer('wo_npc_render60hz');
    thePlayer.AddTimer('wo_npc_render60hz', 0.016, true);
}

// =============================================================================
// Spike #5: Hit registration end-to-end
// =============================================================================
//
// Wire format payload of UPDATE_HIT packet:
//   "<targetHost> <npcId> <damage>|<targetHost> <npcId> <damage>|..."
//
// Flow:
//   GUEST (attacker): jump 4 trigger -> find nearest wo_remote_npc -> enqueue hit
//                     wo_get_pending_hits drains queue, emits Log("wo_hit <payload>")
//                     DLL -> UPDATE_HIT packet -> server (immediate broadcast)
//   HOST (owner):     receives UPDATE_HIT -> wo_apply_hit(attacker, payload)
//                     looks up actor by ID in WO_HostNpcRegistry, applies damage
//                     dead actor skipped by wo_get_npcs -> guest despawn via timeout

class WO_PendingHit
{
    public var targetHost : string;
    public var npcId : int;
    public var damage : int;
}

class WO_HitQueue
{
    public var hits : array<WO_PendingHit>;
}

@addField(CR4Game) public var wo_hit_queue : WO_HitQueue;

@addMethod(CR4Game)
public function WO_GetHitQueue() : WO_HitQueue
{
    if (!this.wo_hit_queue)
        this.wo_hit_queue = new WO_HitQueue in this;
    return this.wo_hit_queue;
}

function WO_EnqueueHit(targetHost : string, npcId : int, damage : int)
{
    var q : WO_HitQueue;
    var h : WO_PendingHit;
    q = theGame.WO_GetHitQueue();
    h = new WO_PendingHit in theGame;
    h.targetHost = targetHost;
    h.npcId = npcId;
    h.damage = damage;
    q.hits.PushBack(h);
}

// =============================================================================
// Verbatim exec relay — cross-player actions with TYPED args (e.g. item names)
// =============================================================================
// WitcherScript has no runtime string->name, BUT the engine's exec-arg binder DOES
// convert a string token to a `name` when invoking an exec function (that's how the
// console's `additem(itemName : name)` works). Our transport injects exec calls over the
// SAME debug-scripts channel. So: the sender builds a verbatim exec string like
// "wo_give_item('Drowner brain', 2)"; the DLL relays it; the receiver's DLL injects it
// as-is; the engine binds 'Drowner brain' -> name. No table, no switch, ANY item.
//
// Channel: own opcode UPDATE_EXEC (isolated from the combat hit channel — zero regression
// risk to kills). Sender queues codes; wo_get_pending_exec drains them; DLL throttle-polls
// it; receiver DLL self-echo-filters + guards "wo_" prefix, then injects each verbatim.

class WO_ExecQueue
{
    public var codes : array<string>;   // verbatim exec strings to broadcast
}

@addField(CR4Game) public var wo_exec_queue : WO_ExecQueue;

@addMethod(CR4Game)
public function WO_GetExecQueue() : WO_ExecQueue
{
    if (!this.wo_exec_queue)
        this.wo_exec_queue = new WO_ExecQueue in this;
    return this.wo_exec_queue;
}

function WO_EnqueueExec(code : string)
{
    var q : WO_ExecQueue;
    if (StrLen(code) == 0) return;
    q = theGame.WO_GetExecQueue();
    q.codes.PushBack(code);
}

// Convenience: queue a "give this item to all partners" action. NameToString(name)->string
// for the wire; the receiver's engine binds it back to a name via the exec param.
function WO_QueueGiveItem(itemName : name, qty : int)
{
    WO_EnqueueExec("wo_give_item('" + NameToString(itemName) + "', " + qty + ")");
}

// RECEIVER side: injected verbatim by the DLL. The engine binds the quoted token to `name`.
// Grants the item locally (this is the whole point of the string->name unlock).
exec function wo_give_item(itemName : name, qty : int)
{
    if (WO_GameBusy()) return;
    if (!IsNameValid(itemName)) return;   // guard like the built-in additem does

    thePlayer.inv.AddAnItem(itemName, qty);
    GetWitcherPlayer().DisplayHudMessage("WO: получено x" + qty + " (" + NameToString(itemName) + ")");
}

// ---- Time & weather sync (host -> guests), rides the exec relay (REDkit finding) ----
// HOST periodically broadcasts its time-of-day + weather; GUESTS apply it for a shared sky.
function WO_TIMEWEATHER_ENABLED() : bool { return true; }

function WO_BroadcastTimeWeather()
{
    var gt : GameTime;
    if (!WO_TIMEWEATHER_ENABLED() || WO_IS_GUEST() || WO_GameBusy()) return;
    gt = theGame.GetGameTime();
    // time as two ints (no string->name needed); weather as a name via the exec binder.
    WO_EnqueueExec("wo_set_time(" + GameTimeHours(gt) + ", " + GameTimeMinutes(gt) + ")");
    WO_EnqueueExec("wo_set_weather('" + NameToString(GetWeatherConditionName()) + "', 3.0)");
    GetWitcherPlayer().DisplayHudMessage("WO host: sent " + GameTimeHours(gt) + ":" + GameTimeMinutes(gt) + " " + NameToString(GetWeatherConditionName()));
}

// RECEIVER: match the host's clock (keep our own DAY, set hour/minute so the sky lines up).
// Only correct when off by >3 game-minutes (handles day-wrap) so we don't re-fire time events
// every tick; once aligned, both clocks advance together. callEvents=true refreshes the sky.
exec function wo_set_time(h : int, m : int)
{
    var gt : GameTime;
    var diff : int;
    if (WO_GameBusy()) return;
    gt = theGame.GetGameTime();
    diff = (h * 60 + m) - (GameTimeHours(gt) * 60 + GameTimeMinutes(gt));
    if (diff < 0) diff = -diff;
    if (diff > 720) diff = 1440 - diff;   // shortest arc around the 24h clock
    if (diff <= 3) return;                 // already in sync — don't re-set / re-fire events
    theGame.SetGameTime( GameTimeCreate( GameTimeDays(gt), h, m, 0 ), true );
    GetWitcherPlayer().DisplayHudMessage("WO recv: time " + h + ":" + m);
}

// RECEIVER: blend to the host's weather. Skip if already that condition (avoids re-triggering).
exec function wo_set_weather(w : name, blend : float)
{
    if (WO_GameBusy()) return;
    GetWitcherPlayer().DisplayHudMessage("WO recv: weather " + NameToString(w));
    if (GetWeatherConditionName() != w)
        RequestWeatherChangeTo( w, blend, false );
}

// RECEIVER: a host NPC dealt damage to THIS guest's ghost on the host; apply it to the real player.
// pct = % of the ghost's max vitality lost in the host's last cycle. Clamped so the guest never dies
// in co-op (floor at 5% of max) — death sync isn't built and dying here would be janky.
exec function wo_take_damage(pct : int)
{
    var p : CActor;
    var mx, cur, dmg, fl : float;
    if (WO_GameBusy()) return;
    if (pct <= 0) return;
    p = GetWitcherPlayer();
    if (!p) return;
    mx = p.GetStatMax(BCS_Vitality);
    if (mx <= 0.0) return;
    cur = p.GetStat(BCS_Vitality);
    dmg = (((float)pct) / 100.0) * mx;
    fl = mx * 0.05;
    if (cur - dmg < fl) dmg = cur - fl;   // never take HP below the floor -> never die in co-op
    if (dmg > 0.0) p.GainStat(BCS_Vitality, -dmg);
}

// Polled (throttled) by the DLL. Drains the exec queue. Always emits the bare "wo_exec"
// marker when empty so the DLL's ExecTagged never waits the full timeout.
exec function wo_get_pending_exec(playerId : string)
{
    var q : WO_ExecQueue;
    var i : int;
    var payload : string;

    q = theGame.WO_GetExecQueue();
    for (i = 0; i < q.codes.Size(); i += 1)
    {
        if (i > 0) payload += "|";
        payload += q.codes[i];
    }
    q.codes.Clear();

    if (StrLen(payload) > 0)
        Log("wo_exec " + payload);
    else
        Log("wo_exec");
}

// TEST trigger (host only): each PC jump queues a give of one item to partners, to prove
// the relay end-to-end (PC drop -> Deck inventory) before the real drop UI exists.
function WO_TEST_DROP() : bool { return false; }

// Polled by C++ DLL each tick. Drains queue. Always emits "wo_hit" tag (possibly empty payload).
exec function wo_get_pending_hits(playerId : string)
{
    var q : WO_HitQueue;
    var i : int;
    var payload : string;
    var h : WO_PendingHit;

    q = theGame.WO_GetHitQueue();
    for (i = 0; i < q.hits.Size(); i += 1)
    {
        h = q.hits[i];
        if (!h) continue;
        if (i > 0) payload += "|";
        payload += h.targetHost;
        payload += " ";
        payload += h.npcId;
        payload += " ";
        payload += h.damage;
    }
    q.hits.Clear();

    if (StrLen(payload) > 0)
        Log("wo_hit " + payload);
    else
        Log("wo_hit");  // empty marker so DLL doesn't time out
}

// Host side: applies damage to NPC owned by us (looked up by ID in WO_HostNpcRegistry).
exec function wo_apply_hit(attackerId : string, payload : string)
{
    var rem, chunk, tok : string;
    var npcId, damage : int;
    var targetHost : string;
    var reg : WO_HostNpcRegistry;
    var a : CActor;

    if (payload == "")
        return;

    // Don't process damage actions while paused / in menu / cutscene — creating and
    // running W3DamageAction then is unsafe and can pile up. Drop the hit (guest retries).
    if (WO_GameBusy())
        return;

    rem = payload;
    while (true)
    {
        if (StrSplitFirst(rem, "|", chunk, rem))
        {
            WO_ApplyHitChunk(attackerId, chunk);
        }
        else
        {
            if (StrLen(rem) > 0)
                WO_ApplyHitChunk(attackerId, rem);
            break;
        }
    }
}

// The guest's ghost on the host (the actor representing the remote attacker). Using it
// as the damage attacker makes NPCs aggro the GUEST (its ghost), not the host player.
function WO_GetGuestGhost() : CActor
{
    var ghosts : array<CEntity>;
    var i : int;
    var g : CActor;
    theGame.GetEntitiesByTag('MPEntity', ghosts);
    for (i = 0; i < ghosts.Size(); i += 1)
    {
        g = (CActor)ghosts[i];
        if (g) return g;   // single-guest: first ghost. (Multi-guest: match by id later.)
    }
    return NULL;
}

function WO_ApplyHitChunk(attackerId : string, chunk : string)
{
    var rem, tok : string;
    var npcId, damage : int;
    var targetHost : string;
    var reg : WO_HostNpcRegistry;
    var a, attackerEntity : CActor;
    var dmgAction : W3DamageAction;

    rem = chunk;
    if (!StrSplitFirst(rem, " ", targetHost, rem)) return;
    if (!StrSplitFirst(rem, " ", tok, rem)) return;
    npcId = StringToInt(tok, -1);
    if (npcId < 0) return;
    damage = StringToInt(rem, 0);

    // We are the host only for our own registered NPCs.
    // Other players' "wo_apply_hit" with their targetHost will fail lookup (not in our registry) -- silently skipped.
    reg = theGame.WO_GetHostNpcRegistry();
    if (npcId < 1 || npcId > reg.actors.Size()) return;

    a = reg.actors[npcId - 1];
    if (!a) return;
    if (!a.IsAlive()) return;

    // Drop immortality just before damage so it can die. (Otherwise SetImmortalityMode blocks it.)
    a.SetImmortalityMode(AIM_None, AIC_Default, true);

    // Attacker = the guest's ghost so the NPC aggros the guest, not the host.
    attackerEntity = WO_GetGuestGhost();
    if (!attackerEntity)
        attackerEntity = thePlayer;

    dmgAction = new W3DamageAction in theGame;
    dmgAction.Initialize(
        attackerEntity,             // attacker = guest ghost -> NPC aggros the guest
        a,                          // victim
        NULL,                       // cause
        attackerId,                 // source name
        EHRT_Heavy,                 // hit reaction
        CPS_AttackPower,            // power stat
        false,                      // is action ranged
        false,                      // is environment
        false,                      // is friendly fire
        true                        // can play hit anim
    );
    dmgAction.SetCanPlayHitParticle(true);
    dmgAction.AddDamage(theGame.params.DAMAGE_NAME_DIRECT, damage);
    theGame.damageMgr.ProcessAction(dmgAction);
    delete dmgAction;

    // Make the NPC actually fight back at the attacker (the guest's ghost): force it hostile to the
    // ghost, make it perceive it, and FORCE the ghost as its combat target. This is the shipped quest
    // pattern for "make NPC fight this actor" (quest_attitude.ws ForceTargetQuest: NoticeActor +
    // 'ForceTarget'), plus the reaction-data enter-combat pair (SetAttitude AIA_Hostile +
    // 'AI_RequestCombatEvaluation', aiStorage.ws NewTempHostileActor). ForceTarget bypasses the
    // IsDangerous/score filter so the ghost is locked as the target even if it scores low.
    if (attackerEntity && attackerEntity != thePlayer && a.IsAlive())
    {
        a.SetAttitude(attackerEntity, AIA_Hostile);
        if ((CNewNPC)a)
            ((CNewNPC)a).NoticeActor(attackerEntity);
        a.SignalGameplayEventParamObject('ForceTarget', attackerEntity);
        a.SignalGameplayEvent('AI_RequestCombatEvaluation');
    }

    // If that killed it, remember the id so wo_get_npcs broadcasts alive=0 once -> the
    // guest despawns its marionette immediately (instead of waiting the 5s stale timeout).
    if (!a.IsAlive())
        reg.killed.PushBack(npcId);
}

// Find nearest wo_remote_npc to player, enqueue hit on its (host, npcId).
function WO_DoHitNearestRemote(damage : int)
{
    var rns : WO_RemoteNpcRegistry;
    var i : int;
    var ppos, npos : Vector;
    var best : WO_RemoteNpcEntry;
    var bestDist, d : float;
    var rem, host, npcIdStr : string;
    var npcId : int;

    rns = theGame.WO_GetRemoteNpcState();
    ppos = thePlayer.GetWorldPosition();
    bestDist = 9999.0;

    for (i = 0; i < rns.entries.Size(); i += 1)
    {
        if (!rns.entries[i] || !rns.entries[i].actor) continue;
        npos = rns.entries[i].actor.GetWorldPosition();
        d = VecDistance(ppos, npos);
        if (d < bestDist)
        {
            bestDist = d;
            best = rns.entries[i];
        }
    }

    if (!best)
    {
        GetWitcherPlayer().DisplayHudMessage("WO_HIT: no remote NPC to hit");
        return;
    }

    // parse "host:npcId" key
    rem = best.key;
    if (!StrSplitFirst(rem, ":", host, npcIdStr)) return;
    npcId = StringToInt(npcIdStr, -1);
    if (npcId < 0) return;

    WO_EnqueueHit(host, npcId, damage);
    GetWitcherPlayer().DisplayHudMessage("WO_HIT: queued hit on " + host + ":" + npcId + " for " + damage);
}

// =============================================================================
// Spike #1-3 jump triggers (unchanged from earlier)
// =============================================================================

// LOCAL APPEARANCE TEST (PC, no Deck/network needed): when on, each jump spawns the
// next NPC type from the test list in front of the player, going through the real
// appearance->template->spawn path. Read scriptslog.txt for "WO_NPC ... loaded OK/FAILED".
// Turn OFF for normal co-op.
function WO_TEST_LOCAL_NPCS() : bool { return false; }

function WO_TestAppearanceAt(index : int) : string
{
    // One representative appearance per category we mapped.
    switch (index)
    {
        case 0: return "drowner_01";
        case 1: return "nml_baron_guard_lvl1_03";
        case 2: return "nml_villager_crowd_06";
        case 3: return "village_woman_04";
        case 4: return "citizen_ma_14";
        case 5: return "citizen_old_07";
        case 6: return "skellige_boy_04";
        case 7: return "skellige_villager_woman_06";
        case 8: return "cat_01";
        case 9: return "dog_02";
        case 10: return "pig_02";
        case 11: return "horse_background_04";
    }
    return "";
}

@wrapMethod(CExplorationStateJump)
function StateWantsToEnter() : bool
{
    var ret : bool;
    var ss : WO_SpikeState;
    var app : string;
    var fwd, pos : Vector;
    var e : WO_RemoteNpcEntry;
    ret = wrappedMethod();
    WO_EnsureTimers();

    // TEST: host jump -> send one item to partners (proves the verbatim exec relay).
    if (ret && !WO_IS_GUEST() && WO_TEST_DROP())
    {
        WO_QueueGiveItem('Drowner brain', 1);
        GetWitcherPlayer().DisplayHudMessage("WO: queued give 'Drowner brain' to partners");
    }

    if (ret && WO_TEST_LOCAL_NPCS())
    {
        ss = theGame.WO_GetSpikeState();
        app = WO_TestAppearanceAt(ss.cleanup_tick_count);   // reuse counter as test index
        if (app != "")
        {
            fwd = thePlayer.GetWorldForward();
            pos = thePlayer.GetWorldPosition() + fwd * 4.0;
            e = WO_CreateRemoteMarionette("test:" + ss.cleanup_tick_count, pos, app, "", "-");
            GetWitcherPlayer().DisplayHudMessage("TEST spawn: " + app);
            ss.cleanup_tick_count += 1;
        }
        else
        {
            GetWitcherPlayer().DisplayHudMessage("TEST: all types spawned");
        }
    }
    return ret;
}
