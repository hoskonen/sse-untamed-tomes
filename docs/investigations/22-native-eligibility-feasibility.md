# Investigation 22 — Native eligibility feasibility

## Status

This is an investigation only: no code, Papyrus, schema or deployment changes.

- **Baseline:** schema 18. It is deployed and runtime-tested, but its source is still uncommitted on top of `b4a8568` / `90cc852`.
- **Offline suites:** 10 of 10 pass.
- **Evidence:** the schema 18 session logs (17 November 2026, 20:37–20:43) are preserved in `task15a-preservation/` in the native checkout, with SHA-256 sums.

Evidence labels used throughout:
- **[V]** verified from logs, source or disassembly;
- **[S]** read from source code (ours, CommonLib or Papyrus Extender);
- **[A]** an engineering assumption that still needs a runtime experiment.

**Recommendation: proceed with a native eligibility evaluator (Option A).** Before any behaviour switch, run it in a shadow mode that changes nothing (§10).

## 1. Current architecture and measured latency

**Schema 18 flow:**
1. Take is vetoed.
2. An SKSE task sends a ModEvent.
3. Papyrus `UT_EvaluateTomeEligibility` runs.
4. Papyrus calls `UT_AnswerWorldTomeRequest`.
5. An SKSE task re-validates.
6. The activation is replayed through `ActivateRef`.
7. The grant is bound, then consumed by `OnItemAdded`.

| Stage, schema 18 [V] | Samples (ms since activation) |
| --- | --- |
| Task dispatch | 48, 32, 32, 33, 32, 49 |
| Papyrus receives the event | 147, 97, 96, 97, 96, 114 |
| Papyrus answer (decision) | 746, 680, 697, 680, 729, 697 |
| `evaluate_ms` inside Papyrus | 575, 572, 567, 578, 644, 560 |
| Answer → replay start | 1.6, 3.3, 2.7 (`scheduled` → `replaying`) |
| Replay itself (`replaying` → `replayed`) | 3.2, 1.0, 1.2 |
| **Automatic pickup complete** | **685, 701, 684** |
| Rejection feedback | 996, 980 |
| Grant consumed in `OnItemAdded` | 814, 846, 814 (130–145 ms after binding) |
| Out-of-scope tomes: inventory event → Papyrus ack | 963, 1243, 914, 947, 929, 979 |

**Where the Papyrus time goes [V].** These are the debug traces, timed from evaluator entry.

| Path | Gate 1 | Gate 2 | Decision |
| --- | --- | --- | --- |
| World request | 0.131–0.141 s | 0.297–0.346 s | 0.429–0.510 s |
| `OnItemAdded` | 0.330–0.357 s | 0.495–0.531 s | 0.594–0.639 s (includes about 66 ms to identify the tome) |

The work in each step is trivial: a few keyword and list lookups and a float comparison. The cost comes from **each Papyrus call to a game function waiting for a frame synchronisation**. The step sizes (about 130–170 ms for four to eight calls each) fit about one 16.7 ms frame per call [A: frame-sync model; consistent with the data, not instrumented per call]. Debug tracing was on (`UT_DebugEnabled`), which adds trace calls.

**Other schema 18 runtime observations [V]:**
- The cancellation at a 128.6-unit displacement worked (request 6, `player_moved`), and the manual Take afterwards worked.
- On automatic replays `OnItemAdded` received the actual reference (`item_ref=FF000F0C/FF000F04 match=exact_reference`). On the manual Take it received `None` (`anonymous_stack`).
- The "yields" notification never showed on automatic pickups (`no_feedback present=False`), because the tome was already gone.

## 2. Eligibility-rule inventory (the source as it is)

The order is that of `UT_EvaluateWorldTome` and `UT_EvaluateTomeEligibility` in `UT_PlayerMonitor.psc` (the world path), and `OnItemAdded` → `UT_HandleTomePickup` (post-acquisition). **No rule is to be removed or reordered.**

| # | Rule and result | Papyrus implementation | Inputs and forms | Failure behaviour now |
| --- | --- | --- | --- | --- |
| R0 | Tome identity | `akBaseItem.HasKeyword(MagicTomeKeyword)`. World path: no reference → `unavailable-no-reference`; no base → `unavailable-no-base`; no keyword → `unavailable-not-a-tome` | Property `MagicTomeKeyword`, bound to `VendorItemSpellTome` `Skyrim.esm 000937A5` | Post-acquisition: returns silently (not acknowledged). World: unavailable |
| R1 | Mod disabled → `disabled` (Exempt) | `UT_ModEnabled.GetValueInt() == 0`. A missing global means enabled | Global `UT_ModEnabled` (`Untamed Tomes.esp`), MCM toggle | None |
| R2 | Pre-authorised (post-acquisition only) → `accept-preauthorized` | `UT_ConsumeWorldTomeGrant` (native) | Native grants | Not consumed → evaluate |
| R3 | Safe context, gate 1 → `accept-safe-context` | `UT_GetPickupContext`. Barter: `UI.IsMenuOpen("BarterMenu")`. Otherwise `UT_GetTomeLocationContext`: `player.GetCurrentLocation()`; None → `no-location` (unsafe). Then, in this order: `LocTypeDungeon` → `dungeon` (unsafe, checked **first**); `LocTypeCity` or `LocTypeTown` → `town`; `LocTypeInn` → `inn`; `LocTypeStore` → `store`; else `other`. Safe values: barter, town, inn, store | Five location keyword properties; the barter menu state | A missing keyword property skips that keyword |
| R3a | Location hierarchy | **Not traversed.** Only the current location's own keywords are tested (`Location.HasKeyword`) | — | A house or interior location without its own town, inn or store keyword is unsafe even inside a city |
| R4 | Explicit safe tome → `accept-safe-keyword` | `akBaseItem.HasKeyword(UT_TomeSafe)` | Keyword `UT_TomeSafe` (ESP) | Missing property: skipped |
| R5 | Safe context, gate 2 (the historical duplicate) → `accept-safe-context` | A repeat of R3 | As R3 | As R3 |
| R6 | Exclusion list → `accept-exclusion` | `UT_TomeExclusions.HasForm(akBaseItem)` | FormList `UT_TomeExclusions` (ESP) | Missing property: skipped |
| R7 | Quest reference → `accept-quest-reference` | `PO3_SKSEFunctions.IsQuestItem(akItemRef)`, only when `akItemRef` is not None | The reference's `ExtraAliasInstanceArray` (Papyrus Extender, §3) | No reference: skipped. Post-acquisition `akItemRef` is usually None |
| R8 | Player present, else `abort-no-player` (Unavailable) | `GetReference() as Actor`, else `Game.GetPlayer()` | The player alias | Unavailable |
| R9 | Magicka: `base Magicka ≥ threshold` → `accept-eligible`, else `reject-ineligible` | `player.GetBaseActorValue("Magicka")`, `UT_MagickaThreshold.GetValue()`. A missing global gives threshold 0 | Global `UT_MagickaThreshold` (MCM slider 0–500, step 10, default 100) | Missing global: always eligible |
| R10 | Progression observation (post-acquisition only, **not** a rule) | `UT_EnsureBaseline` and `UT_IsClearlyNonMage`, run when R9 was reached | Saved script variables | Observation only; excluded from the decision |
| R11 | Rejection side effects (post-acquisition only) | `GetItemCount` and `RemoveItem` → `reject-removed` or `reject-skipped-empty-inventory`; then `UT_TriggerDefense` | Inventory | Not part of the decision |

**MCM [V source]:** `UT_MCM` exposes exactly three globals: `UT_ModEnabled`, `UT_MagickaThreshold` and `UT_DebugEnabled`. There are no other settings. `VendorChestKeyword` is declared but unused.

## 3. Native API and thread-safety analysis

**Threads [V].** The book-activation thunk runs on game worker threads: 22952, 11040, 27868 and 28632 in this run, never the input thread 12692. The same threads run SKSE tasks and Papyrus natives. On these threads the engine itself performs the pickup (Read Or Take's `PickUpObject`) and dispatches the container-change event, so they are game-logic threads, not arbitrary pool threads. Whether two such jobs can touch the same data concurrently is unknown [A].

| Rule | Native equivalent | Evidence | Synchronous at activation? | Risk |
| --- | --- | --- | --- | --- |
| R0 tome keyword | `TESObjectBOOK::HasKeywordID(000937A5)` | [V] already used in the thunk since schema 16 without incident; [S] walks the base form's static keyword array | Yes | Low: loaded record data |
| R1, R9 globals | `TESGlobal::value` (float field) | [S] plain field | Yes | Low. A concurrent MCM write yields the old or the new value |
| R3 barter | `UI::IsMenuOpen(BarterMenu)` | [S] `menuMap.find` plus the `OnStack` flag, **no lock** | Yes, but irrelevant at activation (no world activation happens in barter) | Medium off the main thread [A]. For post-acquisition calls from Papyrus it matches the current `UI.IsMenuOpen` |
| R3 location | `PlayerCharacter::currentLocation` (field, AE offset `11C8`), or the engine `GetCurrentLocation` (AE 19812) | [S] field. The engine function's body was not analysed | Yes if the field is used | Medium [A]: equality with Papyrus `GetCurrentLocation` is unverified, and the field changes on location transitions |
| R3 keywords | `BGSLocation` → `BGSKeywordForm::HasKeyword` | **[V] static:** in `SkyrimSE.exe` 1.7.104, `BGSLocation`'s keyword-form vtable (AE 189920) has the same slot 4 (`HasKeyword`, RVA `1D89E0`) as base `BGSKeywordForm` (AE 187679). No override, so there is no inherited-keyword behaviour in the virtual. Whether the Papyrus `HasKeyword` native has its own location special case is **unverified** | Yes | Medium until the shadow comparison: a semantic mismatch is possible |
| R3a hierarchy | `BGSLocation::parentLoc` / `IsParent` | [S] pointer walk | Yes | n/a: not a current rule. Do not add one silently |
| R4 safe keyword | `TESObjectBOOK::HasKeyword(UT_TomeSafe)` | [S] static data | Yes | Low |
| R6 exclusions | `BGSListForm::HasForm` | [S] walks `forms`, then `scriptAddedTempForms`, **no lock** | Yes | Low–medium: a concurrent Papyrus `AddForm` could race. No Untamed Tomes script modifies the list |
| R7 quest reference | `ExtraDataList::GetByType<ExtraAliasInstanceArray>` (takes the list read lock [S]), then `xAliases->lock` read lock, `alias->IsQuestObject()`, else `TESObjectREFR::HasQuestObject` (AE 19627) | [S] the Papyrus Extender `IsQuestItem` source (master `src/Papyrus/Functions/ObjectReference.cpp`) does exactly this, and CommonLib exposes every piece | Yes | Low–medium: engine locks are used; `HasQuestObject`'s body was not analysed. **Improvement:** at activation the world reference is always available, so R7 is evaluated on the actual reference |
| R8 player | `PlayerCharacter::GetSingleton()` | [S] singleton | Yes | Low |
| R9 Magicka | `player->AsActorValueOwner()->GetBaseActorValue(ActorValue::kMagicka)` | [S] engine vfunc; reads only | Probably | Medium [A]: engine function on a worker thread; equality with Papyrus `GetBaseActorValue("Magicka")` is unverified |

Nothing in the inventory needs main-thread-only state, menus, the Papyrus VM or a latent call. **The smallest remaining asynchronous dependency for the decision is none.** Only feedback (shader, notification, defense) needs to be scheduled.

**Expected native cost [A, from the code].** A dozen field reads, three short keyword-array walks, one short list walk and one engine vfunc: microseconds, well below the 16.7 ms target. **It must be measured** (§10). No frame-time claim is made.

## 4. Candidate architectures

| Criterion | A. Fully native evaluator (Papyrus calls it too) | B. Optimised Papyrus | C. Hybrid (native fast path, Papyrus fallback) |
| --- | --- | --- | --- |
| Correctness | One implementation for both paths. It must be proven equal to the current Papyrus by shadow comparison | Unchanged rules | Two paths that must agree; fallback divergence possible |
| Latency, world | Decision inside the original activation (estimated µs) | Each Papyrus game call costs about a frame. Even after dropping gate 2 (about 165 ms) and tracing, roughly 6–10 frame-synced calls remain: **about 250–400 ms [A]**, so never one frame | Fast path as A |
| Latency, post-acquisition (chest, Take All, other mods) | One native call from Papyrus (about one frame sync) instead of about 0.6 s | About 0.3–0.4 s | As A, or slower on fallback |
| Complexity | Removes the request, answer, timeout, replay and continuation machinery (§8) | Keeps the whole schema 18 state machine | Keeps all of schema 18 plus a fast path: the most code |
| Compatibility | Accepted activations are **the player's own activation**: Read Or Take hotkey, crime and `OnActivate` all happen once and normally. No replay | Replay caveats remain (hotkey lost, two activate events) | Mixed |
| Maintenance | Rules in C++. Papyrus keeps the configuration (ESP bindings), MCM, feedback and effects | Rules in Papyrus | Rules in both: the anti-goal |
| Failure behaviour | Bindings not registered → unavailable → veto with a notice (as `papyrus_not_ready` today) | As schema 18 | As schema 18 |

**Recommended: A.** Option B cannot reach the target by construction. Option C keeps every cost of the current design and adds a second rule implementation.

## 5. Proposed shared eligibility interface

- **The configuration stays in the ESP.** Papyrus passes its bound forms to native code on `OnInit` and `OnPlayerLoadGame`, just as it registers the handshake handler today:

  `Function UT_RegisterEligibilityForms(GlobalVariable akEnabled, GlobalVariable akThreshold, Keyword akMagicTome, Keyword akTomeSafe, FormList akExclusions, Keyword akCity, Keyword akTown, Keyword akInn, Keyword akStore, Keyword akDungeon) global native`

  Native code stores the form pointers (forms are permanent) and reads the **values** live, so MCM changes apply immediately. Missing properties keep their current meaning: skipped, or the defaults in §2.
- **One evaluator** in a pure header: `EligibilityDecision Evaluate(const EligibilitySnapshot&)`. The snapshot holds the gathered values:
  - enabled, threshold, base Magicka;
  - the tome's keywords and exclusion membership;
  - the reference's quest-alias flag;
  - location keyword flags, and barter-open.

  The result carries the **same outcome strings** as today (`disabled`, `accept-safe-context`, `accept-safe-keyword`, `accept-exclusion`, `accept-quest-reference`, `accept-eligible`, `reject-ineligible`, `abort-no-player`, `unavailable-*`) plus the inputs, for logging. Gate 2 is kept for fidelity; at native speed it is redundant but harmless.
- **Papyrus entry point:** `String Function UT_EvaluateEligibility(Form akBase, ObjectReference akRef) global native`. `UT_EvaluateTomeEligibility` becomes a thin wrapper, so `UT_HandleTomePickup`, removal, the trap and progression observation are untouched. The debug trace moves into the native log, since `UT_DebugEnabled` is one of the registered globals.

## 6. Post-acquisition correlation with synchronous acceptance

- **Accepted at activation:** the thunk forwards immediately, inside the original activation. The existing `ForwardContext` binds the grant to the inventory event that fires synchronously in that call [V since schema 17]. The grant carries a decision ID instead of a request ID. `OnItemAdded` consumes it (`accept-preauthorized`), so **a successful world acquisition is never rejected afterwards**. Both safeguards stay: grants and exact-reference matching.
- **Identical copies:** unchanged. Exact match when `akItemRef` is present, anonymous stack otherwise (Inv. 20 §4).
- **Deferred or modded transfers:** no inventory event during the call means no grant. `OnItemAdded` then calls the same native evaluator (now about one frame) and gets the same result unless the state changed in between, which is the current behaviour too.
- **Premature teaching:** unchanged. Unified read enforcement denies the Read Or Take world READ while the acquisition is pending [V]. Inventory reads are forwarded to DEST [V].
- **Rejected:** veto with no Read Or Take call and no reference change [V veto mechanism]. Feedback is scheduled through the existing ModEvent to Papyrus, or a native shader task. A rejection cooldown (2 s) is still needed to stop feedback spam on repeated presses.

## 7. Compatibility and gameplay semantics

| Area | Effect of Option A |
| --- | --- |
| Read Or Take | Called exactly once, in the original input context: the alternate-action hotkey works again (schema 18's replay loses it) |
| DEST 1.2.3, DESTified, read enforcement | Unchanged |
| Ordinary and skill books, non-player activation | Unchanged (the scope filter) |
| Owned or stolen tomes | Accepted → the player's own activation, so normal crime handling. Schema 18's ownership exclusion is no longer needed. Rejected → vetoed before any crime is committed (as now) |
| Safe-location exemption | Evaluated at activation time instead of 0.1–0.6 s later. Same rule (R3/R3a), more accurate timing |
| Quest-protected tomes | Better: the actual world reference is always available |
| Container and Take All | Not world activations. They stay on `OnItemAdded`, but become faster through the native call |
| Other activation mods (QuickLoot) | As above: there is no book `Activate`, so the post-acquisition path applies |
| Mods that replace slot `0x37` later | As now: detected (`bypassed=1`) |

## 8. Expected complexity change

**Could be removed** once Option A is proven:
- the Papyrus request and answer (`UT_WorldTomeRequest`, `OnUTWorldTomeRequest`, `UT_AnswerWorldTomeRequest`);
- Pending, TimedOut and Unavailable states, the timeout, retry and capacity cap;
- the 30 s authorisation window, the Authorized and Continuing states, `BeginContinuation`/`EndContinuation`;
- replay scheduling, the movement, distance, menu and ownership cancellation, and the "Take it again" fallback;
- the `WorldTomeManualTake` marker, and request generations for answers. Session checks stay for queued feedback.

**Must remain:**
- the scope filter, the veto, and the rejection cooldown;
- `ForwardContext` grants and exact-reference matching;
- session reset on load;
- the bindings-not-registered → veto-with-notice policy;
- unified read enforcement, DEST coexistence, and diagnostics;
- the infrastructure notice.

The handshake table shrinks to a per-reference rejection cooldown.

## 9. Unknowns requiring runtime experiments

1. **Semantic equality.** Do native R3, R7 and R9 give the same results as Papyrus `GetCurrentLocation` with `HasKeyword`, `IsQuestItem` and `GetBaseActorValue("Magicka")`, in a dungeon, a town, an inn, a store, an interior house, the wilderness (no location) and while bartering?
2. **Worker-thread safety.** Do reads of the base actor value, the player's location field and the alias array behave on activation threads? A crash-free run is supporting evidence, not proof.
3. **Native cost.** Microseconds per evaluation, measured with a high-resolution timer.
4. **Transition timing.** Does the player's location field update at the same moment Papyrus observes the change?
5. **Exemption data.** R4 and R6 need test data; vanilla tomes carry no `UT_TomeSafe` and the exclusion list may be empty. Inspect the ESP.

## 10. Recommended next implementation task

**Task 15B: a shadow native evaluator. No behaviour change, no schema switch of the world path.**

1. Add `UT_RegisterEligibilityForms` and the pure evaluator with offline tests that mirror R0–R9 exactly, including the gate order and the missing-property defaults.
2. **At every in-scope activation:** compute the native decision synchronously and log the result, inputs and microseconds. **In every Papyrus evaluation:** log the native result for the same inputs next to the Papyrus outcome (`agree=true/false`).
3. Run the Inv. 20 §9 sessions plus the location set from §9.1. **Acceptance:** 100% agreement, no crashes, and native cost well below 1 ms.
4. Only then, as Task 15C, switch the world path to synchronous decisions and retire the components listed in §8, keeping the schema 18 build as rollback.

This directly answers the open evidence gaps (§9) and does not touch acquisition behaviour.
