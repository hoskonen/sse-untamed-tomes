# Investigation 19 — World tome activation and eligibility handshake

> **Superseded in part by [Investigation 20](20-handshake-validation-and-hardening.md) (schema 17).** Schema 17 changes four behaviours documented here:
> - The timeout fallback and the `papyrus_not_ready` forward are removed. Neither ever forwards now.
> - Grants are bound to the observed inventory transfer instead of the base.
> - The dispatch thread is not the main thread (the §3 wording is wrong).
> - The schema 16 rejection path is now runtime-verified.

## Status

Schema 16 connects the pre-pickup veto (Inv. 18) to Papyrus eligibility. When the player activates an in-scope world spell tome, native code vetoes the activation and asks Papyrus. An ineligible character sees the tome refuse them, and it stays where it was found. An eligible character gets one authorised activation. The feature is opt-in and experimental.

- Native and Papyrus build cleanly, and all ten offline suites pass. The new suite is `world_tome_handshake`.
- Deployed: DLL `75D96F668A76A71BF85D9C08DF9CF8F6B12B39D8977ECE829F0232D6C184D9C0` and PEX `4138264A9E1F5669E674D573BDD1D8935AEE5A55AD433C68AC1B5EB12EA2C379`.
- Both files are preserved in `task11-preservation/`, with their `SHA256SUMS.txt`.
- **The handshake has not been run in game.** The latency figures below are predictions until it has.

## 1. Starting point (schema 15 runtime, 16 November 2026, 18:07)

The run is preserved as `task11-preservation/schema15-veto-session-20261116-1807-*.log`. The native log shows:

- **First activation vetoed.** Firebolt `000A26FD`, reference `FF000F0C`, was vetoed with `ref_3d=true`, and the reference stayed at the same position.
- **Second activation forwarded.** It went to Read Or Take (`already_vetoed_once`), which picked the tome up; the reference was then `deleted=true`.
- **Slot ownership.** Read Or Take was the previous owner of the slot (`po3_ReadOrTakeBooks.dll` RVA `25D0`), and we still owned it at data load.
- **Other tomes unchanged.** `000A2705` and `000A26F9` were forwarded with `not_test_tome`.
- **Activation thread.** Activations ran on worker threads 14368, 11404 and 13672, never on the main thread (26440). This decides the threading design below.
- **Post-pickup path, for comparison.** For the forwarded Firebolt READ the timeline was:

  | Time | Step |
  | --- | --- |
  | 0 s | activation |
  | 1.33 s | Papyrus `reject-removed` |
  | 1.48 s | trap triggered |
  | 2.75 s | firebolt cast |

  The tome had already left the world by then. Firebolt hits: 1 of 3 in this run, the same rate as Inv. 17.

## 2. State machine

`src/WorldTomeHandshake.h` contains no game types, so it can be tested offline. State is keyed by the **world reference FormID**, and each entry also records the base book. If a FormID turns up with a different base, the entry is discarded and a new request starts.

| State | Meaning | Next activation |
| --- | --- | --- |
| Unknown (no entry) | Not evaluated | Veto, and queue one request → Pending |
| Pending | Request sent and awaiting Papyrus | Silent veto with no new request (`pending_request`) |
| Rejected | Refused, or undecidable | Silent veto for 2 s (`rejected_cooldown`). After that, veto and a **fresh** request (`reevaluate`) |
| Authorized | Accepted or exempt | Within 30 s: the entry is erased, a pickup grant is recorded, and the previous handler is called **once** (`authorized`). After 30 s: a fresh request (`authorization_expired`) |
| TimedOut | No answer within 5 s | The entry is erased and the activation forwarded (`timeout_fallback`). The unchanged post-acquisition path evaluates it |

**Answers.** Transitions on an answer happen only from Pending, and only when the answer matches:

- the generation (the native session counter);
- the request ID;
- the reference FormID;
- the timeout.

**Rejected answers.** Any non-matching answer is reported back to Papyrus as one of `stale_generation`, `unmatched`, `reference_mismatch`, `duplicate` or `expired`. It changes nothing, and Papyrus shows no feedback for it.

**Papyrus outcome strings.** They map to four categories:

| Category | Outcomes |
| --- | --- |
| Accepted | `accept-eligible` |
| Exempt | the other `accept-*` outcomes and `disabled` |
| Rejected | `reject-*` |
| Unavailable | anything else |

Unavailable answers behave like Rejected, but without feedback, so they never authorise a pickup.

**Re-evaluation.** A rejection is never cached beyond the 2 s cooldown. The next activation after it asks Papyrus again, so a character who has since qualified can take the tome. The cooldown is what stops request flooding and repeated feedback.

**Cancellation.**

| Event | Effect |
| --- | --- |
| Pre-load, post-load or new game | `Reset(session)` clears all entries and grants. Later answers are `stale_generation` |
| On the main thread, before dispatch | The request is cancelled, and the tome goes back to Unknown, if any of these hold: the handle doesn't resolve, the FormID changed, the reference is deleted or disabled, the cell changed, or Papyrus isn't ready |
| Timeout | TimedOut; the next activation falls back to the post-acquisition path |
| Mode disabled | No marker means no hook (it is read at startup) |
| Papyrus mod-enable global is 0 | Papyrus answers `disabled` (Exempt), so the next activation takes the tome |
| Invalid answer | Unavailable |

`Prune` drops settled entries:
- Rejected entries, once their cooldown has passed;
- Authorized entries, after their 30 s window;
- TimedOut entries, after 30 s.

The table therefore stays bounded within a session.

**Recovery for the player.** Activating the tome again always makes progress: a new request, a re-evaluation, or the timeout fallback. No path leaves a book permanently inaccessible, and none authorises a pickup without a Papyrus decision. The timeout fallback goes through the old post-acquisition rules, so the old behaviour applies: an ineligible character's tome is removed and the trap fires.

## 3. Request and response protocol

1. **Activation (worker thread, in `BookActivateThunk`).**
   - The scope check requires: the player as activator, a book that teaches a spell, the `VendorItemSpellTome` keyword (the same filter as `OnItemAdded`), a live target, and, by default, Firebolt only.
   - Under a mutex, the activation is applied to the table.
   - On `VetoAndRequest`, it captures `GetHandle()`, the parent cell and the generation. It then calls `SKSE::GetTaskInterface()->AddTask` and returns false. No game or Papyrus API is called from this thread beyond reading the reference that the game itself passed in.
2. **Dispatch (main thread, in the SKSE task).**
   - Checks that the request is still pending in the same generation.
   - Re-resolves the handle to a `NiPointer` and re-checks the reference's FormID, its deleted and disabled flags, and its cell.
   - Sends the SKSE ModEvent `UT_WorldTomeRequest`, with `numArg` = request ID, `strArg` = generation, and `sender` = the world reference.
   - The raw pointer is never stored. Only the handle crosses threads.
3. **Papyrus (`UT_PlayerMonitor.OnUTWorldTomeRequest`).**
   - Calls `UT_EvaluateWorldTome(ref)`, which checks for a reference, a base and the tome keyword, then the mod-enable global. It then calls the **shared** `UT_EvaluateTomeEligibility(base, ref, …)`.
   - Answers with `UT_AnswerWorldTomeRequest(id, generation, ref, outcome)`, which returns the native status.
4. **Feedback.** Papyrus is the only owner:
   - `rejected`: a 0.6 s `EnchShockFXShader` (`00059EDA`) pulse on the tome itself, if its 3D is loaded, plus the notification "*Spell Tome: Firebolt* refuses you."
   - `authorized`: the notification "… yields. Take it again."
   - Any other status: no feedback.
   - Native code only logs `defense_candidate=world_tome_refusal`.
5. **Authorised pickup.** The forward records a grant keyed by base, with a 5 s TTL. `OnItemAdded` calls `UT_ConsumeWorldTomeGrant` first. If a grant exists, it acknowledges `accept-preauthorized` and returns, with no second decision and no trap. The fallback and `papyrus_not_ready` forwards create no grant, so those pickups are still evaluated.

`UT_PlayerMonitor` registers the ModEvent in `OnInit` and `OnPlayerLoadGame`, then calls `UT_WorldTomeHandshakeReady`. Until that call arrives in the current session, in-scope activations forward with `papyrus_not_ready fallback=post_acquisition` and are not vetoed. A missing or old PEX therefore cannot lock tomes. The ready flag is cleared at pre-load and at new game, but not at post-load, in case `OnPlayerLoadGame` runs before the post-load message.

## 4. Shared eligibility (Papyrus)

The old `UT_HandleTomePickup` was split in two.

**`UT_EvaluateTomeEligibility`** makes the decision. Its gates are unchanged and in the original order:
1. safe context;
2. `UT_TomeSafe`;
3. the second context gate;
4. exclusions;
5. quest reference;
6. player present;
7. base Magicka ≥ threshold.

It changes no items and no saved state, and returns either an `accept-*` outcome, `reject-ineligible` or `abort-no-player`.

**`UT_HandleTomePickup`** (the post-acquisition path only) does the rest:
- the progression observation, under the same condition as before;
- `GetItemCount` and `RemoveItem`;
- it maps `reject-ineligible` to `reject-removed` or `reject-skipped-empty-inventory`, exactly as before.

The world path passes the actual world reference to the quest-item check. On the post-acquisition path that argument is usually `None`, because `ref_handle=0` in every logged pickup. Quest tomes are therefore identified better here.

## 5. Latency to measure

Every row carries `capture_unix_us`. The handshake rows also carry `since_activation_ms`, measured from the vetoed activation:

| Stage | Row |
| --- | --- |
| Activation (0) | `world_tome_activation action=veto_and_request` |
| Request dispatched (main thread) | `world_tome_request stage=dispatched since_activation_ms=` |
| Papyrus received | `world_tome_papyrus stage=received since_activation_ms=` |
| Answer applied | `world_tome_answer … since_activation_ms=` |
| Feedback shown | `world_tome_papyrus stage=feedback … since_activation_ms= evaluate_ms= papyrus_ms=` |

**Expectation, not a measurement.** Dispatch should take one frame. Papyrus receipt and evaluation are bounded by the VM, and the existing post-acquisition decision took 1.3–1.6 s from the inventory event to acknowledgement. The handshake's decision path does less work (no removal) but runs on the same VM, so feedback around 1 s after activation would be a plausible first result.

The tome never leaves the world, so the latency changes **when** feedback appears, not **whether** the book disappears.

## 6. Runtime test procedure (not run)

Markers go in `Documents\My Games\Skyrim Special Edition\SKSE\`:
- **Add** `UntamedTomes.WorldTomeHandshake` (Firebolt only).
- **Keep** `UntamedTomes.EnforceTomeReads` and the trap markers. They only act on the post-acquisition path, which a handshake pickup no longer reaches.
- **`UntamedTomes.VetoTestTomePickup`** can stay. The handshake supersedes it (`veto_test_superseded=true`).
- **Optional:** `UntamedTomes.WorldTomeHandshakeAllTomes`, for every tagged tome.

**Startup checks.** The log must show `observer_load schema=16`, `world_tome_handshake_config … scope=test_tome`, `pickup_veto_ready … policy=world_tome_handshake`, `pickup_veto_slot_check … owner=ours`, and, after loading the save, `world_tome_handler_ready`.

**Setup.** Use a disposable save, base Magicka 100, threshold 150, a dungeon (not a safe context), and `player.placeatme 000A26FD` twice.

| # | Action | Expected | Rows |
| --- | --- | --- | --- |
| H1 | Take Firebolt, ineligible | Stays in place; shock pulse on the book; "refuses you" | `veto_and_request reason=new_request`; `dispatched`; `received`; `answer outcome=reject-ineligible status=rejected`; `feedback kind=refusal shader=played` |
| H2 | Take it again at once, then after 3 s | First attempt: silent veto. Second attempt: a fresh request, rejected again, one more pulse. Never picked up | `veto reason=rejected_cooldown`, then `reason=reevaluate` |
| H3 | `player.setav magicka 200`, retry, then Take | Retry: "yields. Take it again." Take: picked up, no trap | `answer outcome=accept-eligible status=authorized`; `action=forward reason=authorized previous_called=1`; `world_tome_grant consumed=true`; `ledger_ack outcome=accept-preauthorized`; no `defense_effect` |
| H4 | Eligible, take the second copy | The same as the H3 retry | `reason=new_request` for the other reference |
| H5 | Authorised, then Read Or Take READ | No bypass: the read is denied (`pending_acquisition`) and the tome goes to inventory, as for any world READ. Reading it there teaches through DEST and ISL | `tome_read_decision … decision=deny reason=pending_acquisition`; then an accepted inventory read |
| H6 | Two copies: reject one, authorise the other | Independent states | Different `request=` IDs and per-reference rows |
| H7 | Activate, then quickload within about 1 s | Nothing happens to the tome; it is usable after loading | `world_tome_handshake_reset entries_discarded=1`, then a stale cancellation or answer, or none |
| H8 | Another item, an ordinary book, a skill book | Vanilla | No handshake rows. Other tomes log `reason=not_test_tome` |
| H9 | Chest Take of a tome | The existing path, unchanged | No activation rows; `ledger_add`, Papyrus decision, trap if ineligible |

For H3, `player.setav magicka 200` sets base Magicka, which is the value the rule reads. Lowering the threshold global below 100 works as well.

After the run, copy `UntamedTomesSKSE.log` and `Papyrus.0.log` before launching again.

## 7. Compatibility and limitations

- **Supported runtime:** 1.7.104 only. The handshake replaces the same vtable slot as Inv. 18, so the same `bypassed=1` detection applies.
- **Read Or Take:** its handler is called only on authorised activations or fallback forwards. A vetoed activation never reaches it, so it shows no prompt and no read.
- **Unified read enforcement, DEST 1.2.3 and DESTified with Script Fixes:** unchanged. A world READ still becomes a Take (H5), the existing limitation.
- **Two activations needed:** an eligible or exempt character must activate twice, including in towns, shops and inns, where the exemption applies. Automatic replay is out of scope.
- **Grants by base:** the 5 s grant is keyed by base. A different copy of the same base added from a chest inside that window would consume it and skip its evaluation.
- **Mod disabled through the global:** still costs one extra activation (Exempt). Removing the marker removes the hook entirely.
- **Not covered:** QuickLoot-style transfers, container Take, and inventory reads all keep their current paths. NPC activations are forwarded.
- **ModEvent sender:** if the reference does not arrive as an `ObjectReference`, Papyrus answers `unavailable-no-reference`. Native code then reports `reference_mismatch`, and the request times out into the fallback. The logs would show this on the first run.

## 8. Rollback

**Undo the experiment:** delete `UntamedTomes.WorldTomeHandshake` and `UntamedTomes.WorldTomeHandshakeAllTomes`. With no marker the slot is not wrapped. With only `VetoTestTomePickup`, schema 15 behaviour returns.

**Full rollback:** copy the following from `task11-preservation/` into the MO2 mod:

| Preserved file | Install as |
| --- | --- |
| `pre-task11-schema15.dll` and `.pdb` | `SKSE\Plugins\UntamedTomesSKSE.dll` and `.pdb` |
| `pre-task11-UT_PlayerMonitor.pex` (the Task 09 PEX) | `Scripts\UT_PlayerMonitor.pex` |

The new PEX adds no script variables, so the save needs no clean-up after a rollback.
