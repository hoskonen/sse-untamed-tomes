# Investigation 18 — Pre-pickup tome activation feasibility

## Status

Schema 15 adds an opt-in prototype that vetoes the player's first Take of each world reference of one test tome (Spell Tome: Firebolt, `Skyrim.esm 000A26FD`) before Skyrim transfers it. Eligibility is not evaluated. It builds cleanly and all nine offline suites pass. The DLL is deployed (`B80AB1B62C1ADB7EAED502529E9BBB75200E39675DE6EF3D6BC3340F664A3EAA`, preserved as `task10-preservation/pickup-veto-schema15.dll`). Papyrus is unchanged. **The veto has not been run in game.**

## 1. Activation path on 1.7.104 (static)

| Step | Evidence |
| --- | --- |
| `TESObjectREFR::ActivateRef` (AE 19796, RVA `2F11B0`) dispatches to the base object's `Activate` through `call [rax+1B8h]` at `2F186A`. That is vtable slot `0x37`, the `TESObjectBOOK::Activate` override declared in CommonLib. | Disassembly of the executable |
| `test al,al; je 2F18CF`: on **false**, `ActivateRef` skips its post-activation work (the call at `6A77C0` and the flag at `1431DF3DC`) and returns. There is no fallback activation. | Disassembly |
| Without Read Or Take, vanilla book `Activate` for a spell tome picks it up with no BookMenu. | Runtime, Inv. 07 (08D control) |
| Read Or Take 1.5.1 replaces slot `0x37` with `Book::Hooks::Activate::thunk` from its `kPostLoad` handler (`MessageHandler`, message type 0 → `Install@Hooks@Book`). Its thunk **never calls the previous handler**; it always runs `activate_book` (`PickUpObject`, then optionally `Read` and `RemoveItem`). | Disassembly of the Read Or Take DLL with its PDB |
| Untamed Tomes installs at `kPostPostLoad`, after Read Or Take, so it captures Read Or Take's thunk, or vanilla when Read Or Take is absent, as the "previous" handler. | SKSE message ordering and the logs above |

**Earliest safe point:** the `Activate` vfunc for books. It receives the live target reference, the activator and the count, runs before any inventory transfer, and is specific to books. The pickup itself happens inside the previous handler. The activation event and Papyrus `OnActivate` are raised by `ActivateRef` independently of the result. Whether they come before or after the vfunc was not traced.

## 2. Prototype

| File | Change |
| --- | --- |
| `src/PickupVeto.h` (new) | Pure `Decide`. It vetoes only when the experiment is enabled, the activator is the player, the base teaches a spell, the base is the test tome, the target is live (not deleted or disabled), and that reference has not been vetoed this session. Every other case forwards with a reason. |
| `src/main.cpp` | `BookActivateThunk` is installed with `write_vfunc(0x37)` on `VTABLE_TESObjectBOOK[0]` by `InstallPickupVeto` at `kPostPostLoad`. It applies only with the marker, on 1.7.104 only, and is refused when `DenyReadOrTakeWorld` (schema 8) is active, because that mode identifies Read Or Take by ownership of this slot. On veto it returns false without calling the previous handler. Otherwise it calls the previous handler exactly once and returns its result. `VerifyPickupVetoSlot` at `kDataLoaded` reports whether a later plugin replaced the slot (`bypassed=1`). The vetoed-reference set is cleared on every load and new game. `schema=15`. |
| `tests/pickup_veto.cpp` (new) | The veto on the first attempt; forwarding on the second attempt, when disabled, for NPCs, other tomes, ordinary and skill books, and dead targets. |

The marker is an empty `UntamedTomes.VetoTestTomePickup` in `Documents\My Games\Skyrim Special Edition\SKSE\`. It is independent of the read-probe markers and the trap markers.

Log rows:

- **Startup:** `pickup_veto_ready … previous_module=<po3_ReadOrTakeBooks.dll | SkyrimSE.exe> previous_rva=…`, then `pickup_veto_slot_check when=data_loaded owner=ours`.
- **Veto:** `pickup_veto decision=veto reason=test_tome_first_attempt activation= elapsed_us= thread= base= activator= previous_called=0 ref= deleted= disabled= ref_3d= xyz= cell=`.
- **Forward** (player spell tomes only): `pickup_veto decision=forward reason=…` before the call, then `pickup_veto_forwarded previous_result= after: ref=… deleted= disabled=`.

The veto calls no Papyrus, does no inventory work and does not wait.

## Runtime results (16 November 2026, 18:07)

The run is preserved as `task11-preservation/schema15-veto-session-20261116-1807-*.log` in the native checkout.

**V1, V2 and V3 verified by the native log:**

- **V1:** the first Firebolt activation of `FF000F0C` was vetoed (`ref_3d=true`, xyz unchanged). No inventory, ledger or Papyrus row followed.
- **V2:** the second activation was forwarded (`already_vetoed_once`) to Read Or Take. That was a READ: unified enforcement denied it (`pending_acquisition`), and the tome was picked up (`deleted=true` after). Papyrus then logged `reject-removed`, and the fire trap ran (`hit_not_observed`).
- **V3:** `000A2705` and `000A26F9` were forwarded with `not_test_tome`.
- **Slot:** the previous module was `po3_ReadOrTakeBooks.dll` (RVA `25D0`), and the data-load check reported `owner=ours`.
- **Threads:** activations ran on worker threads 14368, 11404 and 13672; the main thread was 26440.

V4 to V7 were not run. Investigation 19 builds on these results.

## 3. Test procedure

Profile: the current markers plus `UntamedTomes.VetoTestTomePickup`. The trap markers may stay; a vetoed Take produces no acquisition, so no trap fires. Place a Firebolt tome in the world in a disposable save (`player.placeatme 000A26FD`).

| # | Action | Expected | Records |
| --- | --- | --- | --- |
| V1 | Take or Read the Firebolt tome (Read Or Take on) | **The tome stays in place.** No `ledger_add`, no read rows, no Papyrus pickup row, no trap. | `pickup_veto decision=veto … ref_3d=1 xyz=…` |
| V2 | Activate the same tome again | Normal Read Or Take behaviour: Take, or READ denied by unified enforcement, then Papyrus rejection and the trap | `decision=forward reason=already_vetoed_once`, then `pickup_veto_forwarded … deleted=` |
| V3 | Take another tome (for example `000A2705`) and an ordinary item | Unchanged | `forward reason=not_test_tome`; nothing for non-books |
| V4 | Ordinary and skill book activation | Unchanged | No rows (`not_spell_tome` is not logged) |
| V5 | Repeat V1 with Read Or Take disabled | The tome stays; the second Take picks it up (vanilla) | `previous_module=SkyrimSE.exe` |
| V6 | Save and reload after V1, then activate | Vetoed once again (the set is cleared on load) | A new `decision=veto` |
| V7 | Take the test tome from a chest | Not intercepted: container transfers do not call book `Activate` | No veto row; the normal ledger and Papyrus path runs |

Timing to compare: the `pickup_veto` capture is the activation itself. In the schema 14 run, the post-pickup trap reached its cast about 2.9 s after the activating read (Inv. 17).

## 4. Future eligibility integration (not implemented)

The decision must not wait for Papyrus inside `Activate`. A workable sequence:

1. On the first activation of an undecided tome reference, veto it and queue a request (reference handle, tome, activator, a generation ID) to Papyrus through a ModEvent or registration set. The tome stays in the world.
2. Papyrus applies the existing eligibility rule, with a new entry point taking the reference instead of an inventory addition, and answers through a native function.
3. **Eligible:** native code marks the reference allowed for a short window. It then either replays `ActivateRef(player)` on the main thread through an SKSE task, or lets the player's next activation pass. **Ineligible:** Papyrus runs the defense with the tome reference itself as the caster or explosion origin.
4. Load, cell unload, a deleted reference or an expired window cancel the pending request, with the same cancellation rules as Inv. 16.

This moves the world-pickup eligibility owner from `OnItemAdded` to activation for world references only. Containers and inventory reads keep their current paths.

## 5. Will this support an animation and a cast from the tome?

Yes, in principle. After a veto the original reference is still in the world with its 3D (`ref_3d` is logged), so it can be the caster: `Spell.Cast(tomeRef, player)`, `PlaceAtMe(explosion)` at the tome, `ApplyHavokImpulse` to make it jump, or a shader pulse (Inv. 05). This removes the XMarker workaround and the projectile origin problem, because the bolt would come from the book. Books have no behaviour graph, so "animation" means physics impulses or shaders, not animation events. All of this is untested.

## 6. Limitations

- **World references:** experimental and 1.7.104 only. One test tome, first attempt only. A plugin that replaces book `Activate` after `kPostPostLoad` bypasses the veto; this is detected and logged. The vtable wrapper affects every book activation, but filters to player spell tomes before doing anything. The order of activation events and Papyrus `OnActivate` relative to the veto is untraced. QuickLoot-style mods may activate or transfer items without book `Activate`.
- **Containers:** not covered. ContainerMenu Take and Take All transfer items without book `Activate`. Pre-transfer interception needs a different boundary (Inv. 06 and 10). The current post-acquisition Papyrus path and read enforcement remain in force.
- **Inventory reads:** not affected. They stay under the unified read gate (Inv. 14).
- **Interaction with schema 8:** refused when `DenyReadOrTakeWorld` is selected. Unified enforcement does not depend on slot ownership.
