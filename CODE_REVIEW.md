# Code Review & Optimization — 2026-05-30

Review of the co-op spike code (C++ DLL, Java server, WitcherScript) with focus on
the user-reported ~300-800ms latency. Optimizations applied are marked ✅ DONE.

---

## 🔴 Critical latency bug (FIXED ✅)

**`wo_get_npcs` did not always emit a tagged reply.**

The DLL's `ExecTagged("wo_get_npcs", "wo_npc", ...)` blocks until it sees a line
starting with `wo_npc`, or until timeout. The WS function only `Log`-ed when it had
NPCs to send:
- On **guest**: `if (WO_IS_GUEST()) return;` — never logged → **every cycle waited the
  full 3000ms timeout**.
- On **host with no nearby NPCs**: also silent → same full-timeout stall.

So on the guest, *every poll cycle* burned ~3 seconds waiting for a reply that never
came. This was very likely the dominant cause of the perceived lag.

**Fix:** `wo_get_npcs` now always ends with a `Log` — `"wo_npc <payload>"` when there
are NPCs, bare `"wo_npc"` (empty marker) otherwise. The DLL treats the bare tag as
"empty, nothing to send". Same pattern `wo_get_pending_hits` already used.

> **Rule:** every WS getter polled via `ExecTagged` MUST always `Log` its tag, even
> when empty. A silent path = a full-timeout stall every cycle.

---

## 🟠 Poll loop did 5 sequential round-trips per cycle (FIXED ✅)

`PollPoseThread` (connected branch) ran five blocking `ExecTagged` round-trips back to
back, each gated by W3's debug-script processing + Wine overhead:

| Call | Purpose | Verdict |
|---|---|---|
| `wo_get` | player position/state | keep — every cycle |
| `wo_get2` | appearance / CPC armor | **throttled** — every 30th cycle |
| `wo_get3` | gwent multiplayer | **removed** — gwent is disabled on both sides (dead code) |
| `wo_get_npcs` | NPC sync | keep — every cycle |
| `wo_get_pending_hits` | hit queue | keep — every cycle |

**Fix:** removed `wo_get3` entirely, throttled `wo_get2` to every 30 cycles (appearance
changes only on armor swap — sub-second staleness is invisible). Steady-state cost
dropped from **5 → 3 round-trips per cycle (~40% fewer)**.

Also refactored the duplicated "exec → strip tag → BuildPacket → send" blocks into two
local lambdas (`pushHalves`, `pushPayload`) — ~140 lines → ~50, far easier to maintain.

Timeout lowered **3000ms → 1500ms**: caps worst-case hitch if a reply is ever dropped,
still generous for Wine's batched replies.

---

## 🟠 Server broadcast floor (FIXED ✅)

`broadcastLoop` slept **100ms** between broadcasts → up to 100ms host→guest staleness
(an update arriving just after a tick waits a full tick). Lowered to **50ms (20Hz)**.
Guest interpolates at 60Hz so smoothness is unaffected; targets are just fresher.
Bandwidth for 2 clients is trivial.

---

## 🟡 Known issues NOT yet fixed (tech debt)

### Host NPC registry grows unbounded
`WO_HostNpcRegistry.actors` only ever grows: every distinct NPC the host encounters
gets a permanent slot, and `WO_AssignNpcId` does a linear scan of the whole array for
every NPC every cycle (O(n) per NPC → O(30·n) per cycle). Over a long session traveling
the map, `n` reaches thousands → slow scan + memory leak (dead actor handles retained).

Not urgent for a test session (grows only on *new* NPC encounters), but needs a bounded
scheme before any real play:
- Reuse `NULL`/dead slots in `WO_AssignNpcId`, or
- Key by the actor's own stable handle/tag instead of an array index, or
- Periodic GC that nulls dead-actor slots (IDs stay stable; freed slots recycled).

### All remote NPCs render as drowners
`WO_CreateRemoteMarionette` hardcodes the drowner template. Host's guards/wolves/etc.
all appear as drowners on the guest. Needs NPC **type** in the `UPDATE_NPC` payload
(append a template/appearance id per NPC) and a template lookup on the guest.

### Guest NPC hide reliability (in progress)
`SetGameplayVisibility(false)` froze NPCs but did NOT hide the mesh. Switched to
`SetHideInGame(true, 'wo_guest')` (untested — verifying tomorrow). If that also fails,
fall back to `Destroy()` (acceptable in Dark-Souls model — guest discards own world).

### No request pipelining
`DebugExecClient` is single-slot request/reply (one outstanding request). The 3 per-cycle
round-trips are strictly sequential. Pipelining (send all, collect all) would cut latency
further but needs protocol work — deferred (risky).

### Debug cruft in hot path
`PollPoseThread` still has `LogStep`/`iterLog` diagnostic calls and a 3-second file-write
tick. Harmless in steady state (the `iterLog<5` guards stop firing after 5 iterations) but
should be gated behind a compile-time `WO_DEBUG` flag for a clean production build.

### `wo_get3` / `pushPlayer3` / UPDATE3 receive path now dead
Removed from the send side but the WS `wo_get3`, DLL `pushPlayer3`, and UPDATE3 receive
handler remain as unused code. Harmless; clean up when removing gwent fully.

---

## 🟢 Things that are good

- **Wire format** (tab-separated, cm-as-int coords) is simple, debuggable, robust.
- **One-shot TCP** (`SendOneShotExec`) was a clean Wine fallback; folding the player
  sync back onto the real `DebugExecClient` (now CRITICAL_SECTION-based) was the right call.
- **Always-emit-empty-marker** pattern (now applied to both NPC and hits) is the correct
  contract for a request/reply poll over a tagged log stream.
- **Guest 60Hz interpolation** decouples render smoothness from network rate — why 20Hz
  server broadcast looks fine.

---

## Net effect of this pass

- Removed a per-cycle **full-timeout stall** on the guest (the big one).
- **5 → 3** exec round-trips per cycle.
- Server staleness **100ms → 50ms**.
- ~90 lines of duplicated C++ collapsed into 2 lambdas.

Expected: substantially snappier sync, especially on the guest. Verify with tomorrow's
two-device test.
