# Investigation 12 — Controlled Read Or Take world-READ denial

## Status

The schema 8 native build adds an opt-in experiment that refuses one demonstrated path: a player spell-tome read issued by Read Or Take from inside its book activation handler. On 15 November 2026 it was runtime-tested on Skyrim 1.7.104. Native and Papyrus logs confirm four world-READ denials, each followed by Papyrus rejection and removal, and one unchanged inventory read. The world-read spell-list outcome, the TAKE, book, rollback and unsupported-caller cases, and every other runtime or load order are not yet verified. This is a developer experiment, not a production read guard.

## Root cause and identification

The Task 03 classifier run, preserved as `task04-preservation/classifier-ab-*.log` in the native checkout, recorded two reads:

- **World READ.** `po3_ReadOrTakeBooks.dll` caller RVA `256C` on a worker thread, classified `unknown/off_main_thread`. `Read` returned true. Papyrus logged `eligible=False` and then `removal=skipped-empty-inventory`.
- **Inventory READ.** `SkyrimSE.exe` caller RVA `945D9C` on the main thread with InventoryMenu open.

The world read teaches the spell and consumes the tome inside Read Or Take's activation call, before the asynchronous Papyrus pickup handler can decide.

### Read Or Take binary

The installed DLL (SHA-256 `5037F69E3E9A0A9CB18A19E6C1F3835BC061227604BE5C6B52E0B6B58C2938BA`, Inv. 07) and its shipped PDB were inspected with `dumpbin /pdata /disasm` (MSVC 14.51):

- Return address `256C` lies in `Book::Hooks::Activate::detail::activate_book` (RVA `20D0–25C9`).
- It resolves Address Library ID `0x45B2` (17842, `TESObjectBOOK::Read`) at `2536` and calls it at `256A`.
- `test al,al; je 25A1` skips the following `call [rax+2B0h]` when `Read` returns false. That call is the actor's `RemoveItem` vfunc. The book has already been picked up, so a denied read leaves it in the player's inventory.
- `activate_book` is reached only through `call` instructions at `2732` and `275E` in `Book::Hooks::Activate::thunk` (RVA `25D0–27A8`). There is no tail jump.
- These facts describe this binary only.

### Identification rule

Denial (`src/WorldReadDenial.h`, `DecideWorldRead`) requires all of the following. Thread identity is not an input.

1. The `UntamedTomes.DenyReadOrTakeWorld` experiment is selected.
2. The reader is the player.
3. The book has the teaching flag and a resolved linked spell.
4. The immediate return address lies in a module named `po3_ReadOrTakeBooks.dll`. The name narrows denial to the one handler whose false-return behaviour was verified. It is not treated as evidence of a world read.
5. The live `TESObjectBOOK` vtable slot `0x37` (`Activate`, read through CommonLib `VTABLE_TESObjectBOOK[0]`) points into that module.
6. A frame from `RtlCaptureStackBackTrace` (up to 16 frames) has an x64 unwind entry whose function begins exactly at the slot address.

No fixed executable or Read Or Take RVA is used. Every missing, unresolved or mismatched observation forwards, with a specific reason (`caller_unresolved`, `game_executable_caller`, `unverified_module_caller`, `activation_owner_unavailable`, `activation_owner_mismatch`, `activation_frame_unavailable`, `activation_frame_absent`, `non_player_reader`, `not_spell_tome`, `experiment_disabled`). An exception while gathering evidence also forwards, with `evidence_unavailable`.

## Implementation

| Native file | Change |
| --- | --- |
| `src/WorldReadDenial.h` | Pure evidence struct, `DecideWorldRead` and log strings. |
| `src/main.cpp` | `denyReadOrTakeWorld` flag. `GatherWorldReadEvidence` reads the caller module, the vtable slot owner and a stack-frame match. `LogWorldReadDecision`. A decision step inside the existing `ObserveBookRead<0>` entry detour. Marker `UntamedTomes.DenyReadOrTakeWorld`. The enter row reports the active mode. `schema=8`. `marker_check_error` ignores not-found results: MSVC reports a missing file through the error code, which made Task 03A config rows show `true`. |
| `tests/world_read_denial.cpp` | Compile-time tests of the decision. |

There is no second hook. The 1.7.104 gate, relocation and body-hash check, call-site checks, competing-module refusal, mutual exclusion and install diagnostics are unchanged. A denied read returns `false` without calling the original, and changes no spell, inventory, Papyrus or ESP state. Every other read calls the original exactly once and returns its result. In this mode the Task 03 classifier row is also logged.

### Marker

Use an empty file at `%USERPROFILE%\Documents\My Games\Skyrim Special Edition\SKSE\UntamedTomes.DenyReadOrTakeWorld`, with no other `UntamedTomes.*` experiment marker in that folder. Any second marker logs `conflicting_probe_modes` and installs nothing.

### Decision row

`event=tome_read_decision` carries:

- read ID and session;
- book, spell and reader;
- current and main thread;
- `caller` category, `caller_module` and `caller_rva`;
- `activation_module` and `activation_rva` (the live slot target);
- `activation_owned_by_caller`, `inside_activation_handler`, `activation_frame` and `stack_frames`;
- `decision`, `reason`, `original_invoked` and `original_result`, where `-1` means not invoked.

A denial is logged before returning. A forward is logged after the original returns. The `read` ID joins this row to `tome_read_enter`, `tome_read_observed` and, for forwards, `tome_read_exit`. Ordinary and skill books produce no rows.

## Runtime results, 15 November 2026

### Environment and build

- Skyrim `1.7.104.0` through MO2, with SKSE and the format-5 Address Library from Inv. 04.
- Read Or Take 1.5.1 (hash above) enabled.
- Untamed Tomes threshold 150 and base Magicka 100, as logged by Papyrus.
- Debug logging on.
- Deployed `UntamedTomesSKSE.dll` SHA-256 `BBA3EA858F491945B2C01BA92A8A8DAC7215BA7B494072B38E5BF05E69E69DE1`. This is identical to the preserved `task04-preservation/world-read-denial.dll`, and the source has not changed since that build.

The session logs were preserved from the live log locations as:

- `task04-preservation/schema8-world-read-denial-20261115-1145-native.log` (from `UntamedTomesSKSE.log`);
- `task04-preservation/schema8-world-read-denial-20261115-1145-papyrus.log` (from `Papyrus.0.log`, opened 11:45:24).

The renamed copies `UntamedTomesSKSE(2).log` and `Papyrus.0(20261115-094943).log` named in the task brief were not found on this machine. The live files have matching timestamps (11:45–11:49 local). Checksums for every preserved file are in `task04-preservation/SHA256SUMS.txt`.

### Startup (verified by native log)

At 11:45:18 the log shows:

- `observer_load schema=8`
- `runtime_verified executable_version=1.7.104.0 address_library_format=5`
- `tome_read_probe_config ... classify_read=false deny_read_or_take_world=true marker_check_error=false selected=deny_read_or_take_world`
- `tome_read_probe_install attempted=1 mode=deny_read_or_take_world strategy=entry`
- `tome_read_probe_ready mode=deny_read_or_take_world strategy=entry target=280290`

### World READ denials

**Verified by native log.** All four rows have reader `00000014`, `caller=read_or_take`, `caller_module=po3_ReadOrTakeBooks.dll`, `caller_rva=256C`, `activation_module=po3_ReadOrTakeBooks.dll`, `activation_rva=25D0`, `activation_owned_by_caller=1`, `inside_activation_handler=1`, `activation_frame=3`, `stack_frames=16`, `decision=deny`, `reason=confirmed_read_or_take_world_path`, `original_invoked=0` and `original_result=-1`. The live slot held the thunk's entry RVA `25D0`, as predicted from the disassembly. All four ran off the main thread (21472) and were classified `unknown/off_main_thread`.

| Read | Native time | Book | Spell | Thread | Papyrus decision | Papyrus removal |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 11:47:57.460 | `000A26FD` (Firebolt) | `00012FD0` | 16772 | `eligible=False` at 0.671 s | `after RemoveItem` at 0.887 s |
| 2 | 11:48:11.373 | `000A2705` | `0003AEA3` | 16772 | `eligible=False` at 0.765 s | `after RemoveItem` at 0.981 s |
| 3 | 11:48:12.055 | `000A26F9` (Dead Thrall) | `0007E8DF` | 13712 | `eligible=False` at 0.702 s | `after RemoveItem` at 0.945 s |
| 4 | 11:48:14.438 | `00109112` | `00109111` | 16772 | `eligible=False` at 0.738 s | `after RemoveItem` at 0.981 s |

Papyrus times are elapsed from handler entry. All entries report `count=1 ref=None source=None` with no menu open, and none reports `skipped-empty-inventory`.

**Verified by native log (inventory sequence).** For each read, the immediate inbound inventory notification for the same BOOK, with source `00000000`, preceded `tome_read_enter` by about 0.2–0.6 ms. This matches Read Or Take's pickup-before-read order. Deferred rows then show an inbound and an outbound change for each book. No `spells_learned_notification` occurred in session 2. The only one in the whole log is during the inventory read below. That notification carries no spell ID, so its absence is supporting evidence, not proof that the spells were not learned.

**Verified by Papyrus log.** Four `[UntamedTomes][Pickup` entries match the native book order, each with `baseMagicka=100 threshold=150 eligible=False` and a completed `RemoveItem` bracket.

**Verified by direct gameplay observation.** The user reported that native denial was confirmed. A spell-list check after the world reads, and the final inventory counts, were not separately recorded.

### Inventory READ regression

**Verified by native log.** After a reload (session 4), a Firebolt inbound with source `00000000` occurred on the main thread at 11:48:49. Read 5 at 11:49:03.786 ran on main thread 21472 with InventoryMenu open, caller `SkyrimSE.exe` RVA `945D9C`, classified `player_inventory`. The decision was `forward`, `reason=game_executable_caller`, `activation_owned_by_caller=0`, `inside_activation_handler=0`, `original_invoked=1` and `original_result=1`. The enter row shows `known_before=0`. A `spells_learned_notification` occurred inside the call. The exit row shows `original_result=true` and `known_after=1`, followed by an outbound Firebolt row.

**Papyrus log.** There is no pickup entry for the session 4 inbound. This is consistent with Untamed Tomes being disabled while the tome was added, as the checklist prescribes, but the log alone does not prove it.

**Direct gameplay observation.** The user reported that the spell was learned.

### Runtime matrix

| Test | Result | Basis |
| --- | --- | --- |
| Hook installation | **Pass** | Native startup rows |
| A1 World READ Firebolt | **Partial** | Native denial and Papyrus removal verified. Final spell list and count not recorded. |
| A2 World READ second tome | **Partial** | As A1, for `000A2705`. Two further tomes (`000A26F9`, `00109112`) behaved the same. |
| B1 Inventory READ | **Pass** | Native forward with `known_before=0` and `known_after=1`, plus the user report |
| B2 World TAKE | Not tested | No TAKE was performed |
| C1 Ordinary book | Not tested | |
| C2 Skill book | Not tested | |
| D1 Marker removed | Not tested | |
| D2 Unsupported caller | Not tested | No such read occurred. The inventory forward exercises `game_executable_caller` only. |

### Observations and discrepancies

- Reads 2 and 3 were 0.68 s apart on different worker threads (16772 and 13712). Their Papyrus handlers overlapped, and both completed removal.
- The first decision took about 5 ms from the enter row. Later decisions took under 0.1 ms. The first stack capture and module lookups are slower.
- The `tome_read_observed` row prints `mode=classify` in denial mode, because the label is hard-coded in the classifier logger. This is cosmetic only. The enter and decision rows carry the correct mode.
- The deferred queue reported `discarded=0` at every session change, and every captured tome change was resolved.
- Each Papyrus removal followed its native denial by roughly 0.9 s. During that window the denied tome is in the player's inventory. An inventory read inside the window would be forwarded. This was not exercised.

## Offline results

`cl /std:c++20 /W4 /WX /EHsc` passes `world_read_denial` (16 cases) and the unchanged `tome_read_context`, `tome_read_decision` and `observation_queue` suites, rerun on 15 November 2026 after the runtime session. A negative control asserting denial for another module failed to compile, which confirms the assertions are evaluated.

## Rollback

- **Experiment off:** delete `UntamedTomes.DenyReadOrTakeWorld`. Without any marker, the schema 8 DLL installs no read hook. A running game keeps an installed hook until it exits.
- **Previous builds** in the native checkout, copied over `D:\Modding\Ancestries\mods\Untamed Tomes\SKSE\Plugins\UntamedTomesSKSE.dll` and `.pdb`:
  - `classifier-preservation/classifier-diagnostics.dll` (`883459F0…`, schema 7 with startup diagnostics);
  - `classifier-preservation/pre-classifier-forwarding.dll` (`D116BC7D…`).
  - The runtime-tested schema 8 build is `task04-preservation/world-read-denial.dll` (`BBA3EA85…`).
- The preservation folders hold binaries and logs and are ignored by Git. They exist only in the local native checkout, and `SHA256SUMS.txt` is tracked.

## Compatibility limitations

- Skyrim 1.7.104 only. DEST, Lodestone, SpellLearning and Heart of Magic prevent installation.
- Only Read Or Take 1.5.1's activation path is recognised. A renamed DLL, another activation replacement, a later re-hook of book `Activate`, or a jump stub in the slot all forward. None of these is tested.
- Denial relies on Read Or Take skipping `RemoveItem` when `Read` returns false. This was verified for this binary.
- With Read Or Take, a world READ always becomes a Take. Below threshold in a dungeon the tome is then removed by Papyrus. In a safe context it stays and can be read from the inventory. The activation prompt still says Read, and there is no denial feedback.
- Container-side reads and the inventory-read window after a denial are not addressed.
- Native and Papyrus still decide independently. Denial is safe here only because native code makes no eligibility decision.

## Next step

Before any further interception work, complete B2, C1, C2, D1 and D2, and record the spell list and inventory count after a world READ. The architectural question for the next phase is the single ownership of each acquisition and read (Inv. 10), not further caller recognition.
