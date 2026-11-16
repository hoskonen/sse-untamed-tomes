# Investigation 16 — Fire trap gameplay lab

## Status

Schema 13 adds a debug-only fire defense on rejected acquisitions. It builds cleanly, the Papyrus sources compile, all eight offline suites pass, and both are deployed. **No in-game test of the fire trap has been run.** Every scenario below is still an expectation.

## 1. Baseline (16 November 2026, 13:16 launch)

Preserved in the native checkout as `task08-preservation/*-20261116-1316*`, with `SHA256SUMS.txt`.

- **Verified (native, DEST and SKSE logs):**
  - `skse64.log` loaded `DontEatSpellTomes.dll` 1.2.3 and `UntamedTomesSKSE.dll`.
  - `DontEatSpellTomes.log` reported `Installed hook for reading spell tome`.
  - Our log showed `observer_load schema=12`, `tome_read_probe_compat dest_loaded=true read_body=dest_window_patched`, `tome_read_probe_ready mode=enforce_tome_reads`, `ledger_ready … enforcement=unified` and `debug_trap_config enabled=true`.
  - **Unified enforcement installs alongside DEST 1.2.3 on 1.7.104.**
- **Not evidenced:** that launch contains twelve session markers but no `ledger_add`, read rows or `debug_trap_triggered`. None of today's four Papyrus logs (10:57, 11:10, 11:59, 13:16) contains an `[UntamedTomes]` row. The debug trap and DESTified study with the mod enabled have **not** been exercised in a logged session.
- **DESTified warnings:** on every load, `DEST_ISL_PlayerSpellLearningScript` reports 12 properties (`StudyPercentage`, `TimedStudy`, `EndlessStudyMessage`, `PlayerRef`, …) as "cannot be initialized because the script no longer contains that property". DESTified's ESP defines properties that the winning Script Fixes PEX no longer declares. These are initialization warnings and do not block testing. Left unchanged.

## 2. Fire effect

`Skyrim.esm` SPEL scan (record data, read-only):

| Candidate | FormID | Delivery | Effect / magnitude | Decision |
| --- | --- | --- | --- | --- |
| Firebolt (player spell) | `00012FD0` | aimed | `00012F03` 25 plus a stagger effect | Rejected: player-oriented, higher damage |
| FireboltStormNoDamage | `000E9AC6` | aimed | `000E9AC7` 5, area 5 | Rejected: Alduin firestorm meteor, not a bolt |
| **TrapFirebolt01** | **`0007E56D`** | **aimed, fire-and-forget** | **`0010192A` 15** | **Chosen:** vanilla trap record built for non-actor casters; lowest trap firebolt |
| TrapFirebolt02–06 | `0007E580`–`0007E584` | aimed | 25–45 | Reserved for later tuning |

Casting:

- A temporary `XMarker` (`Skyrim.esm 0000003B`) is placed 220 units in front of the player and 120 units up, using the player's heading.
- It runs `TrapFirebolt01.Cast(marker, player)` and is deleted about 3 s later.
- The player is never the caster. Neither record is edited, and no ESP change is made.
- **Unverified:** whether `Spell.Cast` from an XMarker, a reference without visible 3D, launches a visible projectile. The `cast_attempted` row logs `source_3d`. If no hit follows, a later `hit_not_observed` row records that. The planned fallback, not built, is to cast from a visible reference or to use an impact/explosion record.

## 3. Trigger, timing and cancellation

Implementation (`UT_PlayerMonitor.psc`, "Defensive effects" section):

- **Trigger:** `UT_TriggerDefense`, called once per `OnItemAdded` tome event with outcome `reject-removed` or `reject-skipped-empty-inventory`, after the unchanged decision, removal and acknowledgement. Eligible and exempt outcomes never call it, and no eligibility is recomputed.
- **Effect selection:** the native `UT_GetDefenseEffect` reads markers at plugin load:
  - `UntamedTomes.FireTrap` gives `fire`;
  - `UntamedTomes.DebugTrap` alone gives `notify` (the Task 07 notification and camera shake);
  - neither gives `none`.

  `src/DefenseConfig.h` and `tests/defense_config.cpp` cover the selection.
- **Separation:** `UT_ActivateDefenseEffect(id, tome, effect, timing)` dispatches to `UT_DefenseFire` or `UT_DefenseNotify`. A frost, rune or guardian effect would add one branch and one function. There is no framework or MCM.
- **Timing:**
  - When `Utility.IsInMenuMode()` is false at decision time, the effect fires immediately.
  - Otherwise it goes into one of four fixed slots. A non-blocking `RegisterForSingleUpdate(0.25)` poll fires it once no menu is open, re-checking state each time rather than relying on a fixed delay.
  - Menus are never closed by the mod.
- **Cancellation:** each is logged as `stage=cancelled reason=`.
  - `expired`: more than 30 real seconds after queueing.
  - `location_changed`: the player's parent cell differs from the cell at queueing.
  - `effect_disabled`.
  - `load`: `OnPlayerLoadGame` cancels every pending slot and deletes leftover casting markers.
  - `queue_full`: more than four deferred effects at once.
  - Pending state is never fired after a load.

## 4. Diagnostics

The native row is `event=defense_effect stage=<stage> id=<n> session tome detail…`, with these stages:

- `triggered`: outcome, effect, count, and the InventoryMenu, ContainerMenu and BarterMenu snapshot.
- `deferred`: slot and expiry.
- `activated` (notify) or `cast_attempted` (fire): timing (`immediate` or `deferred age_s=`), spell, source marker, `source_3d`, target, and the menu snapshot.
- `hit_confirmed`: from the player alias `OnHit` with `akSource == TrapFirebolt01`, plus aggressor, projectile, blocked state and delay.
- `hit_not_observed`: no hit within 3 s of the cast.
- `cancelled`: with its reason.

The acquisition ID is a Papyrus counter. Correlate it with `ledger_add`, `ledger_ack` and the Papyrus pickup rows by tome and time. A cast attempt is never reported as a hit.

## 5. In-game test procedure (not run)

Markers in `Documents\My Games\Skyrim Special Edition\SKSE\`: `UntamedTomes.EnforceTomeReads` and `UntamedTomes.FireTrap`. `DebugTrap` may stay. Use DEST 1.2.3, DESTified and Script Fixes, Read Or Take on, base Magicka 100, a dungeon, debug logging, and a disposable save. Startup must show `observer_load schema=13` and `debug_trap_config … defense_effect=fire`.

| Scenario | Action | Expected | Observed |
| --- | --- | --- | --- |
| F1 | Threshold 150. World TAKE of an unlearned tome. | One `triggered` then `cast_attempted timing=immediate`. A visible firebolt from in front of the player, about 15 damage, `hit_confirmed`. Tome removed. | Not run |
| F2 | Chest TAKE, staying in the menu several seconds | `triggered` with `container=TRUE`, then `deferred`. After closing the menu, one `cast_attempted timing=deferred age_s=…`. | Not run |
| F3 | Read Or Take world READ | `tome_read_decision deny pending_acquisition`, no ISL dialog, then one immediate fire trap | Not run |
| F4 | Threshold at or below 100. World TAKE. | `accept-eligible`, no `defense_effect` rows | Not run |
| F5 | Eligible tome, inventory READ | Forward, ISL study dialog opens, no defense rows | Not run |
| F6 | Several rejected Takes quickly in one chest | One `triggered` per acquisition, each deferred, one cast each after closing. No duplicates. At most four queued; more give `queue_full`. | Not run |
| F7 | Chest TAKE, then save and reload while still in the menu, or reload right after | `cancelled reason=load`, no fire after the load | Not run |
| F8 | Chest TAKE, then wait more than 30 s in the menu | `cancelled reason=expired` | Not run |

For each scenario, record whether the projectile was visible, the health change, any crime or hostility, and the tome count.

## 6. Expected timing differences (to verify)

- **World pickup and Read Or Take READ:** no menu is open when Papyrus decides 0.6–1.4 s after the pickup, so the trap fires about 1 s after the pickup. Earlier logs consistently had `menuMode=False` at decision time.
- **Chest Take:** `OnItemAdded` runs while ContainerMenu is open (`menuMode=TRUE container=TRUE` in every logged chest Take). The trap is deferred, and fires roughly 0.25 s after the player closes the menu. Whether `OnUpdate` keeps polling during the paused menu or resumes on close is unverified. Either way the state check holds the effect until no menu is open.

## 7. Known limitations

- Debug-only and marker-selected. Damage is fixed by the vanilla record (15). A trap could still kill a near-dead character.
- XMarker 3D and projectile visibility are unverified, as is the origin (220 units ahead, 120 up) in tight interiors, where the bolt may hit a wall.
- `hit_confirmed` attribution uses a single awaiting ID. Overlapping casts within 3 s are attributed to the latest.
- Deferred slots are script variables. Variables added by this change start as `None` in older saves and are allocated on first use.
- The tome is still destroyed by the existing rejection. Item preservation is out of scope.

## 8. Recommendation for the next effect experiment

Run F1–F8 first. If the XMarker cast is not visible, change only the casting source before trying another effect. Then try **frost**, using `TrapFrostbolt`-style trap records with the same source and lifecycle. It reuses everything above and tests whether a non-damage effect (slow) reads as a defense. Rune and guardian effects need persistent placement and cleanup, and should come after the timing model is confirmed in game.
