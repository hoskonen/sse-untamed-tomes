# Investigation 24 — Synchronous native world eligibility

## Status

Schema 21 adds opt-in synchronous native eligibility for the Firebolt world tome (`000A26FD`).

- Built and tested offline: 12 of 12 suites, including the new `native_world_policy`.
- Deployed to MO2 (below), with the Papyrus side updated.
- **Off by default.** Without the marker, the build behaves as schema 20.
- **Not yet tested in game.**
- Nothing is committed.

| File | SHA-256 |
| --- | --- |
| DLL | `3B11ECF3902A53772B555AFA04518271EDDFC2E7DFE1CF59B16856D90F43C1CC` |
| PEX | `9DA61D49AD66408660573E84B872909DD312342374E3B9D73B0AB01D20704240` |

The new build and the schema 20 rollback set are in `task15c2-preservation/` (native checkout), with SHA-256 sums.

## 1. Switch and policy

The switch is an empty file:

`Documents\My Games\Skyrim Special Edition\SKSE\UntamedTomes.NativeWorldEligibility`

- It is read at startup.
- It implies the world-tome hook, because the handshake stays as the fallback.
- The log shows `world_tome_policy policy=native_synchronous|papyrus_handshake native_target=000A26FD`.

**Rollback:** remove the file and restart.

The native path applies **only** to Firebolt, even with `WorldTomeHandshakeAllTomes`. Chest, Take All, barter, other tomes and every post-acquisition path are unchanged.

## 2. Activation flow (in scope: player activator, live target, spell tome with the tome keyword)

1. **Mod disabled** (schema 20): forward now; any handshake state is discarded.
2. **Native decision** (`NativeWorldPolicy::Decide`, offline-tested), using a snapshot gathered on the activation thread (Inv. 23 §13):

   | Evaluator result | Action |
   | --- | --- |
   | `accept-eligible` | **Forward in this call**: the original handler and arguments, once. No Papyrus request, no replay, no second activation event |
   | `accept-safe-*`, `accept-exclusion`, `accept-quest-reference` | Forward (exempt) |
   | `disabled` (the evaluator's own view) | Forward |
   | `reject-ineligible` | **Veto in this call**: return false, so Read Or Take is not called, nothing moves, and nothing enters the inventory. Refusal feedback is scheduled (step 4) at most once per reference per 2 s; **every** ineligible press is still vetoed |
   | Forms not registered; `MagicTomeKeyword`, threshold or enabled global missing; `unavailable-*`; `abort-no-player`; anything unrecognised; a handshake replay | **Fall back** to the schema 20 handshake, which is protective (`native_world_decision decision=fallback reason=…`) |

   A missing threshold means "everyone eligible" in Papyrus, so native code never decides on incomplete configuration.
3. **Correlation on forward:**
   - The decision ID (`2^40 + n`, a separate range from handshake request IDs) goes into `ForwardContext`. A grant is bound **only** when the player-inbound transfer happens inside the forwarded call.
   - `OnItemAdded` consumes it (`accept-preauthorized`), so there is no second evaluation, no removal and no trap.
   - Exact-reference matching applies when `akItemRef` is present.
   - The decision alone creates nothing.
   - Any fallback state for the reference is discarded, so a late Papyrus answer or replay cannot forward a second time.
4. **Refusal feedback:**
   - An SKSE task checks the session, that Papyrus is ready, the handle, and that the reference is present and loaded.
   - It then sends the ModEvent `UT_WorldTomeRefused` (sender: the reference; `numArg`: the negated decision ordinal).
   - `OnUTWorldTomeRefused` runs the existing `UT_WorldTomeRefusal`: the shock pulse on the tome and the notification.
   - The decision never waits for it.

## 3. Prerequisites resolved

| Inv. 23 §13 item | Change |
| --- | --- |
| Barter state | Replaced: an atomic flag set by the existing `MenuOpenCloseEvent` sink (release store, acquire load), reset on load. No more `UI::menuMap` lookups from worker threads. It is as current as the UI's own event, the same timing Papyrus `UI.IsMenuOpen` observes |
| Exclusion list | Replaced: an immutable, sorted FormID vector (`ExclusionSnapshot`, behind a `shared_ptr`). It is copied from `forms` and `scriptAddedTempForms` when Papyrus registers, on every load and new game. `UT_RegisterEligibilityForms` is now registered frame-synced (one frame at load), the same context as Papyrus's own FormList functions, so the copy does not race a script `AddForm`. On pre-load the snapshot pointer is dropped; readers that hold it keep it alive. FormIDs, so nothing dangles. **A runtime `AddForm` takes effect at the next load**; no Untamed Tomes script modifies the list |
| Base Magicka | Unchanged: the engine's read-locked actor-value storage; the derived-value branch is a residual (Inv. 23 §13) |
| Location, keywords, quest aliases, globals | Unchanged: aligned fields, lock-free record walks, the engine's own read locks |

## 4. Read Or Take and read enforcement

- **The forward is the original activation**, so Read Or Take sees the real input state. Its alternate-action hotkey works, unlike the schema 18 replay.
- **TAKE:** pickup, grant, `accept-preauthorized`.
- **READ:** Read Or Take picks the tome up (grant bound, ledger pending), then calls `Read`. Unified enforcement denies it (`pending_acquisition`), so the tome is in the inventory **unread**, with no premature learning, exactly as in schema 18. An accepted world acquisition does not authorise learning; the ledger rule still applies. Inventory reads afterwards forward to DEST and DESTified (`no_pending_acquisition`).
- **Disabled mod:** reads are forwarded (schema 20).
- **Vetoed activation:** `Read` is never reached.

## 5. Immediate activation versus the schema 18 replay

| Aspect | Schema 18 replay | Schema 21 synchronous |
| --- | --- | --- |
| Activation events | Two (vetoed plus replay) | One |
| Read Or Take input state | Lost (replay from a task) | The original |
| Ownership and crime | Owned tomes excluded from auto-continue; a second press needed | The engine's normal handling of the player's own press |
| Grant binding | `ForwardContext` around the replay's handler call | The same mechanism around the original call, which is what verified manual second Takes used (Inv. 20 §12) |
| Delayed or modded transfer | No grant, so `OnItemAdded` evaluates (protective) | The same |

## 6. Diagnostics

| Row | Contents |
| --- | --- |
| `world_tome_policy` | At startup |
| `native_world_decision` | `decision=forward\|veto\|fallback reason= native= native_context= decision_id= us_total= us_location= us_magicka= discarded_state= feedback=scheduled\|cooldown\|none previous_called=` and the reference |
| `world_tome_acquisition stage=bound request=<decision_id> since_forward_us=` | The transfer |
| `world_tome_forwarded … acquisitions_bound=` | The forward returned |
| `world_tome_grant … request=<decision_id> since_activation_ms=` | `OnItemAdded` consumed the grant |
| `native_world_refusal stage=dispatched\|skipped` | The refusal task, then `world_tome_papyrus stage=received/feedback request=<-ordinal> since_activation_ms=` |

**Activation → inventory transfer** = the `native_world_decision` capture time plus `since_forward_us` on the bound row. Compare it with schema 18's 684–701 ms automatic pickup (Inv. 22 §1).

## 7. Offline tests (`native_world_policy`, plus the existing suites)

- **Decision mapping:** every outcome; marker on and off; non-target bases; continuation; unregistered configuration and each missing required form; unknown and error outcomes.
- **Refusal cooldown:** per reference, reset on session change, never throttling the veto.
- **Exclusion snapshot:** deduplication and null handling, plus concurrent publish and refresh with four reader threads against 2000 republishes and a reset, with zero inconsistent reads.
- **Grants for synchronous forwards:** two identical Firebolts with exact references and no cross-consumption; another tome cannot consume a Firebolt grant.
- **Fallback state:** a discard makes late answers unmatched and replays impossible.
- **Existing suites** cover the shadow evaluator, the handshake fallback, schema 20 disabled handling, and read enforcement for world READ, TAKE and inventory reads.

## 8. In-game acceptance test

Create the marker, restart, and check for `world_tome_policy policy=native_synchronous`. Keep `EnforceTomeReads`, `DebugTrap` and `FireTrap`. Test in Bleak Falls Barrow unless noted. After each step check `player.getitemcount 000A26FD` and whether the tome is still in the world.

| # | Action | Expected |
| --- | --- | --- |
| N1 | Threshold 150: Take Firebolt | Stays; pulse; `decision=veto reason=ineligible feedback=scheduled`; no Papyrus request |
| N2 | Press again quickly, three times | Every press vetoed; `feedback=cooldown` within 2 s |
| N3 | Threshold 100: Take the same tome | **Immediate pickup**; `decision=forward reason=eligible`, `stage=bound request=<decision_id>`, `match=exact_reference` or `anonymous_stack`, `accept-preauthorized`; no trap |
| N4 | Two Firebolts, one Take each | Two decisions; each grant names its own `world_ref` |
| N5 | Riverwood, threshold 150 | Immediate pickup, `reason=exempt native_context=town` |
| N6 | MCM disabled, then enabled | Disabled: `reason=mod_disabled` (before the native decision), immediate. Enabled: restrictions return |
| N7 | Read Or Take TAKE (Shift + activate), threshold 100 | Normal Take |
| N8 | Read Or Take READ, threshold 100 | In inventory unread: `tome_read_decision … deny reason=pending_acquisition`; no spell learned |
| N9 | Inventory read afterwards | Forwarded; DESTified study starts |
| N10 | An owned Firebolt (a shop, or `setownership`), eligible | Normal Steal handling with crime |
| N11 | Save and reload, then Take | Registration again, then a fresh decision, with no stale grant |
| N12 | Missing configuration | **Untested:** needs an ESP without the threshold binding; the offline tests cover it |
| N13 | Remove the marker and restart | `policy=papyrus_handshake`; the schema 20 behaviour (about 0.7 s auto-pickup) |
| N14 | An ordinary book, a skill book, another tome | Unaffected; other tomes keep the handshake |

## 9. Remaining risks

- **The first in-game run.** Is a synchronous forward from the activation hook observed exactly like the verified manual Take? Expected yes, because it is the same call, but unconfirmed.
- **Vanilla pickup (Read Or Take disabled).** It is still unverified whether the transfer happens inside the call. If it doesn't, there is no grant, and `OnItemAdded` evaluates instead (protective, and the same result for an eligible character).
- **Barter flag timing.** The flag follows `MenuOpenCloseEvent`. A world activation inside barter is not expected.
- **The exclusion snapshot ignores runtime `AddForm` until the next load.**
- **Native and Papyrus rules can drift.** Papyrus still evaluates the post-acquisition paths, so a rule change must be made in both until those paths migrate; the shadow there keeps comparing.
- **Unchanged from earlier investigations:** container rejection still removes the tome (Inv. 23 §17.4), and container, Take All and barter remain unvalidated in the shadow.

## 10. Rollback

| Goal | How |
| --- | --- |
| Back to the handshake | Remove `UntamedTomes.NativeWorldEligibility` and restart |
| Back to the schema 20 files | Copy `pre-task15c2-schema20.dll`, `.pdb` and `pre-task15c2-UT_PlayerMonitor.pex` from `task15c2-preservation/` into the MO2 mod (`SKSE\Plugins\` and `Scripts\`) |
| Earlier rollbacks | Inv. 23 §10 and §18.7 |

## 11. Task 15C.3: Read Or Take world READ does not open DESTified study

**Report:** with native enforcement on, an eligible world READ puts the tome into the inventory instead of reading it. Reading it from the inventory afterwards works, and the study opens.

### 11.1 Evidence (schema 21, 18 November 2026, 11:51–11:52)

The logs are preserved as `task15c3-preservation/schema21-session-{native,papyrus}.log`.

| Time | Row [V] | Meaning |
| --- | --- | --- |
| 11:52:30.392 | `native_world_decision decision=forward reason=eligible`, thread 9632 | The original activation was forwarded |
| .394 | `world_tome_acquisition stage=bound … since_forward_us=1159` | Read Or Take picked the tome up inside the call; the grant was bound |
| .394 | `ledger_add pending=1` | The acquisition is pending until `OnItemAdded` acknowledges it |
| .400 | `tome_read_decision … decision=deny reason=pending_acquisition`, caller Read Or Take, thread 9632 | Read Or Take's READ, inside the same activation, **denied** |
| .476 | `world_tome_grant … match=anonymous_stack consumed=true`, then `ledger_ack accept-preauthorized` | The acquisition was accepted, 94 ms after activation |
| 11:52:39.198 | `tome_read_decision … classification=player_inventory decision=forward reason=no_pending_acquisition`, `original_invoked=1 original_result=false` | The inventory read reached Read, so DEST and ISL took over and the study opened |

### 11.2 Diagnosis

- **It is not a schema 21 regression.** The same deny happened on every verified world READ since the unified rule existed: schema 17 (Inv. 20 §12, activation 3), schema 18 (Inv. 22 §1, all three replays) and schema 20 (§19 request 3). It is the documented v1.0 limitation "the Read Or Take world READ becomes a Take" (roadmap).
- **It happens because the read arrives before Papyrus has acknowledged the acquisition.** Pending-acquisition denial was designed (Inv. 13–14) for the time when native code did not know whether Papyrus would reject the tome. A READ during that window had to be refused, because Papyrus might remove the tome a moment later.
- **The read hook sees the same information as before.** Native enforcement only changes who decided the activation; the pending ledger and the read hook are unchanged.
- **With native enforcement disabled,** the schema 20 handshake gives the same result (§19): a READ in the replay is denied as pending.
- **With the mod disabled,** the READ is forwarded (`reason=mod_disabled`, Inv. 23 §19 D3). Whether DESTified then opened the study was not recorded.
- **Inventory reads reach DEST and DESTified normally [V].**

### 11.3 Can the authorised world READ be distinguished safely?

**Yes, narrowly.** In both the native forward and the handshake's authorised forward, the READ runs:
- **on the same thread**, inside the forwarded activation, while `ForwardContext` is active (thread 9632 for every row above);
- **after** a grant for this base has been bound to this activation (`bound > 0`), which is proof that this transfer was the authorised one.

An unauthorised read cannot meet those conditions:
- a different tome (base mismatch);
- a read on another thread or outside an activation;
- a read before any transfer (`bound == 0`);
- a fallback forward (no context);
- an activation that was vetoed (`Read` is never reached).

### 11.4 Smallest compatible correction (recommended; not implemented)

1. Add `authorizedWorldAcquisition` to `EnforcementEvidence`. It is true only when `forwardContext.active`, `forwardContext.base == book` and `forwardContext.bound > 0`, on the calling thread.
2. In `DecideEnforcement`, after the mod-disabled check: if it is true, **forward** with a new reason, `authorized_world_acquisition`. Every other rule is unchanged: pending denial still applies to every other read, and the container-side rule is untouched.
3. Log `forward_context_request=` on the read decision row for correlation.

**Why this keeps the invariant.** The forwarded `Read` is the same call an inventory read makes. With DEST 1.2.3, Read keeps the book and does not teach (`original_result=false`), and DESTified starts its study through `OnSpellTomeRead`. The tome stays in the inventory because Read Or Take removes it only when `Read` returns true. Without DEST, Read behaves as vanilla Read Or Take always does. Nothing is learned that the player's own READ would not learn, and eligibility has already been decided.

**Offline tests to add:**
- the read-enforcement mapping: authorised and pending → forward; unauthorised and pending → deny;
- a context base mismatch → deny;
- `bound == 0` → deny;
- disabled still takes precedence;
- the container-side rule unchanged.

### 11.5 Runtime tests (with the correction)

| # | Action | Expected | Rows |
| --- | --- | --- | --- |
| R0 | Baseline, current build, **mod disabled**: world READ | Does the DESTified study open? This establishes Read Or Take, DEST and DESTified behaviour without Untamed Tomes | `reason=mod_disabled`, DESTified's own messages |
| R1 | Native on, threshold 100: world READ | Study opens; tome in inventory, unlearned until study completes | `tome_read_decision … decision=forward reason=authorized_world_acquisition`, `original_result=false`, `grant consumed`, `accept-preauthorized` |
| R2 | Native on, threshold 150: world READ | Vetoed before Read; study does not open | `native_world_decision decision=veto`; no `tome_read_*` |
| R3 | Native off (handshake), threshold 100: world READ | Study opens after the automatic replay (about 0.7 s) | `continued_authorized`, then the same forward reason |
| R4 | Native on, threshold 100: Take (Shift), then inventory READ | Unchanged | `no_pending_acquisition` |
| R5 | Chest tome, ineligible, read from the container menu | Still denied (container rule) | `container_side_without_acquisition` |

**Separate observation:** the only native decision in this run took 405 µs, 397 µs of it in location lookups. The schema 19 samples took 4–9 µs. That may be a cold first lookup after load. Watch `us_location` in the next run before treating it as a regression.

## 12. Task 15C.4: an eligible world READ reaches DESTified (schema 22)

**Status:**
- Built; 12 of 12 offline suites pass.
- DLL deployed: `C3B158BB8A6D1816CA2219D1F1BF6644CF0AF1AB1A08729D726E943FCB2C5A4E`. The PEX is unchanged (`9DA61D49…`).
- **Not tested in game.**
- R0, a world READ with the mod disabled to see whether DESTified opens its study, has **not been run**; the newest log is still the one from 11:52. That baseline determines whether the exception alone is enough.
- Nothing is committed.

### 12.1 How Read Or Take executes READ and TAKE [V]

**From the Read Or Take 1.5.1 disassembly, with its PDB symbols** (`po3_ReadOrTakeBooks.dll`):

1. `Book::Hooks::Activate::thunk` (RVA `25D0`, the slot `0x37` handler we forward to) decides Read or Take from its settings (`iDefaultAction`, automatic: unread books are read and read books taken), the alternate-action hotkey and the book's state.
2. It then calls `activate_book(book, target, activator, count, bool read)`. That function:
   - **always** calls `PlayerCharacter::PickUpObject` (`call [rax+660h]`);
   - then tests `read` (`test r15b,r15b; je …`) and leaves if it is false;
   - **only when READ was chosen**, calls `TESObjectBOOK::Read` (`call rax`, return address `+256C`);
   - if `Read` returns true, calls `RemoveItem` (`call [rax+2B0h]`).

**Runtime agreement:**
- Every logged world READ came from `po3_ReadOrTakeBooks.dll+256C`.
- In the schema 17 session, activations 7 and 8 happened after Firebolt had been read once, so Read Or Take's automatic mode **took** them: forwarded, transfer bound, and **no `Read` call at all**.
- So a TAKE never calls `Read`. A `Read` from Read Or Take inside the activation is its READ.

**Discriminator chosen:** the module of `Read`'s return address. The arguments of the original activation do not carry the choice, which Read Or Take makes internally. Input state and timing were rejected as unreliable. The exact RVA (`256C`) is logged but not required, so that an update of Read Or Take does not silently disable the exception.

### 12.2 Change

**Predicate.** `IsAuthorizedWorldRead` (`ReadEnforcement.h`, pure, tested) returns `authorized` only if **all** of these hold:

| Condition | Rejection reason |
| --- | --- |
| This thread is inside a forwarded activation (`ForwardContext`, thread-local) | `no_context` |
| The forward came from a **native** approval (decision ID ≥ 2^40). Handshake and fallback forwards are excluded | `not_native_decision` |
| The forwarded book equals the book being read | `wrong_book` |
| At least one inventory transfer was bound in this activation | `no_transfer` |
| Its grant still exists | `no_grant` |
| `Read` was called from `po3_ReadOrTakeBooks.dll` | `not_read_or_take` |
| The registered configuration says enabled | `mod_not_enabled` |

**Decision.** `DecideEnforcement` forwards an authorised read with reason **`authorized_world_read`**. The check comes after the marker, mod-disabled, reader and spell-tome checks, and before the pending rule.

**Unchanged for every other read:**
- the pending-acquisition denial;
- the container-side denial;
- inventory reads.

**Lifetime.** `ForwardContextScope` (RAII) restores the outer context on every exit from the forwarded call, including nested activations and unwinding.

**Diagnostics.** A `world_read_authorization result= forward_context_request= native_decision= context_base= book= bound= grant_present= caller_read_or_take= caller_rva= mod_enabled=` row is logged for every read made inside a forwarded activation.

**What an authorised READ does:**
- It is the same `Read` call an inventory read makes, so DEST 1.2.3 keeps the book and does not teach, and DESTified starts its study through `OnSpellTomeRead`.
- `Read` returns false (observed for inventory reads, `original_result=false`), so Read Or Take does not call `RemoveItem`. The tome stays in the inventory.
- No new grant: `Read` adds nothing to the inventory, and binding requires an inbound transfer.
- `OnItemAdded` still consumes the activation's grant (`accept-preauthorized`), so there is no post-acquisition rejection or trap.

**TAKE is unchanged:** there is no `Read` call, so the tome goes into the inventory without the study interface.

### 12.3 Offline tests (`read_enforcement`)

**Predicate:**
- authorised;
- each rejection reason: no context, a handshake forward, the wrong book (another tome, or a zero ID), no transfer, the grant consumed, a non-Read Or Take caller, the mod not enabled.

**Decision:**
- authorised plus pending → forward (`authorized_world_read`) under both pending policies;
- unauthorised plus pending → deny (world READ and the inventory race);
- the container rule intact;
- the marker and mod-disabled rules still decide first;
- non-player readers and non-teaching books never reach the exception.

The existing suites keep covering the handshake fallback, the two-copy grants and the disabled mod.

### 12.4 Runtime tests

Use the `NativeWorldEligibility` marker, Bleak Falls Barrow, a placed Firebolt, and an unread Firebolt base. After the first study, use a fresh save or a different unread tome base: Read Or Take auto-takes read books.

| # | Action | Expected | Rows |
| --- | --- | --- | --- |
| R0 | **Baseline:** MCM disabled, world READ | Note whether DESTified opens its study | `reason=mod_disabled` |
| R1 | Threshold 100, world READ (plain activate on an unread tome) | **Study opens**; the tome is in the inventory; the spell is **not** learned yet | `native_world_decision forward`; `world_tome_acquisition bound`; `world_read_authorization result=authorized … caller_rva=256C`; `tome_read_decision … decision=forward reason=authorized_world_read`; `tome_read_exit original_result=false`; `world_tome_grant consumed`; `accept-preauthorized`; no `defense_effect` |
| R2 | Threshold 100, TAKE (Shift + activate) | The tome is in the inventory, no study | No `tome_read_*` rows in the activation |
| R3 | Threshold 150, world READ and TAKE | Both vetoed; tome stays; pulse | `decision=veto`; no `tome_read_*` |
| R4 | Two Firebolts, READ one and TAKE the other | Independent grants; study only for the read one | Two decisions, one `authorized_world_read` |
| R5 | Inventory READ after R2 | DESTified study | `no_pending_acquisition` |
| R6 | Marker removed (handshake), threshold 100, world READ | **Denied** as before (`pending_acquisition`): the exception excludes handshake forwards; the tome is in the inventory unread | `world_read_authorization result=not_native_decision` |
| R7 | MCM disabled, world READ | Forwarded by `mod_disabled` | As in schema 20 |
| R8 | Chest tome, read from the container menu | Still denied | `container_side_without_acquisition` |

`player.getitemcount 000A26FD` after R1 should be 1 (the tome kept). Check `player.hasspell 00012FD0` stays 0 until the DESTified study completes.

### 12.5 Remaining compatibility risks

- **R0 is unknown.** If Read Or Take, DEST and DESTified do not open the study from a world READ even without Untamed Tomes, the fault is in that integration: `Read` is called on a worker thread inside the activation. The exception cannot fix that.
- **Read Or Take updates.** The caller check is by module name. A version that calls `Read` from a TAKE path, which is not the case in 1.5.1, would let that read through. It is still protected by native approval, the bound transfer and the grant, and DEST still prevents direct teaching.
- **Without DEST,** an authorised READ teaches immediately (vanilla `Read`), and Read Or Take removes the book. That is ordinary Read Or Take behaviour for an eligible character.
- **The handshake path** (marker removed) keeps turning a world READ into a Take. Extending the exception to authorised handshake forwards is possible with the same predicate but was excluded by scope.

### 12.6 Rollback

Copy `pre-task15c4-schema21.dll` and `.pdb` from `task15c4-preservation/` into `SKSE\Plugins\`. The PEX is unchanged.
