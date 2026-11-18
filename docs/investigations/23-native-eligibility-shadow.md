# Investigation 23 — Native eligibility shadow validation

## Status

Schema 19 adds a **shadow** native eligibility evaluator. It decides nothing: the schema 18 Papyrus handshake stays authoritative, and the shadow creates no grants, effects or authorisations.

| Item | State |
| --- | --- |
| Baseline (committed) | native `961f0c1` and Papyrus `b046740` on `dev/untamed-tomes-v2` |
| Builds | native and Papyrus build cleanly |
| Offline suites | 11 of 11 pass, including the new `native_eligibility` parity suite |
| Deployed DLL | **Schema 20** (Task 15C.1, §18): `39ACDF7F13B554BFC87E24DDCB2073C8102C57D3225998DE32E4828A0488D2BE`. The schema 19 DLL was `15349CA4…` |
| Deployed PEX | `8BD9388234B6E54FE28A8FDE10C4EEE45562ECD9346DB872132E5B9C1B3E27B6` (unchanged in schema 20) |
| Preserved | `task15b-preservation/` (schema 18 rollback) and `task15c1-preservation/` (schema 19 rollback), each with a SHA-256 manifest |
| Commits | none for Tasks 15B and 15C.1 |

**Runtime (18 November 2026, Task 15B.2):** 13 comparisons, 13 matches, with no mismatch, unavailable or error (§5). Native evaluation took 4.4–9.3 µs (§6).

**One confirmed defect, found by the shadow logs:** with the mod disabled, the world handshake refused the tome (§11). It is fixed in schema 20, built and tested offline but not yet tested in game (§18). Container, Take All and barter acquisitions remain unvalidated (§12). Sections 11–17 cover Task 15B.2; §18 covers Task 15C.1.

## 1. Architecture

- **`src/NativeEligibility.h`** is a pure evaluator over a `Snapshot`. It uses the same outcome and context strings as Papyrus and mirrors Inv. 22's R0–R9 in order:
  - the world entry gives `unavailable-*` outcomes for identity failures, and the post-acquisition entry returns silently (`not-evaluated`);
  - then `disabled`, context gate 1, `UT_TomeSafe`, context gate 2, exclusions, the quest reference (only with a reference), the player, then Magicka ≥ threshold.
- **`GatherEligibility`** (`main.cpp`) fills the snapshot from the registered forms, timing four segments: configuration, location, Magicka and quest.
- **Activation-time shadow:** every in-scope activation (not replays) that starts a new request is evaluated on its worker thread. The decision is stored on the request record and logged as `eligibility_shadow_decision source=activation` with its inputs and timings. When Papyrus answers, `UT_AnswerWorldTomeRequest` compares it (`eligibility_shadow source=activation`). Only answers the handshake applied are compared; stale or duplicate ones aren't decisions.
- **Papyrus-boundary shadow:** `UT_ShadowEligibility(path, base, ref, papyrusOutcome, requestId, papyrusInputs)` is called immediately after the Papyrus evaluator, so no latent call separates the two:
  - in `OnUTWorldTomeRequest`, after `UT_EvaluateWorldTome` (`papyrus_world`);
  - in `UT_HandleTomePickup`, after `UT_EvaluateTomeEligibility` (`papyrus_post`): chest, Take All, Read Or Take world pickups of out-of-scope tomes, and any other `OnItemAdded` acquisition;
  - in the `OnItemAdded` disabled branch (`papyrus_post`, outcome `disabled`).

  It evaluates natively on the VM thread and logs one row.
- **Papyrus input recording:** `UT_EvaluateTomeEligibility` is now a wrapper around the unchanged `UT_EvaluateTomeEligibilityRules`. It records gate 1 and gate 2 contexts, Magicka and threshold into scalar script variables and formats them as `UT_EvalLastInputs` (`ctx1= ctx2= magicka= threshold= overlap=`). Evaluations that interleave are flagged with `overlap=True`.
- **Counters:** match, mismatch, unavailable and error per source (`activation`, `papyrus_world`, `papyrus_post`). Each row carries the running totals, and `eligibility_shadow_summary` is logged at every session marker.
- **What is not compared:** the `accept-preauthorized` grant branch, because it is not an evaluation. The world request was already compared twice.

**Latency impact on schema 18:**
- both new natives are registered tasklet-callable, so Papyrus pays no frame sync for them;
- at activation the shadow costs one gather (measured in §6);
- the wrapper adds about seven script variable assignments and one string concatenation.

## 2. Rule-by-rule parity (offline)

`tests/native_eligibility.cpp` has 58 compile-time assertions. "Runtime" means agreement in an actual game session (§5).

| Rule | Behaviour reproduced | Offline | Runtime |
| --- | --- | --- | --- |
| R0 world identity | No reference → `unavailable-no-reference`; no base or no `MagicTomeKeyword` property → `unavailable-no-base`; no keyword → `unavailable-not-a-tome`; identity outranks disabled | ✓ | Pending |
| R0 post identity | Silent return (`not-evaluated`, never compared) | ✓ | Pending |
| R1 disabled | `GetValueInt()` truncation (0.9 and −0.5 are disabled, 2 is enabled); a None global means enabled; outranks every exemption | ✓ | Pending (MCM) |
| R3 barter | Outranks location, even a dungeon | ✓ | Pending |
| R3 location | No player → `no-player`; no location → `no-location`. Dungeon is checked **before** city and town (a dual-keyword location is a dungeon); city or town → `town`, then inn, then store, else `other`; a missing keyword property is skipped | ✓ | Pending |
| R3a current location only | A house with none of the five keywords → `other`, so unsafe | ✓ | Pending |
| R4 `UT_TomeSafe` | Outranks gate 2, exclusions, quest and Magicka; a safe context still comes first | ✓ | Untested in game: needs plugin data |
| R5 gate 2 | Evaluated twice from one snapshot | ✓ | Pending (§7: drift) |
| R6 exclusions | `HasForm`; None skipped | ✓ | Untested in game: needs list entries |
| R7 quest reference | Only with a reference; after exclusions | ✓ | Untested in game: needs a quest-aliased tome |
| R8 player | Not safe at R3, so the evaluation reaches `abort-no-player` (unless R7) | ✓ | Not practical |
| R9 Magicka | `>=`; a missing threshold global means 0; a present threshold of 0 also accepts everything | ✓ | Pending |

## 3. Configuration synchronisation

- **Source of truth:** the monitor's ESP-bound properties. Nothing is hardcoded, so there is no load-order-dependent FormID.
- **Registration:** `UT_RegisterWorldTomeHandshake`, on `OnInit` and `OnPlayerLoadGame`, now also calls `UT_RegisterEligibilityForms` with all ten properties:
  - `UT_ModEnabled` and `UT_MagickaThreshold`;
  - `MagicTomeKeyword`, `UT_TomeSafe` and `UT_TomeExclusions`;
  - the five location keywords.

  The call is logged as `eligibility_forms_registered`, with every FormID, the size of the exclusion list and the current global values.
- **Missing configuration versus a missing property:**
  - Registration not received in this session means the native result is **unavailable**, and the comparison is counted separately, never as a match.
  - A property registered as None means the rule is skipped, exactly as in Papyrus. A None threshold is the intentional "threshold 0" case and is logged as `threshold=none`.
- **Live values:** globals are read at each evaluation, so MCM changes take effect at once. The activation decision row logs the threshold it used.
- **Lifetime:**

  | Event | Effect |
  | --- | --- |
  | Pre-load | Registration cleared |
  | Load | `OnPlayerLoadGame` registers again, about 0.1–0.2 s after the post-load message in earlier runs |
  | New game | `OnInit` registers. Registration isn't cleared at `kNewGame`, but the forms are the same records |
  | Revert | As pre-load |
  | Shutdown | Nothing persisted; it is process memory only |

## 4. Thread-safety evidence

The activation thunk runs on game worker threads, and the Papyrus-boundary call runs on the VM thread. Both perform only the reads below. No operation without a justification is executed. **A crash-free run is supporting evidence, not proof.**

| Read | Evidence | Kind |
| --- | --- | --- |
| Globals, keyword and list forms (pointers and values) | Loaded record data; `TESGlobal::value` is a float field | CommonLib source |
| Book and location keywords | `BGSKeywordForm::HasKeyword` (RVA `1D89E0`): a virtual default-keyword call (slot 5), then an array walk with **no lock**. `BGSLocation` does not override it (same slot 4 in both vtables, Inv. 22) | Disassembly |
| Player location | `PlayerCharacter` runtime data `currentLocation`: a pointer field. Locations are permanent forms. The engine `GetCurrentLocation` (AE 19812) is **not** used | CommonLib layout |
| Barter menu | `UI::IsMenuOpen`: `menuMap.find` and the `OnStack` flag, **no lock**. The map is filled when menus register at startup | CommonLib source; remaining unknown U3 |
| Base Magicka | `Actor::GetBaseActorValue` (`6C4EF0`, AE 38464, slot 3 of PlayerCharacter's `ActorValueOwner` vtable AE 208050). Its storage lookup (`6E2DE0`, AE 39016) takes `BSReadWriteLock::LockForRead` and `UnlockForRead` (AE 68233 and 68239), so the engine guards this data for concurrent readers. Two callees (`4435B0` and its callees) were not fully analysed | Disassembly; partial |
| Quest reference | `ExtraDataList::GetByType` takes the list's read lock (CommonLib source); `ExtraAliasInstanceArray::lock` is held for read during iteration, the same as Papyrus Extender `IsQuestItem` (master, `ObjectReference.cpp`); `BGSBaseAlias::IsQuestObject` is a flag test | Source |
| Papyrus Extender's `HasQuestObject` fallback | `TESObjectREFR::HasQuestObject` (`2E5A60`, AE 19627) does anything only when the base form type is `0x1C` (container) or `0x2B` (NPC). For a BOOK it returns false, so for tomes the fallback contributes nothing and is not called | Disassembly |
| Exclusion list | `BGSListForm::HasForm` walks `forms` and `scriptAddedTempForms` with **no lock**. No Untamed Tomes script modifies the list; another mod's `AddForm` could race | CommonLib source; U4 |
| Reference lifetime | At activation: the engine-supplied target, used during the call only. At the Papyrus boundary: the reference the VM passes in. No pointer is stored; the request record holds values only | Design |

**Remaining unknowns:**
- U1: the unanalysed `GetBaseActorValue` callees.
- U2: equality of the `currentLocation` field with Papyrus `GetCurrentLocation`.
- U3: unlocked `menuMap` reads.
- U4: an exclusion-list race with other mods.
- U5: whether the Papyrus `HasKeyword` native special-cases locations.

U2 and U5 are exactly what the runtime comparison detects.

## 5. Runtime comparison results

**Session:** 18 November 2026, 09:17–09:22, schema 19. The logs are preserved as `task15b2-preservation/schema19-session-{native,papyrus}.log` with SHA-256 sums.

**Registration [V]:** `eligibility_forms_registered` arrived 187 ms after post-load in session 2 and 126 ms after post-load in session 4. It carried:
- `enabled=0F000802` and `threshold=0F000804`;
- `magic_tome=000937A5` and `tome_safe=0F000805`;
- `exclusions=0F000806` (`exclusions_count=0`);
- city `00013168`, town `00013166`, inn `0001CB87`, store `0001CB86`, dungeon `000130DB`.

| Source | Match | Mismatch | Unavailable | Error |
| --- | --- | --- | --- | --- |
| activation | 6 | 0 | 0 | 0 |
| papyrus_world | 6 | 0 | 0 | 0 |
| papyrus_post | 1 | 0 | 0 | 0 |

| Request | Situation | Native = Papyrus | Native inputs |
| --- | --- | --- | --- |
| 1 | Bleak Falls Barrow, threshold 150 | `reject-ineligible` | dungeon, Magicka 100 |
| 2 | Same, threshold 200 (MCM) | `reject-ineligible` | threshold 200.00 |
| 3 | Same, threshold 100 | `accept-eligible`, then continued and picked up (`replayed consumed=true`) | threshold 100.00 |
| 4, 5 | Mod disabled (MCM) | `disabled` (Papyrus `Disabled`) | `enabled=0.00` |
| — | `OnItemAdded` while disabled (input thread 8520, no source: consistent with console `additem`) | `disabled` | `papyrus_post` |
| 6 | Riverwood (cell `00009712`), threshold 150 | `accept-safe-context`, context `town`; continued and picked up | `kw_town=1` |

The Papyrus traces show the same contexts and thresholds (`context=Dungeon`/`Town`; thresholds 150, 200, 100). After the reload in session 4 the threshold was 150 again, because the globals are saved with the save game.

## 6. Native latency (measured, µs)

| Source | n | Min | Median | Max |
| --- | --- | --- | --- | --- |
| activation (worker thread) | 6 | 4.4 | 5.65 | 9.3 |
| papyrus_world (VM thread) | 6 | 5.0 | 5.65 | 8.1 |
| papyrus_post | 1 | 6.7 | — | — |

- **Segments, activation, ranges:**

  | Segment | µs |
  | --- | --- |
  | Configuration | 0.9–1.5 |
  | Location | 2.7–6.1 |
  | Magicka | 0.3–1.3 |
  | Quest | 0.3–0.5 |

- **p95:** not meaningful with six samples; it equals the maximum.
- **Comparison:** the Papyrus evaluation of the same requests took about 430–590 ms (traces), so native is roughly five orders of magnitude faster.
- **Location share:** the location segment dominates, because it evaluates five keyword lookups on the location.

## 7. Mismatch analysis

**Expected categories:**

- **True rule divergence.** A native rule differs from Papyrus. This blocks enforcement and must be fixed in the evaluator.
- **Timing drift.** The activation-time snapshot is taken about 100–700 ms before Papyrus reads its own state. The Papyrus-boundary snapshot follows Papyrus immediately, but the gate 1 → gate 2 interval in Papyrus is about 165 ms.
  - Signs of drift: `papyrus_inputs` shows `ctx1 ≠ ctx2`, or the activation and boundary native results differ.
  - Drift is not a rule divergence. It shows that native evaluation at activation is *more* precise in time.
- **Overlap.** `overlap=True` means the recorded Papyrus inputs may belong to another evaluation. The outcome comparison stays valid; only the diagnostic inputs are unreliable.
- **Unavailable.** Registration was missing (before `OnPlayerLoadGame` registers), or Papyrus produced no outcome. These are counted separately.

Every mismatch row logs:
- the source;
- the request, session and thread;
- the reference and base;
- both outcomes and the native context;
- the full native inputs: barter, player, location, the five keyword flags, tome keyword, tome-safe, excluded, quest reference, enabled, Magicka, threshold;
- the Papyrus inputs.

## 8. Recommendation

*Superseded by §17.*

**Original recommendation (Task 15B):** do not enable native enforcement yet. It needs:
1. a runtime session with 100% agreement for every source in the testable matrix;
2. measured native latency well under 1 ms;
3. no errors or crashes;
4. a decision on U1 and U3.

**Status after the 18 November session:**
- 1 is met for the world path only.
- 2 and 3 are met.
- 4 is resolved in §13.

## 9. Runtime test plan (next session)

**Markers:** unchanged (`WorldTomeHandshake`, `EnforceTomeReads`, `DebugTrap`, `FireTrap`). Keep `UT_DebugEnabled` on, so the Papyrus traces are available too.

**Startup checks:**
- `observer_load schema=19`;
- after loading the save, `eligibility_forms_registered` with non-zero FormIDs for the properties the ESP binds.

| # | Where and how | Compare |
| --- | --- | --- |
| 1 | Bleak Falls Barrow, threshold 150, base Magicka 100: take Firebolt (`player.placeatme 000A26FD`) | activation and papyrus_world `reject-ineligible`, context `dungeon` |
| 2 | Same, threshold 100 through the MCM | `accept-eligible`; the activation decision row shows `threshold=100.00` |
| 3 | Two Firebolt copies, one Take each | Two requests, each compared |
| 4 | Take a non-Firebolt tome (`000A2705`) and a chest tome (`additem` into a chest, then Take; also Take All) | `papyrus_post` rows |
| 5 | Riverwood (town), the Sleeping Giant Inn, Riverwood Trader (store) | `accept-safe-context`, contexts `town`, `inn`, `store` |
| 6 | An interior house (for example a Riverwood house) | Whatever Papyrus says; context `other` expected if the location has none of the keywords |
| 7 | Wilderness outside Riverwood | `no-location` or the hold location, matching Papyrus |
| 8 | MCM: disable the mod, take a Firebolt and add one with `additem` | `disabled` from both paths |
| 9 | Save and load | `eligibility_shadow_summary`, then `eligibility_forms_registered` again |
| 10 | Buy a tome from a vendor (barter) | `papyrus_post` `accept-safe-context`, context `barter` |

**Untested without plugin data:** `UT_TomeSafe`, exclusions, a quest-protected tome, a dual dungeon/town location (unless one is found in game), and a missing threshold global.

Preserve `UntamedTomesSKSE.log` and `Papyrus.0.log` after the session.

## 10. Rollback

| Goal | How |
| --- | --- |
| Remove the shadow | Copy `pre-task15b-schema18.dll`, `.pdb` and `pre-task15b-UT_PlayerMonitor.pex` from `task15b-preservation/` into the MO2 mod, or check out `961f0c1` and `b046740` |
| Keep the build | The shadow is passive: it changes no decision |

## 11. Disabled-mod behaviour: a confirmed defect

**Observed [V].** With `UT_ModEnabled = 0`, requests 4 and 5 were answered `outcome=Disabled`. The handshake classified that as `category=unavailable status=unavailable`, and the world tome was **refused**: `retry_after_unavailable`, no pickup. Investigation 19 specifies `disabled` → Exempt, so this is a regression, not intent.

**Root cause [V source].**
- `WorldTomeHandshake::ClassifyOutcome` compares case-sensitively (`text == "disabled"`, plus the `accept-` and `reject-` prefixes).
- Papyrus interns strings case-insensitively across **all** scripts. The first casing loaded wins: this load order delivers `Disabled`, as it delivered `Dungeon` and `Rejected` earlier.
- The ledger acknowledgement classifier and the shadow comparison are already case-insensitive, which is why the shadow reported a match.

**Latent scope.** Any outcome string could arrive capitalised:
- an `Accept-*` arriving capitalised would also become Unavailable, so the tome is protected but needs a retry;
- a capitalised `Reject-*` would also become Unavailable, so it stays protected but **without** refusal feedback.

No unsafe authorisation is possible: unknown strings never authorise.

**Second disabled-state issue [V source; runtime consequence inferred].** Unified read enforcement does not consult `UT_ModEnabled`. With the mod disabled, Read Or Take's world READ is still denied while the ledger shows a pending acquisition. The READ becomes a Take, so the mod still changes behaviour when it is off. Inventory reads are not affected (`no_pending_acquisition`).

**Recommended correction (small, isolated; not applied during shadow validation):**
1. Make `ClassifyOutcome` case-insensitive, reusing `NativeEligibility::EqualsIgnoreCase` with a prefix variant. Add tests for `Disabled`, `Accept-Eligible` and `REJECT-INELIGIBLE`.
2. Have read enforcement forward every read when the registered enabled global is 0, that is, when the mod is disabled.
3. In Task 15C, `disabled` at activation forwards synchronously, so a disabled mod stops intercepting world tomes entirely.

**Compatibility:** item 2 restores Read Or Take and DESTified behaviour when the mod is disabled; there is no effect while enabled.

## 12. Container, Take All and barter acquisition

**Status: not exercised in schema 19.** The only `papyrus_post` sample was a disabled, sourceless addition.

**What the code establishes [V source]:**
- Container Take, Take All and purchases do not call book `Activate`, so the world hook and its activation shadow never run for them.
- `OnItemAdded` runs for every tome addition. While enabled, it calls `UT_HandleTomePickup`, which runs the shared evaluator and then `UT_ShadowEligibility(1, …)`. So the `papyrus_post` shadow **does** run for these paths.
- `akSourceContainer` is passed to `OnItemAdded` and is logged in the Papyrus debug traces. The native container sink also logs `source=` and the ledger.
- Barter: `UT_GetPickupContext` returns `barter` while `BarterMenu` is open, so `accept-safe-context` applies.

**Historical runtime evidence (earlier schemas, not the shadow):**
- Inv. 14 (schema 10): container-side read denial was runtime-verified, with 8 denials and `original_invoked=0`.
- Inv. 17 (schema 13): a chest Take produced `triggered … container=TRUE`. The menu deferral was then broken by the array defect, which was later fixed.

None of these recorded a schema 19 eligibility comparison.

**Limitations of post-acquisition enforcement** (separate from parity):
- **The tome is destroyed.** An ineligible chest tome is removed with `RemoveItem(base, 1, true)`. It is gone, which contradicts the principle "never destroy a protected tome". The interim option from Inv. 13 is to return it to `akSourceContainer`.
- **Late decision.** The decision is made about 0.6–1.2 s after the transfer: the Papyrus evaluation plus the frame-synced calls (Inv. 22 §1).
- **No original reference.** `akItemRef` is usually None, so the quest-reference exemption rarely applies.
- **Read enforcement.** It prevents premature learning while the acquisition is pending. Container-side reads are denied separately (Inv. 14).

**Test procedure (enabled; once at threshold 150 and once at threshold 100):**
1. `additem 000A2705 1` into a dungeon chest, then use the chest's individual Take.
2. Two tomes in a chest, then Take All.
3. Buy a spell tome from a court wizard or Farengar.

For each, record:
- the `papyrus_post` row (`result=`, `native=`, `papyrus=`);
- the `ledger_ack` outcome;
- `player.getitemcount` afterwards;
- the Papyrus trace `source=`;
- whether a container-side read is denied.

## 13. Thread-safety assessment

| Read | Guarantee | Kind | Verdict for synchronous enforcement |
| --- | --- | --- | --- |
| Configuration form pointers | Copied under our own mutex, which nests nothing. Forms are permanent records | Design | Safe |
| Global values (enabled, threshold) | A single aligned float, written by the MCM on the VM thread. A read sees the old or the new value | Static (field) and runtime (propagated 150 → 200 → 100 → 150, §5) | Safe |
| Book keywords | Record data, `HasKeyword` walk with no lock (disassembly) | Static | Safe |
| Player `currentLocation` | An aligned pointer written by the engine on location change; locations are permanent | Static (layout) and runtime (dungeon and town parity) | Safe. May be one update stale at a transition, which matches Papyrus timing |
| Location keywords | Record data; `HasKeyword` is not overridden, with no lock | Static and runtime | Safe unless a mod edits location keywords at runtime (rare; data-load distributors run earlier) |
| Exclusion list | `forms` and `scriptAddedTempForms`, **unlocked**. Papyrus `AddForm` could reallocate the array during a walk | Source | **Unresolved.** Fix: copy the list into an immutable vector at registration (each load). No Untamed Tomes script modifies it, so semantics are unchanged |
| Quest aliases | `ExtraDataList` read lock plus `ExtraAliasInstanceArray::lock` read lock (the engine's own locks, the same pattern as Papyrus Extender). We hold no other lock while waiting, so there is no lock-order inversion | Source | Safe. Reader-only use of engine locks; deadlock needs a lock held by us, and there is none |
| Barter state | `UI::menuMap` lookup, **unlocked** | Source | **Unresolved on worker threads.** Fix: keep an atomic `barterOpen` flag from the existing `MenuOpenCloseEvent` sink. A world activation inside barter is not expected anyway |
| Base Magicka | `Actor::GetBaseActorValue` (`6C4EF0`) reads actor-value storage under the engine's `BSReadWriteLock` read lock (`6E2DE0` → AE 68233/68239). For derived values it also calls an optional per-value callback (`4435B0` → `[info+68h]`, then `445550`/`445C30`, whose callees AE 68115, 68121 and 68160 are unnamed) | Disassembly, partial; runtime parity in all 6 samples | Accept with residual risk: the storage path is engine-locked. The derived-value branch is unanalysed but read-only by name and structure |
| Reference | At activation, the engine-supplied target, used during the call only; no pointer is stored | Design | Safe |

**Blockers for synchronous enforcement:** the barter and exclusion-list reads. Both have the simple replacements described above. Everything else is backed by engine locks, permanent forms or aligned single-word fields. Six crash-free samples support this, but they are not proof.

## 14. Configuration synchronisation checks

| Check | Result |
| --- | --- |
| Threshold change applies immediately | **[V]** 150 → 200 → 100 within one session, with each activation using the new value |
| Enabled change applies immediately | **[V]** `enabled=0.00` on the next activation |
| Registration after save and load | **[V]** both loads; cleared at pre-load |
| Stale configuration after reset | **[V by design and log]** registration is cleared at pre-load. The globals are save-game values, so the reload restored 150 |
| Missing optional configuration | **Untested:** every property was bound in this ESP. Offline tests cover the None semantics |
| Missing required configuration | Papyrus semantics: a missing threshold global means threshold 0, so **everyone is eligible**. That would silently authorise. For Task 15C: if `MagicTomeKeyword`, the threshold or the enabled global is not registered, native enforcement **declines** and falls back to the schema 18 handshake. Native code never authorises on incomplete configuration, and Papyrus semantics are not changed |

**Who owns what:**
- **ESP globals:** player-facing values that are saved per game (enabled, threshold).
- **ESP keywords and FormList:** exemption data.
- **Native code:** the form registry, an immutable exclusion snapshot, the barter flag, and the evaluator.
- **Marker files:** stay developer-only.

## 15. Task 15C proposal: opt-in synchronous native enforcement (Firebolt world tome)

1. **Prerequisite fixes (isolated, tested):**
   - case-insensitive `ClassifyOutcome` (§11);
   - read enforcement forwards when the mod is disabled;
   - the immutable exclusion snapshot and the atomic barter flag (§13).
2. **Opt-in marker:** `UntamedTomes.NativeWorldEligibility`. Without it the build behaves as schema 19, so **rollback is removing the marker**. The schema 18 handshake stays compiled and in use as the fallback.
3. **Thunk flow** (in scope: player, Firebolt, live target, not a continuation):
   - **Configuration check:** if the forms are not registered, or a required form is missing, use the schema 18 handshake for this activation (logged `fallback=handshake reason=…`).
   - **Evaluate natively**, synchronously, as now.

   | Native result | Action |
   | --- | --- |
   | `accept-*` or `disabled` | Forward **once, now**, inside the original activation. Read Or Take and its hotkey, crime and `OnActivate` all run normally, with no replay |
   | `reject-ineligible` | Veto (return false). Record the per-reference cooldown entry. Post a feedback task to Papyrus, the existing refusal pulse and notification, through a new `UT_WorldTomeRefused` ModEvent carrying only the reference. The decision does not wait for it |
   | `unavailable-*` or `abort-no-player` | Use the schema 18 handshake (protective) |

4. **Post-acquisition and correlation:**
   - An accepted forward sets `ForwardContext` with a decision ID instead of a request ID, so the existing grant binding and `accept-preauthorized` prevent a second rejection.
   - Exact-reference matching is unchanged.
5. **Kept:**
   - the handshake table, as the fallback and for the rejection cooldown;
   - `Continuing` and replay, which only run on the fallback path;
   - all non-world behaviour, unchanged, with the `papyrus_post` shadow kept.
6. **Diagnostics:** `native_world_decision decision=forward|veto|fallback reason= us=`, with session and reference correlation. The world parity shadow is no longer produced on this path, because Papyrus no longer evaluates world tomes there.
7. **Tests:**
   - offline: the decision-to-action mapping, fallback on missing configuration, cooldown, grant binding on a synchronous forward;
   - in game: the existing matrix, plus disabled → immediate pickup, plus a Read Or Take READ with the hotkey preserved.
8. **Later, after it passes:** widen the scope to all tomes, then retire the async path for world tomes.

## 16. Configuration UI recommendation

**Current MCM (`UT_MCM`, SkyUI) [V source]:**

| Setting | Global | Classification |
| --- | --- | --- |
| Enable Untamed Tomes | `UT_ModEnabled` | Player-facing |
| Required Magicka (0–500, step 10, default 100) | `UT_MagickaThreshold` | Player-facing balance |
| Debug logging | `UT_DebugEnabled` | Developer diagnostics |
| *(marker files: `WorldTomeHandshake`, `EnforceTomeReads`, `DebugTrap`, `FireTrap`, …)* | — | Temporary experimental switches; not in the MCM, and should stay out |

| Criterion | SkyUI MCM (keep) | SKSE Menu Framework |
| --- | --- | --- |
| Dependency | SkyUI, already required (MCM Helper is also installed) | A new required dependency (installed in this profile, `SKSEMenuFramework.log`, but not for all users) |
| Controller | Full gamepad support | ImGui navigation; gamepad support is weaker |
| Persistence | Globals saved per game, already working | Must be implemented (JSON or INI): global, not per save |
| Existing saves | Unchanged | Migration needed |
| Synchronous native reads | **Already verified:** native reads the registered globals in µs (§5, §14) | Direct C++ |
| Cost | None now | A new UI, persistence and migration |

**Recommendation: keep SkyUI MCM with ESP globals.** The native evaluator already reads them synchronously, so SKSE Menu Framework would solve no current problem. Revisit only if settings must become global across saves; even then, MCM Helper with INI storage is the smaller step. Developer switches stay as marker files.

## 17. Remaining release blockers

| # | Blocker | Severity | Fix |
| --- | --- | --- | --- |
| 1 | A disabled mod refuses world tomes (the case-sensitive classifier) | **High:** a confirmed defect | §11.1 |
| 2 | Read enforcement ignores the mod being disabled | Medium | §11.2 |
| 3 | Container, Take All and barter parity untested | High, for the post-acquisition paths | §12 procedure |
| 4 | Post-acquisition rejection destroys the tome | High, against the design principle | Return to `akSourceContainer` (a separate task) |
| 5 | Unlocked barter and exclusion-list reads on worker threads | Blocks Task 15C | §13 replacements |
| 6 | `GetBaseActorValue`'s derived-value branch is partially analysed | Low, residual | Accept, or disassemble further |
| 7 | `UT_TomeSafe`, exclusions and quest references untested in game (the exclusion list is empty, and no tome carries `UT_TomeSafe`) | Medium | Test data (an ESP edit or a test plugin) |
| 8 | The full Ancestries load order | Medium | A profile run |

**Recommendation.** Do the §11 and §13 prerequisites as one small, tested change, then run the §12 container session. After that, implement Task 15C as specified in §15: opt-in, Firebolt only, with the schema 18 fallback and marker rollback. The world-path evidence (13 of 13 matches, µs latency, every input explained) is sufficient for that step. It is not yet sufficient for removing the asynchronous path.

## 18. Task 15C.1: outcome classification and disabled-mod corrections (schema 20)

**Status:** built and tested offline (11 of 11 suites), DLL deployed, Papyrus unchanged. **Not yet tested in game.** Native enforcement is **not** enabled: the schema 18 handshake still decides, and the schema 19 shadow still runs.

### 18.1 Outcome classification

`WorldTomeHandshake::ClassifyOutcome` now goes through a typed boundary, `NativeEligibility::ParseOutcome`:
- it accepts exactly the eleven known outcome strings, case-insensitively;
- anything else is `Unrecognized`, which maps to Unavailable (protected, never authorised).

The prefix matching (`accept-*` → Exempt, `reject-*` → Rejected) is gone.

| String | Schema 16–19 | Schema 20 |
| --- | --- | --- |
| `Disabled` | Unavailable: **tome refused** (observed 18 November) | Exempt |
| `Accept-Eligible`, `ACCEPT-ELIGIBLE` | Unavailable | Accepted |
| `Reject-Ineligible` | Unavailable: protected, but **no refusal feedback** | Rejected: refusal feedback |
| `accept-preauthorized`, `accept-anything` (no Papyrus world path produces these) | Exempt | Unavailable |
| `reject-removed` (post-path only) | Rejected | Unavailable |

**Why the casing varies.** The script literals are lowercase (`"disabled"` in `UT_EvaluateWorldTome` and `OnItemAdded`), yet native code received `Disabled`. It also received `Dungeon` and `Town` from lowercase context literals, and the ledger logged `outcome=Disabled`. That fits a VM-wide, case-insensitive string table in which the first casing loaded by any script wins. This is a plausible explanation, not a verified one. **The fix does not depend on it:** Papyrus string comparison is case-insensitive by definition, so the native boundary has to be too.

### 18.2 Disabled-mod acquisition

The mod state now comes from the registered `UT_ModEnabled` global, read live (`CurrentModState`), so an MCM change applies on the next activation without a restart.

| State | Meaning |
| --- | --- |
| Disabled | The forms are registered, the global is present, and `(int)value == 0` (Papyrus `GetValueInt`) |
| Enabled | Registered, and the global is not 0 or is None (as in Papyrus) |
| Unknown | Not registered this session. Enforcement stays as it was (conservative); the handshake now classifies `Disabled` correctly anyway |

**What a disabled mod does at activation:**
1. The in-scope activation is forwarded **immediately**: no veto, no Papyrus round trip, no replay.
2. `world_tome_activation action=forward reason=mod_disabled discarded_state=` is logged.
3. Any handshake entry for the reference (Pending, Rejected, Authorized, Continuing) is discarded. A late Papyrus answer is then `unmatched`, and a running continuation reports itself consumed.
4. No grant is bound, because `OnItemAdded` takes its own disabled branch. No trap fires.

**Re-enabling** starts each reference fresh.

### 18.3 Disabled-mod read enforcement

`EnforcementEvidence::modDisabled` (only a positive Disabled) makes `DecideEnforcement` forward every read with reason `mod_disabled`. It is checked after the `EnforceTomeReads` marker check and before any other rule.

With the mod disabled:
- the Read Or Take world READ reads normally;
- container-side reads are forwarded;
- DEST, DESTified and vanilla behave as they would without Untamed Tomes.

With the mod enabled or the configuration unknown, the pending-acquisition and container-read protections are unchanged. No third-party book behaviour is affected beyond what the `EnforceTomeReads` marker already scopes.

### 18.4 Tests (offline)

| Suite | New cases |
| --- | --- |
| `native_eligibility` | `ParseOutcome` for every known string in mixed casings, and unknown strings; a round trip from evaluator results; `ModStateOf` for unregistered, disabled, truncated 0.4, re-enabled and None global |
| `world_tome_handshake` | Mixed-case classification for accepted, exempt, rejected, disabled and unavailable; unknown strings; a mixed-case refusal applied as a refusal; disabling with Pending, Rejected and Authorized entries (all discarded, a late answer unmatched, a fresh request after re-enabling, no stale authorisation or cooldown); disabling during a continuation (reported consumed) |
| `read_enforcement` | A disabled mod forwards a world READ while pending, a container-side read and an inventory read in every policy; the marker still decides first; re-enabling restores the denials |

### 18.5 Behaviour changes

All of these apply only when the mod is disabled, or to unknown or mixed-case strings:
1. A disabled mod no longer intercepts in-scope world tomes. Take and READ go through immediately.
2. A disabled mod no longer denies reads.
3. Mixed-case known outcomes are honoured.
4. Unknown `accept-*` strings no longer authorise.

**Enabled behaviour is unchanged** for every outcome Papyrus produces today.

### 18.6 In-game test plan

Markers are unchanged. Startup must show `observer_load schema=20`.

| # | Action | Expected |
| --- | --- | --- |
| D1 | Enabled, threshold 150, dungeon: Take a Firebolt | Refused as before (`reject-ineligible`, pulse) |
| D2 | MCM: disable. Take the same Firebolt | Picked up at once. `reason=mod_disabled discarded_state=true` (the rejected entry from D1), `ledger_ack outcome=disabled`, no trap |
| D3 | Disabled: Read Or Take **READ** on a placed Firebolt | Read proceeds: `tome_read_decision … reason=mod_disabled`; DEST and ISL study starts |
| D4 | Disabled: chest Take of a tome | Kept, `disabled` |
| D5 | MCM: re-enable. Take a new Firebolt | Refused again; a fresh request (`new_request`) |
| D6 | Enabled: READ on a placed Firebolt with threshold 100 | Authorised, the read denied as pending, the tome in inventory (schema 18 behaviour unchanged) |
| D7 | Enabled: inventory read | Forwarded (`no_pending_acquisition`) |

### 18.7 Rollback

Copy `pre-task15c1-schema19.dll` and `.pdb` from `task15c1-preservation/` into `SKSE\Plugins\`. The PEX is unchanged, so nothing else is needed.

## 19. Schema 20 runtime results (18 November 2026, 10:07–10:10)

The logs are preserved as `task15c2-preservation/schema20-session-{native,papyrus}.log`.

| §18.6 test | Evidence [V] |
| --- | --- |
| D1, enabled refusal | Request 1, `reject-ineligible`, refused (10:08:54) |
| D2, disabled Take | `action=forward reason=mod_disabled discarded_state=true` (the D1 rejected entry was discarded); picked up; `ledger_ack outcome=Disabled`; no trap |
| D3, disabled READ | The Read Or Take READ was forwarded: `tome_read_decision … decision=forward reason=mod_disabled` (Firebolt 10:09:18, Oakflesh 10:09:35) |
| D5, re-enabled | Request 2, `reject-ineligible`, refused (10:10:27) |
| Eligible again | Request 3 `accept-eligible`, continued and picked up; `world_tome_grant match=exact_reference consumed=true` |
| Shadow | Every comparison matched (`papyrus_world`, `activation`, `papyrus_post` `disabled`) |

D4 (chest Take while disabled), D6 and D7 were not exercised.
