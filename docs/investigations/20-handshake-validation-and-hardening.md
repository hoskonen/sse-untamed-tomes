# Investigation 20 — World tome handshake: runtime validation and hardening

## Status

Schema 17 hardens the schema 16 handshake (Inv. 19) and has been built, tested offline and deployed. It changes two things.

- **Authorisation grants are bound to the inventory transfer.** A grant now comes from the inventory transfer that the authorised activation actually caused. It no longer comes from a per-base slot.
- **No forward without an answer.** An in-scope tome is no longer forwarded without a matching Accepted or Exempt answer. A timeout, a missing handler and an internal error all keep the tome in the world.

Builds and tests:

- **Native:** builds cleanly.
- **Papyrus:** 2 of 2 scripts compile.
- **Offline suites:** all 10 pass. `world_tome_handshake` now has 26 cases.

Deployed files:

| File | SHA-256 |
| --- | --- |
| DLL | `89A638E42C7F9108188D8CAC95ED4DB4050B49C5FACE4FCC26B32A491417B90F` |
| PEX | `2E1FE3358B4E81839DEE042FBB7FDDB1BB638EF7ECFDBDDA1A26BEEA3D8577E4` |

The rollback files and logs are in `task12-preservation/`, with a SHA-256 manifest.

**Runtime status (schema 17, 16 November 2026, §12).** Verified in game:
- world rejection and re-evaluation;
- eligible pickup of the same, previously rejected reference;
- grant binding and consumption;
- no trap after an authorised pickup;
- two references authorised and collected independently;
- inventory reads forwarded through the DEST-compatible read hook;
- reset and re-registration on save and load.

Still open: DESTified study completion, save and load *during* a pending request or an active authorisation, the exemptions, missing-handler recovery, Read Or Take disabled, and the full load order (§13). Schema 17 is an experimental checkpoint, not production-ready.

## 1. Schema 16 runtime evidence (16 November 2026, 18:52–18:55)

The run is preserved as `task12-preservation/schema16-session-{native,papyrus}.log`.

**Setup:**
- profile with `WorldTomeHandshake`, `EnforceTomeReads`, `DebugTrap` and `FireTrap`;
- DEST 1.2.3 loaded (`read_body=dest_window_patched`);
- Read Or Take was the previous owner of the activation slot (`owner=ours`);
- Papyrus ready 185 ms after `kPostLoadGame`;
- Bleak Falls Barrow, base Magicka 100, threshold 150, one Firebolt reference `FF000F0C`.

| Observed | Evidence |
| --- | --- |
| 13 activations of the same reference, all vetoed | `previous_called=0` on every row; the reference is unchanged (`ref_3d=true`, same xyz) |
| 8 independent evaluations, 8 refusals | `outcome=reject-ineligible status=rejected` |
| Each refusal showed its pulse | `shader=played`, `notification=1` |
| 5 activations during the cooldown | `reason=rejected_cooldown`; no request, no feedback |
| Re-evaluation once the cooldown passed | A fresh request each time |
| No unintended pickup or trap | No `ledger_add`, `tome_read_*` or `defense_effect` row during the session |
| Papyrus | No errors from `UT_PlayerMonitor` |

Not observed:
- several activations while a request was pending, since every repeat came after the answer;
- eligible acquisition;
- a second reference;
- save and load;
- exemptions.

## 2. Confirmed defects and root causes

| # | Defect | Root cause | Fix (schema 17) |
| --- | --- | --- | --- |
| D1 | **Per-base grant could authorise a different copy** (design) | The grant was recorded per base *before* forwarding, whether or not the forward transferred anything. Example: an authorised activation that added nothing followed by a chest Firebolt within 5 s skipped the chest copy's evaluation. | Grants are bound to the observed inventory transfer and carry the authorised reference and request (§4) |
| D2 | **The timeout fallback could destroy a protected tome** (design) | `TimedOut` forwarded the next activation to the post-acquisition path. That removes the tome from an ineligible character (and fires the trap), or grants it silently if `OnItemAdded` is also broken. | A timeout now means a protected retry, with unavailable feedback (§5) |
| D3 | **`papyrus_not_ready` forwarded in-scope tomes** (design) | The same consequences as D2 whenever the handler was missing or not yet registered | Veto, plus a native notice |
| D4 | **An exception in the handshake path failed open** (design) | `catch (...)` set `forward = true` | Fails closed once scope is known |
| D5 | **Re-evaluations were logged as `new_request`** (observed: activations 9–13 show `state_before=unknown`) | `Prune` ran before `OnActivation` and erased the rejected entry first | Prune now runs after classification; covered by a test |
| D6 | **Mislabelled dispatch thread** (observed) | `main_thread=` printed the input thread (29348). The SKSE task actually ran on 26512, 30588 and 27396. | Renamed `input_thread=` and tagged `boundary=skse_task`; corrected in §6 |
| D7 | **The generation could collide across processes** (analysis) | The generation was the per-process session counter, which repeats after a restart (`2` both times). A Papyrus stack saved while a request was pending resumes after loading and could match a new request with the same ID and reference. | Generation = per-process random nonce × 1000 + session; request IDs never reset |
| D8 | **Feedback could appear for an unloaded tome** (analysis) | Papyrus notified regardless of where the tome was | Feedback only while the tome's 3D is loaded; otherwise `no_feedback present=False` |

D1 to D4 and D7 were found by review and confirmed by offline tests, not observed in game.

## 3. Handshake state (schema 17)

**Invariant:** an in-scope activation reaches the previous handler only by consuming an `Authorized` entry, which in turn needs a matching Accepted or Exempt answer.

| State | Next activation |
| --- | --- |
| Unknown | Veto and request. If 8 or more requests are pending: veto with `capacity` (no entry is created), plus the unavailable notice |
| Pending | Silent veto with `pending_request` |
| Rejected | Silent veto for 2 s, then a fresh request (`reevaluate`) |
| Unavailable *(new)* | Silent veto for 2 s, then `retry_after_unavailable` |
| TimedOut | Veto and a fresh request (`retry_after_timeout`), counting consecutive timeouts, plus the unavailable notice. **Never forwarded** |
| Authorized | Within 30 s: the entry is erased, then one forward. After 30 s: `authorization_expired`, which starts a fresh request |

**Pruning.**
- Rejected and Unavailable entries are dropped after their cooldown.
- Authorized and TimedOut entries are dropped after 30 s.

A dropped entry returns to Unknown, which is still protected.

**Bounds.** Each reference has at most one pending request, and there are at most 8 in total.

## 4. Reference-scoped acquisition grants

### Mechanism

1. **Context set.** Just before calling the previous handler for an authorised activation, the thunk sets a thread-local `ForwardContext` holding the request, the world reference, the base and the time. It is cleared, or the outer context restored, as soon as the call returns.
2. **Binding.** During the pickup, the engine dispatches the player-inbound `TESContainerChangedEvent` synchronously on the activation thread. In the Inv. 18 run, the container row (`thread=11404`) sits between the forward and its return on that same thread. If the context is active and the base matches, the sink binds an `AcquisitionGrant`: request, world reference, base, count, time. It logs `world_tome_acquisition stage=bound … since_forward_us=`.
3. **Return.** `world_tome_forwarded … acquisitions_bound=N` is logged, as a warning when N = 0. With N = 0 no grant exists, and the resulting addition, if there is one, is evaluated normally.
4. **Papyrus.** `OnItemAdded` calls `UT_ConsumeWorldTomeGrant(base, count, akItemRef)`:
   - **`akItemRef` present** (a persistent reference): only a grant with that exact world reference matches (`exact_reference`). A grant for another reference gives `reference_mismatch`, so it is not consumed and the addition is evaluated.
   - **`akItemRef` None** (the normal case; `ref_handle=0` in every logged pickup): the copy has merged into an anonymous stack of identical items. The oldest grant for that base, with enough count, matches (`anonymous_stack`).
5. **Expiry.** A grant lasts 10 s, the same as the ledger. After that, the addition is evaluated. Load and new game clear all grants.

### Why stack matching is exact enough

When `akItemRef` is None, the game itself no longer distinguishes the copies. `RemoveItem(base, 1)` removes "a Firebolt", not a particular one.

Take an authorised world copy and an unauthorised chest copy that both arrive within the window. There is still **exactly one** grant, because only the forwarded activation binds. One `OnItemAdded` is pre-authorised and the other is evaluated, whichever order they run in. The inventory result is the same as with perfect correlation.

A copy that the activation did not transfer can no longer create or consume a grant on its own. That was the D1 failure.

### Offline tests

The `world_tome_handshake` suite covers:
- a failed pickup, which leaves no grant;
- an unauthorised copy, which never creates one;
- an exact persistent reference, which rejects a mismatch;
- three rapid, overlapping authorised pickups across two bases, consumed in interleaved order;
- an authorised addition interleaved with a chest addition (exactly one pre-authorised);
- expiry;
- count coverage.

## 5. Timeout and failure recovery

The decision is **protection over access, with explicit feedback and a bounded retry**.

| Failure | Behaviour | Player recovery |
| --- | --- | --- |
| Papyrus slow (answer after 5 s) | Late answer → `expired`, ignored. The next activation sends a fresh request; the notice is shown | Activate again |
| Papyrus answers `unavailable-*`, or an unrecognised outcome | Unavailable state; Papyrus shows "cannot judge you right now" | Activate again after 2 s |
| Request undeliverable (handle gone, deleted, disabled, cell changed) | Cancelled; back to Unknown | Activate again |
| Handler not registered this session (script missing, old PEX, or registration failed) | Every in-scope activation is vetoed with `papyrus_not_ready`, plus the throttled native notice "The tome's judgement is unavailable. It stays sealed; try again." | Reload, because `OnPlayerLoadGame` re-registers. A persistent failure is an installation fault: remove the `UntamedTomes.WorldTomeHandshake` marker to disable the hook |
| Mod disabled through `UT_ModEnabled` | Papyrus answers `disabled` (Exempt), then one more activation takes the tome | Normal |
| Capacity (8 pending) | Veto with no entry, plus the notice | Activate again |
| Exception in the handshake path | Veto (fail closed) | Activate again |

**Why not forward on failure.** When Papyrus does not answer, both possible forward outcomes are wrong.

- **Papyrus slow:** the forward reaches the post-acquisition path, which removes the tome from an ineligible character and fires the trap.
- **Papyrus dead:** nothing runs `OnItemAdded`, so the tome is granted silently.

Neither is acceptable for a protected tome. A temporary failure therefore costs one more activation, and a permanent one is visible and reversible.

**Ownership of the infrastructure notice.** Native code owns it because Papyrus may be the failing part. It goes out through the SKSE task boundary with `ShowHUDMessage` (AE ID 52933), at most once every 3 s. It is never a defense.

**New-game ordering.** The ready flag is cleared only at pre-load. The relative order of `kNewGame` and the quest's `OnInit` is unverified. A stale ready flag can only produce timeouts, which are protected.

## 6. Reference, thread and session safety

**Threads.**

| Thread | What runs on it | Runtime evidence |
| --- | --- | --- |
| Activation (game worker: 26512, 27396, 30588, 14016) | Reads only the target the engine passed in (deleted and disabled flags, keyword array, cell), takes a handle, posts a task. No Papyrus calls and no game state changes | Logged |
| SKSE task | Resolves the handle into a counted `NiPointer`, re-checks the reference, sends the ModEvent | `thread=` logged; SKSE's supported game-thread dispatch boundary |
| Papyrus VM | Native answers touch only the table under a mutex, plus the FormIDs of the references passed in | Logged |
| Container sink | The binding runs on the activation thread inside the forwarded call | Inv. 18 run (`thread=11404`) |

The same worker thread IDs appear in all four roles. The engine schedules this work on a shared job pool, so "main thread" in the earlier wording (Inv. 19) was wrong. **No raw reference pointer is stored or used across threads.**

**Session and identity checks.**

- **Load or new game:** the table, grants and timings are reset, and the generation changes.
- **Stale or invalid answers:**

  | Answer | Status |
  | --- | --- |
  | From an earlier generation, including one resumed from a saved stack | `stale_generation` |
  | Unknown request ID | `unmatched` |
  | Different reference | `reference_mismatch` |
  | Second answer to the same request | `duplicate` |
  | After the timeout | `expired` |

  None of them changes state or produces feedback.
- **Reused FormID:** a FormID that turns up with a different base starts over.

**Each Section 6 test case, and what covers it.**

| Case | Covered by |
| --- | --- |
| Two Firebolt references | Offline; runtime pending |
| Multiple bases | Offline (grant tests); runtime needs `WorldTomeHandshakeAllTomes` |
| Rapid repeated activation | Runtime for the cooldown; offline for pending |
| Save and load while pending, or while authorised | Offline; runtime pending (session C) |
| Cell change while pending | Dispatch check plus offline; no feedback while unloaded (D8) |
| Returning to a rejected tome | Runtime (fresh evaluation after the cooldown) |
| Reference disabled, deleted or unloaded before the answer | The dispatch check, plus the answer never touching the reference; Papyrus feedback requires `Is3DLoaded` |
| Late, duplicate, stale or mismatched answers | Offline |

## 7. Compatibility and exemptions

| Item | Status |
| --- | --- |
| Shared eligibility (safe context, `UT_TomeSafe`, exclusions, quest reference, player, Magicka) | The world path calls the same `UT_EvaluateTomeEligibility` as `OnItemAdded` (Inv. 19 §4). Only the dungeon/ineligible branch has been observed in game |
| Safe location | Runtime pending (session B) |
| `UT_TomeSafe`, exclusions, quest reference | Shared code, but **not testable without plugin data**: no vanilla tome carries `UT_TomeSafe`, the exclusion list needs the ESP, and a quest-flagged world tome needs a quest. Open |
| Mod disabled (`UT_ModEnabled`) | Runtime pending (session B, through the MCM) |
| Ordinary and skill books, other tomes | Scope filter, tested offline; runtime pending (session A) |
| Non-player activation | Scope filter, tested offline; not practical to trigger in game |
| Chest Take | Does not pass through book `Activate`. Inv. 18 shows the existing path running; runtime pending with the handshake (session A) |
| Read Or Take disabled | Runtime pending (session D) |
| DEST 1.2.3 and unified read enforcement | Startup rows unchanged in the schema 16 run. Study after an authorised pickup is pending |
| Read Or Take READ on an authorised tome | Forwarded once. Read Or Take picks it up, unified enforcement denies the world read (`pending_acquisition`), and the tome goes to inventory with no trap (grant consumed). The read itself stays controlled. Runtime pending |

## 8. Measured latency (schema 16, 8 rejections, `since_activation_ms`)

Papyrus debug tracing was on during the run (`UT_DebugEnabled`), which adds trace calls inside the evaluation.

| Stage | Min | Median | Max |
| --- | --- | --- | --- |
| Activation → task dispatch | 31 | 33 | 33 |
| Dispatch → Papyrus receives the event | 64 | 65 | 81 |
| Papyrus receipt → native answer (evaluation) | 534 | 608 | 633 |
| Answer → feedback logged (shader, name, notification) | 200 | 217 | 217 |
| **Activation → feedback** | **831** | **930** | **947** |

The Papyrus-measured `evaluate_ms` was 560–593. In the debug traces (requests 1–4), context gate 1 completed about 135 ms after entry, gate 2 about 310 ms and the Magicka decision about 450 ms. Each gate is about 140–175 ms. There was no unusually slow case: the spread is 116 ms.

**Where the time goes.**
- About 65% is Papyrus evaluation. It is dominated by the location context lookup, which runs twice because the shared evaluator keeps the historical second gate.
- About 23% is feedback presentation.
- About 10% is dispatch plus VM queueing.

The native side contributes about 33 ms, roughly two frames.

No optimisation was made. The obvious candidates are the duplicate context gate and the order of feedback calls (pulse first). Both change shared or presentation code, so they should be measured with debug tracing off first.

Eligible-path latency, from activation to grant consumption, is not yet measured. Schema 17 logs `since_forward_us` at binding, and `since_bind_ms` and `since_activation_ms` at consumption.

## 9. In-game test sessions (schema 17)

**Startup checks:**
- `observer_load schema=17`;
- `world_tome_handshake_config`;
- `pickup_veto_ready … policy=world_tome_handshake`;
- `owner=ours`;
- after loading, `world_tome_handshake_reset … generation=<large number>` and `world_tome_handler_ready`.

Keep the current markers. Preserve both logs after each session.

**Session A (one dungeon setup).** Use threshold 150 and `player.setav magicka 100`. Run `player.placeatme 000A26FD` three times (T1, T2, T3), and place one ordinary book and one skill book.

| # | Action | Pass when |
| --- | --- | --- |
| A1 | Activate T1, then spam it 5 times within 0.5 s | One `veto_and_request`, then `pending_request` vetoes, then one refusal pulse |
| A2 | Activate T1 at about 1 s and about 3 s | `rejected_cooldown`, then `reevaluate`; a second pulse; T1 still in place |
| A3 | `player.setav magicka 200`; activate T1; then activate it again | Answer `accept-eligible status=authorized`, "yields"; `forward reason=authorized`, `world_tome_acquisition stage=bound world_ref=<T1>`, `acquisitions_bound=1`, `world_tome_grant match=anonymous_stack consumed=true request=<same>`, `ledger_ack outcome=accept-preauthorized`. **No** `defense_effect`, no removal |
| A4 | `player.getitemcount 000A26FD`; check that T1 is gone from the world | Count = 1; T1 `deleted=true` in the forwarded row |
| A5 | Read the Firebolt in inventory | Accepted inventory read; DEST keeps the book; DESTified/ISL study starts |
| A6 | `player.setav magicka 100`; activate T2 | Refused, independently of T1's earlier approval |
| A7 | `player.setav magicka 200`; authorise T3, then use Read Or Take **READ** | Read denied (`pending_acquisition`); T3 in inventory; grant consumed; no trap |
| A8 | `player.setav magicka 100`; take a Firebolt added to a dungeon chest (console: select the chest, `additem 000A26FD 1`) | No activation rows; `world_tome_grant match=none`; `reject-removed`; the existing trap |
| A9 | Activate the ordinary book, the skill book and another tome | Vanilla behaviour; another tome logs `not_test_tome` |

**Session B (town).** Run `coc Riverwood`, with Magicka 100.
- B1: place a Firebolt and activate it. Expect `accept-safe-context`, "yields", then take it.
- B2: turn the mod off in the MCM, place another and activate it. Expect `disabled`, then take it.

**Session C (save and load).** In a dungeon with Magicka 200:
- C1: authorise a tome, quicksave, quickload, activate. Expect `world_tome_handshake_reset entries_discarded=1`, then a **new** request, with no forward from before the load.
- C2: activate, quicksave within about 0.5 s (while pending), quickload. Expect any resumed Papyrus answer to be `stale_generation`, with no feedback after the load, and the tome usable.

**Session D (optional).** Disable Read Or Take in MO2 and restart. Expect `previous_module=SkyrimSE.exe`, then repeat A1 and A3.

## 10. Remaining risks

- **Binding depends on synchronous dispatch.** Grant binding relies on the container event being dispatched synchronously during the forwarded call. That was observed with Read Or Take. With Read Or Take disabled (vanilla pickup), or with a mod that defers the transfer, the expected result is `acquisitions_bound=0`. That is safe: the pickup is then evaluated normally, so an eligible character still keeps the tome. The trap would only fire if the character were ineligible at that moment.
- **Permanent Papyrus failure.** In-scope tomes stay sealed until the install is fixed or the marker is removed. That is deliberate (§5).
- **Untested exemptions.** The `UT_TomeSafe`, exclusion and quest-reference exemptions are untested in game without plugin data.
- **Two activations needed.** Eligible and exempt characters still need two activations.
- **Generation wrap.** The generation includes the session modulo 1000. A collision would need the same process, the same request ID and the same reference, and request IDs never repeat within a process.
- **Scope.** The scope is still Firebolt only. `WorldTomeHandshakeAllTomes` is untested.

## 11. Rollback

| Rollback to | Copy from `task12-preservation/` | Install as |
| --- | --- | --- |
| Schema 16 | `pre-task12-schema16.dll` and `.pdb` | `SKSE\Plugins\UntamedTomesSKSE.dll` and `.pdb` |
| | `pre-task12-UT_PlayerMonitor.pex` | `Scripts\UT_PlayerMonitor.pex` |
| Schema 15 | Inv. 19 §8 | |

**Replace the DLL and PEX together.** The `UT_ConsumeWorldTomeGrant` signature changed, so a mismatched pair fails to bind the native.

**Disable without replacing files:** remove the `UntamedTomes.WorldTomeHandshake` marker.

## 12. Schema 17 runtime results (16 November 2026, 19:38–19:44)

The run is preserved as `task13-preservation/schema17-session-native.log`, `schema17-session-papyrus.log` and `schema17-session-papyrus.1.log`, with a SHA-256 manifest.

**Setup:**
- Skyrim 1.7.104, Address Library format 5;
- DEST 1.2.3 (`read_body=dest_window_patched`);
- Read Or Take was the previous slot owner (`owner=ours`);
- markers `WorldTomeHandshake`, `EnforceTomeReads`, `DebugTrap` and `FireTrap`;
- Bleak Falls Barrow (cell `000371DD`), base Magicka 100.

**Eligibility was changed by lowering the threshold, not by raising Magicka.** The Papyrus traces show `threshold=150` for request 1 and `threshold=100` from request 2 onwards, with `baseMagicka=100` throughout.

| Step | Request | Reference | Evidence |
| --- | --- | --- | --- |
| Rejection, tome stays | 1 | `FF000F0C` | `reject-ineligible status=rejected`; `shader=played`; reference unchanged |
| Re-evaluation of the same tome | 2 | `FF000F0C` | `reason=reevaluate state_before=rejected` (the D5 fix confirmed), then `accept-eligible status=authorized`, "yields" |
| Authorised pickup | 2 | `FF000F0C` | Activation 3: `forward reason=authorized previous_called=1`. It was a Read Or Take READ: unified enforcement denied the world read (`pending_acquisition`, `original_invoked=0`), and the tome went to inventory |
| Grant bound to the transfer | 2 | `FF000F0C` | `world_tome_acquisition stage=bound … since_forward_us=1378`, `acquisitions_bound=1`; afterwards the reference was `deleted=true` |
| Grant consumed; no second evaluation | 2 | — | `world_tome_grant match=anonymous_stack consumed=true request=2 since_bind_ms=112`; `ledger_ack outcome=accept-preauthorized`; Papyrus `decision=accept-preauthorized` |
| Inventory read | — | — | 19:40:19: `classification=player_inventory decision=forward original_invoked=1 original_result=false known_after=0`. That is the DEST path: the book is kept and nothing is taught directly |
| Out-of-scope tome untouched | — | `FF000F0D` (`000A2705`) | `forward reason=not_test_tome`, `match=none`, evaluated normally (`accept-eligible`). No cross-grant |
| Save and load | — | — | Generation `1714577002` → `1714577004` (per-process nonce), `world_tome_handler_ready session=4` |
| Two references of one book | 3, 4 | `FF000F04`, `FF000F05` | Independent requests, both `authorized`; taken in order 3 then 4, each `bound` to its own request, and each grant consumed with matching `request=` and `world_ref=` |
| Trap after authorised pickups | — | — | No `defense_effect` stage row in the whole session; the only match is the startup configuration row |

**Not handshake activity.** Four Firebolt additions (19:42:39, 19:42:40, 19:43:30, 19:43:31) have no activation rows, `source=00000000`, and the input thread. They were acknowledged with `outcome=Disabled`, so the mod was off through its global at the time. That fits console `additem`, but the source cannot be identified from the logs. They exercise only the `disabled` acknowledgement path. The read at 19:43:40 was another forwarded inventory read.

**Latency in this run (`since_activation_ms`):**

| Request | Dispatch | Papyrus received | Answer | Feedback | Outcome |
| --- | --- | --- | --- | --- | --- |
| 1 | 47 | 112 | 727 | 978 | refusal |
| 2 | 32 | 97 | 730 | 914 | authorised |
| 3 | 15 | 81 | 580 | 730 | authorised |
| 4 | 33 | 81 | 615 | 765 | authorised |

These figures match the schema 16 profile, with Papyrus evaluation still dominant (`evaluate_ms` 522–599).

On the authorised path:
- the inventory event arrived 0.3–1.4 ms after the forward;
- `OnItemAdded` consumed the grant 81–112 ms after binding.

## 13. Open validation gaps (not passed; offline tests do not substitute)

| Gap | State |
| --- | --- |
| DESTified study completion and eventual spell learning | **Open.** The inventory reads forwarded (`original_result=false`, the DEST behaviour), but no study rows were logged. The Papyrus log shows `DEST_ISL_PlayerSpellLearningScript` property-initialisation warnings at every load; this needs investigating in DESTified, separately from Untamed Tomes |
| Save and load while a request is pending | Open (only the reset after a load with no requests was observed) |
| Save and load while an authorisation is active | Open |
| Safe-location and `UT_TomeSafe` exemptions | Open |
| Quest-protected tomes and exclusions | Open; need plugin data |
| Missing-handler recovery (`papyrus_not_ready` veto and notice) | Open; offline only |
| Timeout, retry and capacity under real load | Open; offline only |
| Read Or Take disabled | Open |
| Exact attribution under unusual concurrent transfers | Partially covered: two sequential references verified; true concurrency offline only |
| Ineligible chest Take with the handshake active | Open in schema 17 (the path is unchanged since Inv. 18) |
| The full Ancestries load order | Open: only this test profile was used |

## 14. The two-activation limitation (high-priority follow-up)

Today an eligible or exempt world tome needs **two** activations:

1. The first activation is vetoed.
2. Papyrus evaluates eligibility (about 0.6 s).
3. Native code authorises the reference.
4. The player activates it again within 30 s to take it.

**Desired behaviour:**
- **Eligible or exempt:** one activation, then automatic acquisition once authorised.
- **Ineligible:** one activation, an immediate visible reaction, then the refusal and the magical defense.
- **Rejected tome:** stays at its original world location.

**Questions to investigate before any implementation (automatic continuation):**

1. **Resuming the activation.** Can the original activation be resumed safely after approval? Options:
   - re-invoke `TESObjectREFR::ActivateRef` (AE 19796) with the player as activator;
   - call the captured previous handler (`previousBookActivate`) directly, which skips `ActivateRef`'s bookkeeping (the activation event, the `6A77C0` post-activation call, the flag at `1431DF3DC`);
   - call `PlayerCharacter::PickUpObject` directly, which bypasses Read Or Take.
2. **Thread and game state.** Which thread and game state must own the continuation? An SKSE task runs on the shared worker pool (§6), whereas a player activation arrives with the engine's own context, such as crosshair and activation state. Re-invoking activation outside that context is unverified.
3. **Recursion and duplicates.** Recursion and double activation must be prevented. The continuation must bypass the veto exactly once, for example through a continuation token checked by the thunk, without opening a forward path for any other activation.
4. **Read Or Take.** Its behaviour must be preserved: should a continuation be a Take or a READ? Read Or Take decides from input state at activation time, which no longer exists when the continuation runs.
5. **Player state while pending.** The player may have moved out of range, changed cell, opened a menu (inventory, dialogue, console), started combat, been knocked down, or loaded a game.
6. **Ownership and theft.** The continuation must not automatically take items owned by NPCs or merchants. Taking an owned tome is theft: crime, bounty and witness checks happen at activation. An automatic pickup must not steal silently, nor bypass the player's choice to steal. Possible rule: no auto-continuation for owned references.

**Next gameplay milestone:** a responsive, single-activation world tome.

> Take → immediate magical reaction → asynchronous eligibility → automatic pickup if eligible, defense if rejected.

The first visible response should come from native code at activation time (or the next frame), not after the roughly 0.6 s Papyrus evaluation. Candidate reactions:
- small movement or trembling;
- brief levitation or rotation;
- a glow or shock shader;
- a defensive spell cast from the world reference itself.

Physical animation and real defensive damage stay separate experimental tasks.
