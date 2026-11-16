# Investigation 17 — Trap hit reliability

## Status

Schema 14 fixes a confirmed state defect from Task 08 and offers two independently selectable fire effects. Both build cleanly, the Papyrus sources compile, all eight offline suites pass, and both are deployed. **Neither experiment has been run in game.**

## 1. Task 08 run analysis (16 November 2026, 15:12)

Preserved as `task09-preservation/schema13-fire-trap-20261116-1512-*.log`.

**Verified from the logs:**

- Three Read Or Take world READs were denied (`pending_acquisition`), rejected by Papyrus (`reject-removed`, matched acknowledgements), and each produced one `defense_effect stage=triggered` and one `cast_attempted timing=immediate` with `source_3d=TRUE`. The visible fire in the clips matches these casts.
- **No** `hit_confirmed` or `hit_not_observed` row followed any cast.
- A later chest Take was `triggered` with `container=TRUE`, then immediately `cancelled reason=queue_full`, although nothing was queued.
- The Papyrus log contains repeated runtime errors in the new code: `Cannot cast from None to Form[]` (at `OnPlayerLoadGame` and at `UT_EnsureDefenseState`'s `== None` test) and `Cannot create an array into a non-array variable` (array allocation). This happened on the user's existing save.

**Root causes:**

1. **State defect (confirmed by the errors).** The script-level arrays added in Task 08 were unusable on the existing save, so allocation, the queue and marker cleanup all failed:
   - every deferral reported `queue_full`;
   - the casting markers `FF000F0A`, `FF000F05` and `FF000F0B` were never deleted;
   - `OnUpdate` aborted at its first array access, so `hit_not_observed` was never logged.

   The absence of a hit row therefore does not by itself prove a miss.
2. **Aim (strongly supported).** `MoveTo(player, …)` copies the target's rotation by default, so the marker faced the same way as the player. Trap-style casts from non-actors fire along the caster's facing, which would send the bolt away from the player. That fits "visible fire, no hit". It remains a hypothesis until the instrumented run below.

## 2. Changes (schema 14 and the new PEX)

- **Defense state** now uses newly named scalar slots: four deferred slots and four marker slots, accessed through small helpers. No script arrays remain. The old array variables no longer exist in the script, so the save's stale entries are only dropped. The queue, the 30 s expiry, the location, effect-disabled and load cancellations, and the non-blocking poll keep their Task 08 semantics.
- **Experiment A, `UntamedTomes.FireTrap` (effect `fire`):**
  - It still uses `TrapFirebolt01` (`Skyrim.esm 0007E56D`, 15 trap fire damage).
  - The marker now sits 220 units ahead at chest height (+90) and is **turned to face the player** with `SetAngle(0, 0, heading + 180)`, then `Cast(marker, player)`.
  - The `cast_attempted` row logs marker and player XYZ, marker angles, player heading, distance, `marker_3d`, cell, interior, health before, and the menu snapshot.
- **Experiment B, `UntamedTomes.FireBurstTrap` (effect `fire_burst`):**
  - It uses vanilla `TrapDweFlamePillarExplosion01` (`Skyrim.esm 000E605E`): 8 damage plus the trap fire enchantment `000E605F`, radius 50, force 0.
  - The explosion is placed with `PlaceAtMe` **at the player's position**, from a temporary XMarker 40 units up. There is no projectile, so travel, aim and walls cannot cause a miss, and force 0 means no knockback.
  - The record is from a Dwemer flame-pillar trap (a burst, not a bolt), so the two effects should look different.
  - Damage comes from the explosion and its enchantment, which go through the engine's damage and resistance handling, not `DamageActorValue`.
- **Hit verification (both effects):**
  - Activation records health and the expected sources: the spell (A), or the explosion and its enchantment (B).
  - `OnHit` with a matching `akSource` logs `hit_confirmed` with aggressor, projectile, blocked state, delay and `health_delta`.
  - Any other hit during the window logs `hit_other`.
  - After 3 s without a match, the poll logs `hit_not_observed` with `health_delta`, which shows whether damage landed without an `OnHit`.
- **Selection** (`src/DefenseConfig.h`): `FireTrap` gives `fire`, `FireBurstTrap` gives `fire_burst`, and both together give a **conflict**, logged as `conflict=true`, under which the defense is disabled. `DebugTrap` alone gives `notify`. Schema 14 logs `fire_burst_trap=` and `conflict=` on `debug_trap_config`.

Unchanged: acquisition eligibility, unified read enforcement, DEST coexistence, item removal, the existing markers and menu deferral.

## Runtime results: Experiment A (16 November 2026, 15:58)

Preserved as `task10-preservation/schema14-session-20261116-1600-*.log` in the native checkout. The setup was `defense_effect=fire conflict=false`, three Read Or Take world READs in one interior, all denied (`pending_acquisition`) and rejected (`reject-removed`). **Verified by the native log:**

| ID | Tome | Marker Z angle / player heading | Distance | Result |
| --- | --- | --- | --- | --- |
| 1 | `000A26FD` | 483.1 / 303.1 (+180) | 237.7 | `hit_not_observed` after 3.1 s, health Δ 0 |
| 2 | `000A2705` | 410.6 / 244.8 | 193.0 | **`hit_confirmed`**: source `TrapFirebolt01`, `aggressor=None`, not blocked, 1.48 s after the cast, **health Δ −15.5** |
| 3 | `000A26F9` | 424.8 / 244.8 (+180) | 237.1 | `hit_not_observed` after 3.2 s, health Δ +2.2 (regeneration) |

- **The scalar state works on the existing save.** The Papyrus log has no `UT_PlayerMonitor` errors, every activation reached a verdict, and no queue or cleanup faults occurred.
- **Attribution:** the one hit reports `aggressor=None`. The player is not the attacker, and the damage matches the record's 15.
- **Reliability: 1 of 3 interior casts hit.** The facing correction did not make the projectile dependable. Cast 2's marker angle is not heading+180, unlike casts 1 and 3, and the cause of that difference was not recorded.
- **Latency:** about 1.25 s from `triggered` to `cast_attempted` (Papyrus marker placement), and about 2.9 s from the denied read to the cast.
- **Not yet run:** an open exterior, Experiment B, chest deferral and load cancellation.

## 3. Test procedure

Markers in `Documents\My Games\Skyrim Special Edition\SKSE\`: `UntamedTomes.EnforceTomeReads`, plus **exactly one** of `UntamedTomes.FireTrap` (A) or `UntamedTomes.FireBurstTrap` (B). Restart between A and B. Startup must show `observer_load schema=14` and `debug_trap_config … defense_effect=fire|fire_burst conflict=false`. Use base Magicka 100, threshold 150, and a disposable save. A **new** save is preferable, but the scalar state also runs on the existing one.

| # | Location | Action | Record |
| --- | --- | --- | --- |
| 1 | Open exterior | World TAKE of an unlearned tome | Visible effect, health before and after, `hit_confirmed` or `hit_not_observed`, and `health_delta` |
| 2 | Tight dungeon corridor, facing a wall | World TAKE | As 1, plus whether the bolt hit the wall |
| 3 | Dungeon chest | TAKE, stay in the menu, then close it | `deferred`, then one cast after closing, plus the hit row |
| 4 | Either | Read Or Take world READ | Read denied, one effect, hit row |
| 5 | Either | Reload while a chest effect is pending | `cancelled reason=load` |

For A, compare `marker_angle` with `player_heading` (the expected difference is 180°). If A still logs `hit_not_observed` with a facing marker, aim-by-facing is ruled out, and the cast method is the remaining suspect.

## 4. Comparison (expectations; fill in from the run)

| Criterion | A: facing-corrected TrapFirebolt01 | B: flame-pillar burst at the player |
| --- | --- | --- |
| Reliability of affecting the player | Depends on facing, travel and collision. Unproven. | Placed at the player with radius 50: no travel. Expected to hit. |
| Visual credibility | A bolt from "the book's direction". Readable as a magical retaliation. | A burst of flame around the player. Reads as the book erupting. |
| Damage attribution | Caster is a non-actor XMarker. Player is not the aggressor. | Placed from an XMarker, with no actor owner expected. To verify via `aggressor=`. |
| Near walls | A wall within 220 units may block the bolt | Unaffected (no travel) |
| After container menus close | The same deferral; fires about 0.25 s after closing | The same |

## 5. Recommendation

Make **B (direct discharge) the baseline for acquisition traps** if the run confirms `hit_confirmed` or a negative `health_delta` in both the open and tight locations. It removes aim, travel and walls from the reliability question. Keep A as a presentation variant for later, once a cast origin that is reliably clear of geometry is designed. Do not combine them until each has been verified separately.

## 6. Limitations

- Damage is fixed by the vanilla records: A does 15, B does 8 plus its enchantment, to be measured.
- `OnHit` attribution uses a single awaiting ID, so a second activation within 3 s overrides it.
- B's explosion owner and any crime or alarm behaviour need checking in the run.
- Stale `UT_Defense*` array entries from the Task 08 save may produce one-time "variable … no longer exists" load warnings. These are harmless.
