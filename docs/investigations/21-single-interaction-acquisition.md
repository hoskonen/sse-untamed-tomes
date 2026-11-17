# Investigation 21 — Single-interaction world tome acquisition

## Status

Schema 18 continues an authorised world-tome activation automatically, so an eligible or exempt character takes the tome with **one** Take. It is built, tested offline (10 of 10 suites; the handshake suite has 37 cases) and deployed. Nothing is committed.

| File | SHA-256 |
| --- | --- |
| DLL | `FB4733AEFC8E13DEF5EB18C25CC9B29EAC860EE240D2FF6DC9689FE7F0190F7D` |
| PEX | `D72BAE8C198B0ABC4B94E1CCA4CCBC6FED99EB2F2FF3B913E945D3AFAF1CFB1A` |

Both are in `task14-preservation/` in the native checkout, with the schema 17 rollback set and a SHA-256 manifest. The baseline is native `b4a8568` and Papyrus `90cc852`.

**Runtime-tested in part (17 November 2026; evidence in [Inv. 22 §1](22-native-eligibility-feasibility.md#1-current-architecture-and-measured-latency) and `task15a-preservation/`):**
- **Verified:**
  - single-Take automatic pickups (requests 2, 3 and 4, complete 684–701 ms after activation, `consumed=true`);
  - two references, each continued independently;
  - rejection;
  - cancellation on movement (`player_moved` at 128.6 units), followed by a working manual Take.
- **Not yet exercised from §6:** menu, save and load during evaluation, ownership, Riverwood, mod disabled, inventory study, and the manual-take marker.

Unchanged: the eligibility rules, the post-acquisition path, the veto, refusal and its cooldown, the grant correlation, and the timeout and failure handling.

## 1. What `ActivateRef` does around the book vfunc (static, 1.7.104)

`TESObjectREFR::ActivateRef` (AE 19796, RVA `2F11B0`) was disassembled from `SkyrimSE.exe`. Its call targets were mapped to Address Library IDs and named where CommonLib names them.

| Order | Call | Meaning |
| --- | --- | --- |
| Before the vfunc | `ScriptEventSourceHolder::GetSingleton` (14298) at `2F15A2`, followed by a dispatch | The `TESActivateEvent` and Papyrus `OnActivate` path. It runs for vetoed activations too |
| Before the vfunc | `TESObjectREFR::InitChildActivates` (20264) at `2F1843` | Linked child activations |
| The vfunc | `call [rax+1B8h]` at `2F186A`, which is `TESObjectBOOK::Activate` (slot `0x37`): the Untamed Tomes thunk, then Read Or Take or vanilla | The pickup, read or take |
| After a true return | AE 37864 at `2F189A`, 40512, `Actor::DispelAlteredStates` (38819) at `2F18FA`, 20053, 20037 | Post-activation work. Activation breaks invisibility |
| On false | `je 2F18CF`, skipping the above | This is how the veto works (Inv. 18) |

Theft and crime are not handled in `ActivateRef`'s visible body. The engine predicate `TESObjectREFR::IsCrimeToActivate` (AE 19827) is what the "Steal" prompt uses.

## 2. Options evaluated

| Option | Equivalent to normal activation? | Verdict |
| --- | --- | --- |
| **Re-invoke `ActivateRef(player, …)` from an SKSE task, with the original arguments** | Yes, apart from input state. The same engine path as the manual second Take that schema 17 verified at runtime (Inv. 20 §12): event, `OnActivate`, child activations, thunk, Read Or Take, pickup, post-activation and invisibility break | **Chosen** |
| Call the captured previous handler directly | No. It skips the activate event and `OnActivate`, child activations and all post-activation work, including the invisibility break | Rejected |
| Papyrus `ObjectReference.Activate(player)` from the answer handler | Probably reaches `ActivateRef`, but runs from the VM, a different context, after the answer and without the native re-validation | Rejected: the continuation must be validated and executed at one native boundary |
| `PlayerCharacter::PickUpObject` | No. It bypasses Read Or Take and the book vfunc | Rejected |

**One-shot authorisation for the replay.** The schema 17 table gains a `Continuing` state.

- `BeginContinuation` moves `Authorized` to `Continuing` for one request and one reference.
- The thunk forwards a `Continuing` entry only for the replay: a thread-local `continuationRef` that is set only on the task thread during the `ActivateRef` call. The reason is `continued_authorized`.
- Any other activation of that reference is vetoed (`continuation_in_progress`), so there is never a second forward.
- `EndContinuation` runs after the replay returns. If the replay never reached the thunk (for example, a script blocked activation), the entry returns to `Authorized` and the manual Take still works.

## 3. Behaviour

1. **Take:** veto and request, unchanged.
2. **Answer:** Papyrus answers `accept-*` or `disabled`. The native answer sets `Authorized` and posts an SKSE task (`world_tome_continuation stage=scheduled`). It never activates from the Papyrus VM thread.
3. **Task:** checks run in order. Generation and authorisation come first, before the stored handle is touched. Then it resolves the handle to a counted `NiPointer` and evaluates `CheckContinuation`:

   | Cancel reason | Condition |
   | --- | --- |
   | `disabled` | The `UntamedTomes.WorldTomeManualTake` marker is present |
   | `stale_generation` | A load or new game happened |
   | `not_authorized` | Consumed by a manual Take, expired, or reset |
   | `reference_unavailable` | The handle doesn't resolve, or resolves to another FormID |
   | `reference_not_live` | Deleted or disabled |
   | `reference_not_3d` | Unloaded |
   | `cell_changed` | The tome left its activation cell, or the player is not in it |
   | `player_invalid` | No player, or dead |
   | `menu_open` | A pausing menu, dialogue, console or loading screen |
   | `ownership` | `IsCrimeToActivate`: never automatic |
   | `too_late` | More than 3 s since the activation |
   | `too_far` | Player more than 256 units from the tome |
   | `player_moved` | More than 128 units since the activation |

4. **Replay:** `ActivateRef(player, arg3, object, count, false)` with the arguments the engine passed to the original vetoed activation (logged as `arg3=`, `object=`, `count=`). The thunk forwards it (`continued_authorized`). The existing `ForwardContext` binds the grant only if an inventory transfer actually happens during the call. `OnItemAdded` then consumes it (`accept-preauthorized`): no second evaluation, no trap.
5. **Result:** `world_tome_continuation stage=replayed activate_result= consumed= fallback=`.
6. **Feedback.**
   - Papyrus says "*X* yields."
   - If the continuation is cancelled, or the replay is not consumed, native code adds "The tome yields. Take it again." The authorisation then stays for its 30 s window: the schema 17 behaviour.
   - When the tome is gone, unloaded or in another cell, nothing is shown.

**Ownership.** An owned tome is **never** continued automatically. The player has to press Take or Steal again, which goes through the engine's normal crime handling. Picking up still happens only through the engine's own path, so ownership cannot be bypassed in either case.

**Grants.** A failed or cancelled continuation creates no grant: binding requires an inventory event inside the forwarded call.

## 4. Compatibility

| System | Effect |
| --- | --- |
| Read Or Take | With `iDefaultAction = 0` and `bAutoUseSpellTomes = true`, an unread tome activation is a READ. Read Or Take picks the tome up, then unified enforcement denies the read (`pending_acquisition`), so the tome lands in inventory unread. That is the same outcome as the verified schema 17 manual Take (Inv. 20 §12). The replay is not made under the original input state, so holding the alternate-action hotkey (Left Shift) at Take time is not preserved. Both actions end in "tome in inventory" anyway |
| DEST 1.2.3 and DESTified | Nothing is read during acquisition, so no study starts there. Study begins with the normal inventory read, which forwards through the DEST-compatible hook |
| Duplicates | One forward per authorisation, enforced by the `Continuing` token. One grant per actual transfer |
| Containers, non-player activations, ordinary books | Unchanged: the scope filter is untouched |
| Papyrus | The script and natives are unchanged apart from the shorter "yields." text. Signatures are unchanged, so the schema 17 PEX would still bind |
| Activate events | The replay raises a second `TESActivateEvent` and `OnActivate` on the tome, exactly as the manual second Take does today |

## 5. Offline tests (`world_tome_handshake`, 11 new cases)

- **Replay:** consumes once and binds to the right request; a second continuation cannot start.
- **Manual activation:** during a continuation it is vetoed with no new request; before the continuation it wins, and the continuation finds nothing.
- **Replay that never reaches the thunk:** reverts to `Authorized`, with no grant and a manual Take still possible.
- **Replay whose pickup fails:** consumed, but no grant.
- **States that cannot continue:** Pending, Rejected and Unavailable.
- **Reference specificity:** another reference's request cannot be continued, and a rejected sibling stays protected.
- **Load during a continuation:** voids it.
- **Expiry:** an expired authorisation cannot start.
- **Bounding:** a stuck `Continuing` entry is pruned.
- **Policy:** every cancel reason, including NaN distance and ownership taking precedence over timing.

## 6. In-game test procedure (not run)

**Markers:** unchanged (`WorldTomeHandshake`, `EnforceTomeReads`, `DebugTrap`, `FireTrap`).

**Startup checks:**
- `observer_load schema=18`;
- `world_tome_handshake_config … auto_continue=true continue_max_delay_ms=3000 continue_max_distance=256 continue_max_displacement=128`.

**Setup:** threshold 150, base Magicka 100, in Bleak Falls Barrow. Place three Firebolt tomes with `player.placeatme 000A26FD` three times. Lower the threshold through the MCM to make the character eligible.

| # | Action | Expected | Key rows |
| --- | --- | --- | --- |
| S1 | Ineligible: Take T1 once | Stays; pulse; "refuses you" | `reject-ineligible`; **no** `world_tome_continuation` |
| S2 | Threshold 100: Take T1 once and wait | Picked up about 0.7 s later; "yields"; no trap | `stage=scheduled` → `stage=replaying arg3= object= count=` → `world_tome_activation reason=continued_authorized continuation=true` → `world_tome_acquisition stage=bound request=<same>` → `stage=replayed activate_result=true consumed=true` → `world_tome_grant match=anonymous_stack` → `ledger_ack accept-preauthorized` |
| S3 | `player.getitemcount 000A26FD`; check T1 gone | Count up by 1; `after: … deleted=true` | |
| S4 | Take T2 and T3 quickly, one press each | Both arrive; each grant names its own `world_ref` | Two `replayed consumed=true` |
| S5 | Place T4; Take it and immediately walk away (more than 128 units) | Not picked up; "Take it again"; walking back and taking it works once | `stage=cancelled reason=player_moved fallback=manual_take`, then `reason=authorized` |
| S6 | Place T5; Take it and immediately open the inventory | `reason=menu_open`; the manual Take works | |
| S7 | Place T6; Take it and quicksave and quickload at once | No pickup after the load | `world_tome_handshake_reset`, then `stale_generation` or `not_authorized`, or no continuation at all |
| S8 | Inventory read of an acquired Firebolt | Accepted inventory read, forwarded; DESTified study starts (check its own messages) | `tome_read_decision … decision=forward` |
| S9 | An owned Firebolt (place it in a shop, or set ownership with `setownership`) | Not automatic: "Take it again"; the second press is a normal Steal with crime | `reason=ownership crime=true` |
| S10 | Riverwood (safe location), Magicka 100 | One Take is enough | `accept-safe-context`, then `replayed consumed=true` |
| S11 | Mod disabled in the MCM | One Take is enough | `outcome=disabled`, then `replayed` |
| S12 | Ordinary book, skill book, another tome | Vanilla | No continuation rows |
| S13 | Optional: add the `UntamedTomes.WorldTomeManualTake` marker and restart | The schema 17 two-Take flow | `reason=disabled fallback=manual_take`, plus "Take it again" |

Preserve `UntamedTomesSKSE.log` and `Papyrus.0.log` after the run.

## 7. Limitations and risks

- **Unverified context.** Calling `ActivateRef` from an SKSE task outside a player input frame is untested in game. The thunk, Read Or Take and the pickup are all reached through the same vfunc call, but the input-dependent state (crosshair, hotkeys) is not reproduced.
- **Read Or Take hotkey.** The alternate-action hotkey state at Take time is not carried into the replay.
- **Fixed thresholds.** 3 s, 256 units and 128 units are conservative guesses, not measured activation reach.
- **Owned tomes.** They always need two presses, by design.
- **Second activate event.** Scripts listening to `OnActivate` on a tome see two activations, as they do today with two presses.
- **Replay that does not consume.** The replay could reach `ActivateRef` and return without calling the vfunc. The entry then falls back to the manual Take and is logged `consumed=false`.
- **Still open from Inv. 20 §13:** study completion, exemptions, failure recovery in game, Read Or Take disabled, and the full load order.

## 8. Rollback

| Goal | How |
| --- | --- |
| Back to two Takes, no file changes | Add the empty marker `UntamedTomes.WorldTomeManualTake` and restart |
| Full rollback to schema 17 | Copy `pre-task14-schema17.dll`, `.pdb` and `pre-task14-UT_PlayerMonitor.pex` from `task14-preservation/` into the MO2 mod (`SKSE\Plugins\UntamedTomesSKSE.dll` and `.pdb`, `Scripts\UT_PlayerMonitor.pex`), or check out `b4a8568` and `90cc852` |
| Disable the handshake | Remove the `UntamedTomes.WorldTomeHandshake` marker |
