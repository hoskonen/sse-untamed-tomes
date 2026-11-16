# Investigation 14 — Controlled spell-tome read enforcement

## Status

Schema 10 adds two opt-in, mutually exclusive denial modes to the existing `TESObjectBOOK::Read` entry detour. Papyrus stays the only eligibility authority. Native code refuses a teaching read only when Papyrus **has not decided** the tome's acquisition, or when the read comes from a container's own list, where no acquisition exists for Papyrus to decide.

The build compiles without warnings, and all offline suites pass. **No Skyrim runtime test of schema 10 has been run.** Every runtime case below is pending, and no runtime success is claimed.

## Evidence for the two policies

- **Pending acquisition** (Inv. 13 §13, 15 November 2026, 15:27:24):
  - A Read Or Take world READ of Firebolt logged `ledger_add` 1 ms before `Read`, on the same worker thread, then `tome_read_ledger pending=1 would_gate=1 gate_reason=pending_acquisition`.
  - The forwarded read taught the spell. Papyrus acknowledged 919 ms later with `reject-skipped-empty-inventory`. This is the bypass the policy targets.
  - Inventory reads with nothing pending logged `would_gate=0`. Six additions and six matched acknowledgements, with no anomalies.
- **External container** (15:44 launch, preserved as `task06-preservation/schema9-container-read-observation-20261115-1544-*.log` in the native checkout):
  - At 15:45:41 a SkyUI equip-mode READ from a chest's take tab ran on the main thread (16356). It logged caller `SkyrimSE.exe` RVA `913833` (the static prediction from Inv. 13 §1), `container_menu=1 container_side=other classification=external_container`, and `pending=0 would_gate=1 gate_reason=container_side_without_acquisition`.
  - The original returned true and `known_before=0` became `known_after=1`.
  - The Papyrus log of that launch has no pickup row, and the native log has no player-inbound change. The spell was taught without any acquisition.
- **Static basis** (Inv. 13 §1): `Read` teaches through `Actor::AddSpell` and returns true only for a newly added spell. Every caller removes the tome only when `Read` returns true. Read Or Take skips its `RemoveItem` on false (Inv. 12). The container handler at `91382E` skips its container `RemoveItem` on false. Returning false without calling the original therefore teaches nothing and consumes nothing in the observed callers.

## Implementation

Native checkout, no new hook:

| File | Change |
| --- | --- |
| `src/ReadEnforcement.h` | New. Pure `DecideEnforcement(EnforcementEvidence)`. Its inputs are the policy, reader, spell-tome validity, the ledger count after expiry (`-1` when unavailable) and the classifier result. It has no eligibility input. |
| `src/ProbeModeSelection.h` | New. Pure marker-to-mode selection, extracted from `InstallReadProbe` so the no-marker and conflict behaviour can be tested. It also defines `UsesEntryHook`, `UsesLedger`, `LogsReadContext` and the mode names, which are unchanged for the existing modes. |
| `src/main.cpp` | Two markers. `enforcementPolicy` is set before the detour is enabled. `LogLedgerRead` returns the snapshot it logged, and the decision reuses it, with expiry applied first. One enforcement step sits after the classifier and ledger rows. `LogEnforcementDecision` writes `tome_read_decision`. `InstallReadProbe` uses `SelectProbeMode`. `schema=10`. |
| `tests/read_enforcement.cpp` | New. Both policies, ledger lifecycle compositions, concurrency and mode selection. |

Papyrus and the ESP are unchanged from Task 05B. The acknowledgement native stays registered in every mode, and both new modes keep the ledger lifecycle.

### Markers

All markers are empty files in `%USERPROFILE%\Documents\My Games\Skyrim Special Edition\SKSE\`. There must be **exactly one**: a second marker logs `conflicting_probe_modes` and installs nothing, and no marker installs no read hook.

| Marker | Mode | Behaviour |
| --- | --- | --- |
| `UntamedTomes.DenyPendingAcquisition` | `deny_pending_acquisition` | Ledger, classifier rows, pending denial |
| `UntamedTomes.DenyContainerRead` | `deny_container_read` | Ledger, classifier rows, container-side denial |
| `UntamedTomes.ObserveLedger` | `observe_ledger` | Unchanged schema 9 observation; forwards every read |
| `UntamedTomes.DenyReadOrTakeWorld` | `deny_read_or_take_world` | Unchanged schema 8 denial |
| `ClassifyRead`, `TraceReadEntry`, `TraceRead`, `DenyFirebolt` | earlier probes | Unchanged |

The existing 1.7.104 gate, `Read` relocation and body hash, call-site byte checks and competing-module refusal apply to every mode.

### Decision table

The decision is evaluated only for spell-teaching books, which are the reads that produce `tome_read_enter`. Ordinary and skill books are forwarded without rows, as before.

| Order | Condition | Decision | Reason |
| --- | --- | --- | --- |
| 1 | No enforcement mode selected | forward | `experiment_disabled` (no row is written outside enforcement modes) |
| 2 | Reader unknown, or not the player | forward | `reader_unavailable`, `non_player_reader` |
| 3 | Teaching flag without a resolved spell | forward | `not_spell_tome` |
| 4 (pending mode) | Ledger not consulted | forward | `ledger_unavailable` |
| 4 (pending mode) | `pending > 0` after expiry | **deny** | `pending_acquisition` |
| 4 (pending mode) | `pending == 0` | forward | `no_pending_acquisition`. This is *not* evidence of acceptance. |
| 4 (container mode) | Classifier `external_container`, reason `container_external_side`, confidence `tentative` | **deny** | `container_side_without_acquisition` |
| 4 (container mode) | Classifier `player_inventory` (InventoryMenu or the player side of a ContainerMenu) | forward | `player_side_context` |
| 4 (container mode) | Anything else: side unavailable, several menus, worker thread, no menu | forward | `unknown_context` |
| any | Exception while gathering evidence | forward | `evidence_unavailable` |

The suggested reason `accepted_inventory` is deliberately not used for enforcement decisions. The ledger only shows that nothing awaits a decision. The observation row `tome_read_ledger` keeps its schema 9 `gate_reason` values. Thread identity, caller module and caller RVA are never decision inputs. Each policy acts only on its own evidence: the pending mode does not deny container-side reads, and the container mode does not deny pending inventory reads.

### Log rows

For every player spell-tome read in an enforcement mode, rows appear in this order. All share the same `read` ID.

1. `tome_read_enter`
2. `tome_read_observed` (classifier)
3. `tome_read_ledger` (pending count, oldest age, `would_gate`)
4. `tome_read_decision`, with `mode`, `policy`, session, thread, main thread, book, spell, reader, classification and reason, `pending`, `oldest_age_ms`, `ttl_ms`, `decision`, `reason`, `original_invoked` and `original_result`

A denial is logged **before** returning, with `original_invoked=0 original_result=-1`, and has no `tome_read_exit`. A forward is logged after the original returns, with its result, and is followed by `tome_read_exit`. A read that was never intercepted has no `tome_read_enter` at all. `ledger_add`, `ledger_ack`, `ledger_expired` and `ledger_cleared` are unchanged.

### Interaction with Papyrus

The detour never calls Papyrus, waits for a task, or mutates inventory. A denied pending read leaves the tome where the caller put it: in the inventory after Read Or Take's pickup, or in the inventory for an inventory read. The queued `OnItemAdded` decides exactly as today, then acknowledges. After that acknowledgement the count is zero and reads forward. If Papyrus accepted the tome, it is readable from the inventory. If Papyrus rejected it, it has been removed. A denied container read leaves the tome in the container, and no acquisition event occurs. A later Take goes through Papyrus normally.

## Offline results, 15 November 2026

`xmake -y` (releasedbg, SE and AE) built schema 10 without warnings and installed it. SHA-256 `8F1794DB0EDB47E0D9ECC7EA7495B0961CBAD88DF2759761199376C6608BC9D4`, preserved as `task06-preservation/read-enforcement.dll` and `.pdb`. Pyro compiled the unchanged Papyrus sources (2 succeeded, 0 failed); the deployed PEX remains the Task 05B build. `cl /std:c++20 /W4 /WX /EHsc` passes these suites:

| Suite | Coverage |
| --- | --- |
| `read_enforcement` (new) | **Pending:** one or two pending copies denied; matched acknowledgement clears; denial before a rejecting acknowledgement; readable after an accepting one; unknown caller with a pending entry denied; missing, expired and unconsulted ledger forwards; a different FormID unaffected; clear on load; concurrent reader, adder and acknowledger (2000 each) end consistent. **Container:** external side denied (with or without pending); player side and inventory forward; unavailable side, conflicting menus, worker thread and no-menu forward; a category without the positive side reason forwards; ordinary/skill books and non-player readers forward. **Regression:** no policy forwards everything; mode selection for all eight markers; no marker gives no hook; any two markers give `conflict` and no hook. |
| `tome_ledger`, `world_read_denial`, `tome_read_context`, `tome_read_decision`, `observation_queue` | Unchanged and passing. The schema 8 decision suite confirms its behaviour is unchanged. |

A negative control asserting denial for an open ContainerMenu with an unknown side fails to compile, which confirms the assertions are evaluated.

## Runtime results, 15 November 2026 (Task 06 sessions)

Preserved in the native checkout under `task07-preservation/`, with `SHA256SUMS.txt`.

**Container mode, 17:38 launch.** The native and Papyrus logs are both preserved (`schema10-deny-container-read-20261115-1738-*`).

- **Verified by native log:**
  - `selected=deny_container_read` and `tome_read_probe_ready`.
  - Eight consecutive chest-side reads of Firebolt (17:39:11–17:39:15) each logged `classification=external_container reason=container_external_side decision=deny reason=container_side_without_acquisition original_invoked=0`, with no `tome_read_exit`.
  - The chest Take at 17:39:24 logged `ledger_add source=000371E9`, then `ledger_ack outcome=reject-removed status=matched`.
  - A second Take with the mod disabled at 17:40:19 was acknowledged as `Disabled`.
  - The player-side ContainerMenu read at 17:40:38 logged `classification=player_inventory reason=container_player_side decision=forward reason=player_side_context original_invoked=1`.
  - Every acknowledgement in the log is `matched`, with no expired, late, unmatched or excess rows.
- **Verified by Papyrus log:** one pickup entry, from source `000371E9` with `container=TRUE`, then `eligible=False` and `after RemoveItem`.
- **User report:** the spell stayed unknown during the repeated denied reads.

**Pending mode, 17:27 launch.** Only the Papyrus log survives (`schema10-deny-pending-acquisition-20261115-1727-papyrus-native-log-lost.log`). The native log was overwritten by the 17:38 launch, and no copy was found on the machine.

- **Verified by Papyrus log:** five tome acquisitions (`000A26FD` twice, `000A2705`, `000A26F9`, `00109112`). Each logged `eligible=False` and a completed `after RemoveItem`, and **none** logged `reject-skipped-empty-inventory`. In the schema 9 baseline a Read Or Take world READ produced that row, because the forwarded read had already consumed the tome.
- **User report:** four Read Or Take world READ attempts were denied with `original_invoked=0`.
- **Not verified by preserved native evidence:** the `tome_read_decision deny pending_acquisition` rows themselves, and which of the five acquisitions were READs rather than Takes.

**Not yet tested:** P5–P7, C2 (corpse), C5 (books), C6, and any run of the unified mode below.

## Runtime matrix

Environment: 1.7.104 through MO2, Read Or Take 1.5.1 enabled, SkyUI, base Magicka 100, threshold 150, MCM debug logging, `bEnableTrace=1`, a disposable save. For every case, check the spell list and final inventory or container contents in game, not only the logs. Copy `UntamedTomesSKSE.log` and `Papyrus.0.log` from the same launch into `task06-preservation/`.

**Pending mode.** The only marker is `UntamedTomes.DenyPendingAcquisition`. Startup must log `observer_load schema=10`, `selected=deny_pending_acquisition`, `tome_read_probe_ready mode=deny_pending_acquisition` and `ledger_ready keyword_resolved=true`.

| Case | Action | Expected | Status |
| --- | --- | --- | --- |
| P1 | World READ Firebolt (dungeon) | `tome_read_decision decision=deny reason=pending_acquisition original_invoked=0`. No `spells_learned`. Then `ledger_ack outcome=reject-removed status=matched` (not `reject-skipped-empty-inventory`). Spell not learned, tome gone. | Not run |
| P2 | World READ another tome | As P1, with no Firebolt-specific logic | Not run |
| P3 | World TAKE | No read rows. `reject-removed`, matched. | Not run |
| P4 | Accepted tome READ from inventory (town pickup or added while disabled) | `forward reason=no_pending_acquisition original_result=1`, spell learned | Not run |
| P5 | Inventory READ while pending (open the inventory immediately after pickup) | `deny pending_acquisition` until the acknowledgement, then forward or removed | Not run |
| P6 | Two closely spaced acquisitions of one tome | `pending=2`, then two matched acknowledgements. Reads in between denied. | Not run |
| P7 | Expiry (only if a stall can be induced) | `ledger_expired` after 10 s, then `no_pending_acquisition` forward. No permanent block. | Not run |

**Container mode.** Restart with only `UntamedTomes.DenyContainerRead`.

| Case | Action | Expected | Status |
| --- | --- | --- | --- |
| C1 | Chest, take tab, select an unlearned tome, **hold Left Shift** until the bar shows `Read`, then activate | `deny container_side_without_acquisition original_invoked=0`. Spell not learned. Tome still in the chest. No `ledger_add` and no Papyrus pickup row. | Not run |
| C2 | As C1 on a corpse | Same as C1 | Not run |
| C3 | Take the same tome normally | `ledger_add source=<chest>`, Papyrus decision and a matched acknowledgement | Not run |
| C4 | Read from the give tab (player side) while eligible | `forward player_side_context`, learned | Not run |
| C5 | Ordinary and skill books | Normal. No enforcement rows. | Not run |
| C6 | Ambiguous or unsupported context, for example a world READ through Read Or Take in container mode | `forward unknown_context` | Not run |

## Unified enforcement (schema 11, Task 07)

The marker `UntamedTomes.EnforceTomeReads` selects mode `enforce_tome_reads` (policy `unified`). It is mutually exclusive with every other marker. `DecideEnforcement` applies the existing rules in one place, with no duplicated detour logic:

1. If `pending > 0`, **deny** with `pending_acquisition`, whatever the caller classification (including off the main thread).
2. Otherwise, if the read is a positively identified external-container read, **deny** with `container_side_without_acquisition`.
3. Otherwise, **forward** with `no_pending_acquisition`, or `ledger_unavailable` if the ledger could not be consulted.

A missing or ambiguous classification never denies on its own. The standalone modes behave exactly as in schema 10.

Diagnostics changed:

- `ledger_ready` now reports `mode=<selected mode> enforcement=<policy>`, replacing the misleading `mode=observe_only`.
- `ledger_ack` adds `papyrus_decision`, which is one of:
  - `accepted` for `accept-*`;
  - `rejected` for `reject-*`;
  - `not_evaluated` for `disabled`;
  - `unknown` for anything else.
- `pending=0` is reported only as `no_pending_acquisition`, never as accepted.
- `tome_read_decision` adds `trap_candidate=read_attempt` on denials. This is observation only.

Build: schema 11, SHA-256 `DD1B571A2F8F496505D31E08AE0F4B2A38142B242D92F87CDBD6273667E8D098`, preserved as `task07-preservation/unified-enforcement-debug-trap.dll`. It compiled without warnings, and all six offline suites pass. The new unified cases cover the precedence above, the accepted-path lifecycle (denied while pending, forwarded after an accepted acknowledgement, container-side still denied), and outcome classification. **No runtime test of the unified mode has been run.**

### Core behaviour matrix (unified mode)

| Interaction | Native read gate | Papyrus | Expected result | Evidence |
| --- | --- | --- | --- | --- |
| World TAKE, ineligible | No read | Rejects, removes | Tome gone, spell unknown | Observed in schema 9 and 10 |
| World TAKE, eligible | No read | Accepts | Tome kept | **Not tested** with the mod enabled |
| Read Or Take world READ, ineligible | Deny `pending_acquisition` | Rejects, removes | Spell unknown | Pending mode (Papyrus log and user report) |
| Read Or Take world READ, eligible | Deny while pending | Accepts | Tome in inventory; read again to learn | Not tested |
| Chest or corpse TAKE | No read | Decides by context | As for world TAKE | Chest observed. Corpse not tested. |
| Chest-side READ | Deny `container_side_without_acquisition` | Not involved | Tome stays in chest, spell unknown | Container mode, 8 denials |
| Inventory or player-side READ, nothing pending | Forward | Not involved | Learned, consumed by the caller | Observed (tomes added while disabled) |
| Inventory READ while pending | Deny | Pending decision | Readable after an accepted acknowledgement | Offline only |
| Ordinary or skill book | Not evaluated | Not involved | Vanilla | Not retested since schema 6 |

### Installation and selection

Install the Untamed Tomes MO2 mod (ESP, `Scripts/*.pex`, `SKSE/Plugins/UntamedTomesSKSE.dll`) with SKSE, Address Library, PO3 Papyrus Extender and SkyUI. Read Or Take is optional. Select exactly one empty marker in `Documents\My Games\Skyrim Special Edition\SKSE\`, for example `UntamedTomes.EnforceTomeReads`. The debug trap marker `UntamedTomes.DebugTrap` is independent (Inv. 15) and may be combined with any mode. Rollback is described below. Use `task07-preservation`, `task06-preservation` or earlier builds with their matching PEX.

## Known limitations and remaining bypasses

- Skyrim 1.7.104 only. DEST, Lodestone, SpellLearning and Heart of Magic prevent installation.
- **The modes are exclusive.** With either one alone, the other path remains open: pending mode leaves container-side reads unprotected, and container mode leaves the Read Or Take world READ and the inventory race unprotected. Combining the policies would be a separate, tested step.
- Pending denial needs the synchronous player-inbound notification, filtered by `VendorItemSpellTome`. Tomes without the keyword, and acquisitions without that notification, are not covered.
- Expiry fails open after 10 s with `ledger_expired`. During a VM stall longer than that, an undecided tome can be learned.
- Container denial needs SkyUI's `isViewingContainer`. A menu replacer without it gives `unknown_context` and forwards.
- Base-form counting briefly blocks an older accepted copy while a new copy of the same tome is pending (about 1 s).
- Spells granted without `Read` (script, quest, console or other mods' `AddSpell`) are outside this mechanism.
- Denial gives no player feedback. The Read Or Take world READ becomes a Take.

## Rollback

- **Experiment off:** delete the enforcement marker. With `UntamedTomes.ObserveLedger` the schema 10 DLL behaves like schema 9. With no marker it installs no read hook.
- **Schema 9 exactly:** copy `task06-preservation/pre-task06-schema9.dll` and `.pdb` (`78466971…`) over `D:\Modding\Ancestries\mods\Untamed Tomes\SKSE\Plugins\UntamedTomesSKSE.dll` and `.pdb`. It works with the deployed PEX (`0AE1819A…`, identical to `pre-task06-UT_PlayerMonitor.pex`).
- **Earlier baselines:** follow Inv. 13 §14. A DLL older than schema 9 needs `task05b-preservation/pre-ledger-*.pex`.
