# Investigation 15 — DESTified compatibility and the first trap trigger

## Status

| Item | State |
| --- | --- |
| Unified enforcement (`UntamedTomes.EnforceTomeReads`) | Built and offline-tested (Inv. 14). Not runtime-tested. |
| DESTified on Skyrim 1.7.104 | The bundled DEST 1.2.2 cannot load format 5 (static). **The separately installed DEST 1.2.3 can** and overrides it (static). Schema 12 adds verified coexistence. No DEST runtime session exists yet. |
| Debug trap (`UntamedTomes.DebugTrap`) | Built and deployed (schema 11 plus the new PEX). Not runtime-tested. |

## 1. Installed versions (verified from files)

| Mod (MO2 Default profile, enabled) | Version | Contents |
| --- | --- | --- |
| Immersive Spell Learning – DESTified | 2.0 RC3 (`meta.ini` 2.0.0.0, Nexus 45514) | `DEST_ISL.esp`; scripts `DEST_ISL_PlayerSpellLearningScript`, `DEST_AliasExt`, `DEST_UIExt` and an MCM config; **bundled `SKSE/Plugins/DontEatSpellTomes.dll` 1.2.2.0** (SHA-256 `12888C92…A7B24236`) with its PDB |
| Immersive Spell Learning – Script Fixes | 1.0.0 (Nexus 166224) | Replaces `DEST_ISL_PlayerSpellLearningScript.pex` and its source. It is above DESTified in `modlist.txt`, so it wins. |
| Read Or Take SKSE | 1.5.1 | Unchanged (Inv. 07, 12) |

The 17:38 launch `skse64.log` (preserved as `task07-preservation/skse64-20261115-1738.log`) lists Read Or Take and UntamedTomesSKSE but not `DontEatSpellTomes.dll`. DEST has therefore never run in a logged session.

## 2. How DESTified works (source and disassembly)

- **DEST 1.2.2** patches *inside* `TESObjectBOOK::Read` at `ProcessBook + 0x11D`, with REL::ID 17842 and pattern `48 8B 0D ?? ?? ?? ?? E8` (Inv. 05). On 1.7.104 that offset is `2803AD`. It is the `AddSpell` call sequence identified in Inv. 13, and the pattern matches the executable statically.
  - The patch skips the vanilla teaching block, forces `rsi = 0` (so `Read` returns false and no caller consumes the tome), and queues the Papyrus event `OnSpellTomeRead(Book, Spell, ObjectReference container)`.
- **ISL** (`DEST_ISL_PlayerSpellLearningScript`, Script Fixes version, `OnSpellTomeRead` at line 73):
  - It applies its own optional Magicka and school requirement (`baseMagReq`, `baseSchoolReq`).
  - It shows study message boxes, advances game time while studying (`Study`), and finally teaches through **`PlayerRef.AddSpell(akSpell, false)`** (line 284), or immediately for whitelisted tomes (line 108).
  - It never removes the tome, and it ignores `akContainer`.

### Static blocker: DEST 1.2.2 on 1.7.104

- `DontEatSpellTomes.dll` exports `SKSEPlugin_Version` with `versionIndependence=AddressLibraryPostAE` and `versionIndependenceEx=NoStructUse`. SKSE 2.3.1 is therefore expected to load it (decoded from the export).
- Its bundled CommonLib `REL::IDDatabase::header_t::read` (disassembly with its PDB) checks `cmp eax,2; jne` and otherwise calls `SKSE::stl::report_and_fail("Unsupported address library format…")`. `report_and_fail` shows a `MessageBoxW` and calls `TerminateProcess`.
- The only database for 1.7.104 in the profile is `versionlib-1-7-104-0.bin`, which is **format 5**. The 1.6.x files are format 2.
- **Hypothesis, with high confidence:** launching 1.7.104 with DESTified enabled terminates the game at startup, with an "Unsupported address library format" message box, as soon as DEST resolves an ID. It should be confirmed with one launch. Keep a save backup, and check `skse64.log` and the message box text.

DESTified can therefore only be evaluated on **1.6.1170** (the main machine, which has format-2 databases), or with a DEST build made against a format-5-capable CommonLib. Untamed Tomes' read hook is not ported to 1.6.1170 (Inv. 07).

### Hook interaction (static)

- Our entry detour sits at `Read+0` and DEST's patch at `Read+0x11D…0x18F`. They **do not overlap**. Our detour runs first on every call, and DEST's callback only runs if we forward.
- **Denying at our entry suppresses DEST's `OnSpellTomeRead`, so no study UI appears.** This follows from the call structure and has not been observed at runtime.
- Today our installer **refuses** whenever `DontEatSpellTomes.dll` is loaded (`competing_read_plugin`), and the `Read` body hash covers DEST's patch window. With DEST present, no Untamed Tomes read hook installs. Papyrus acquisition rejection still runs.
- **Bypass with DEST and no Untamed Tomes hook** (static and source-based): a Read Or Take world READ calls `Read`, so DEST queues the study prompt. The tome is not consumed. ISL's dialog opens while Papyrus rejects and removes the tome about 1 s later. ISL then teaches by `AddSpell` after studying, without ever checking that the tome is still present. A container-side read similarly lets the player study a chest tome without taking it.
- **Smallest safe integration**, once DEST can run (not implemented):
  1. Accept `DontEatSpellTomes.dll` only when the `Read` bytes **outside** DEST's documented window `[0x11D, 0x173)` match the original. That needs a second, window-excluded body hash computed from the executable.
  2. Keep refusing Lodestone, SpellLearning and Heart of Magic.
  3. Our existing pending and container denial then gates DEST's study prompt for undecided and container-side reads. Accepted inventory reads forward to DEST, and ISL studies normally.
  4. Verify on the target runtime that our entry trampoline and DEST's mid-body jump coexist in both load orders.

### Update: Don't Eat Spell Tomes 1.2.3 resolves the loader blocker (static)

The MO2 profile now also contains **Don't Eat Spell Tomes 1.2.3** (Nexus 43095, `meta.ini` 1.2.3.0, DLL SHA-256 `45E06173…67637F65`, built 2026-08-27). It ships its own `DEST_*` scripts. In `modlist.txt` it sits above DESTified (line 13 versus 14), so **its DLL and scripts override DESTified's bundled 1.2.2**. Findings from its own disassembly and PDB:

- **Address Library:** `header_t::read` accepts formats **1, 2 and 5** (`sub ecx,1; je`, `sub ecx,1; je`, `cmp ecx,3; jne → report_and_fail`). The 1.7.104 format-5 database is therefore supported, and the startup blocker above applies only to 1.2.2.
- **Version record:** `AddressLibraryPostAE` with `NoStructUse` (`versionIndependenceEx=3`). SKSE 2.3.1 is expected to load it.
- **Patch:** the same as 1.2.2. It resolves REL ID `0x45B2` (17842, `Read`), adds `0x11D`, checks `48 8B 0D … E8`, generates the stub with Xbyak, and guards and protects exactly **0x56** bytes. The window is `[0x11D, 0x173)`.
- **Timing:** `Hooks::Install` runs from DEST's messaging listener for message type 0 (`kPostLoad`). That is **before** Untamed Tomes installs at `kPostPostLoad`, so our check sees the already-patched body.

### Implemented: verified DEST coexistence (schema 12)

`src/ReadBodyCompat.h` (new) and `InstallReadProbe`:

- `DontEatSpellTomes.dll` is no longer refused by name. Lodestone (entry detour), SpellLearning and Heart of Magic still are.
- The `Read` body is classified as follows:
  - `original`: the full 0x249-byte FNV-1a equals `A0B7B66E2B2D53F0`. This was confirmed from the executable file.
  - `dest_window_patched`: DEST is loaded **and** the hash with `[0x11D, 0x173)` excluded equals `475471DA905339D6`, computed from the executable. This covers the entry bytes, the untouched tail before DEST's resume point at `+0x18F`, and the rest of the body.
  - `mismatch`: anything else, including the same change without DEST loaded. The installer refuses with `read_body_mismatch`.
- Startup logs `event=tome_read_probe_compat dest_loaded= read_body= window=11D-173`. The call-site byte checks, the 1.7.104 gate and mutual exclusion are unchanged.
- `tests/read_body_compat.cpp` covers every classification and shows the hash ignores only the window: bytes 0, `0x11C`, `0x173`, `0x18E` and the last byte are all detected.
- Build schema 12, SHA-256 `7D6F6D75B4CE04F99944A6E14160FEA1AE50C8DC0DAEEC3D29AD27D8909A2007`, preserved as `task07-preservation/dest-coexistence.dll`. All seven offline suites pass.

Expected with `UntamedTomes.EnforceTomeReads` and DEST 1.2.3 (static, **not observed**):

| Read | Our entry detour | DEST / ISL |
| --- | --- | --- |
| Read Or Take world READ while pending | Deny | No `OnSpellTomeRead`, so no study UI. The tome stays in the inventory for Papyrus. |
| Chest-side READ | Deny | No study UI. The tome stays in the chest. |
| Accepted inventory READ | Forward | DEST raises `OnSpellTomeRead` and ISL opens its study dialog. `Read` returns false (`rsi=0`), so the tome is kept, and ISL teaches later through `AddSpell`. Our exit row will show `original_result=false`, which is normal under DEST. |

### Phase 1 runtime cases (now testable, not yet run)

Profile: DEST 1.2.3, DESTified and Script Fixes enabled; Read Or Take on; mod enabled; and only the markers `UntamedTomes.EnforceTomeReads` (optionally plus `UntamedTomes.DebugTrap`).

1. **Startup.** Expect no message box. `skse64.log` should list `DontEatSpellTomes.dll` as loaded, and our log should show `observer_load schema=12`, `tome_read_probe_compat dest_loaded=true read_body=dest_window_patched`, then `tome_read_probe_ready mode=enforce_tome_reads`. If `read_body=mismatch` appears, enforcement stays off and the window assumption is wrong; preserve the log.
2. **Eligible inventory study.** Set the threshold at or below base Magicka. Take a tome (enabled mode, accepted), then read it from the inventory. Expect a forward, the ISL study dialog, and the spell after studying. The tome is kept.
3. **Ineligible Read Or Take world READ.** Expect `deny pending_acquisition`, **no** ISL dialog, then Papyrus `reject-removed`.
4. **Chest-side READ** (Left Shift, then Read). Expect `deny container_side_without_acquisition`, no ISL dialog, and the tome in the chest.
5. **Control without our marker.** Expect DEST/ISL to behave normally on every path. This confirms the bypass described above exists when our gate is off.

Record in game whether any ISL dialog appears, the spell list after studying, and the inventory and container contents.

## 3. Debug trap prototype (schema 11)

- **Opt-in:** an empty `UntamedTomes.DebugTrap` file in `Documents\My Games\Skyrim Special Edition\SKSE\`. It is read at plugin load (`debug_trap_config enabled=`), is independent of the read-probe markers, and is off without the file.
- **Trigger:** in `UT_PlayerMonitor.OnItemAdded`, after the unchanged `UT_HandleTomePickup` decision and removal and after the ledger acknowledgement. It fires when the outcome is `reject-removed` or `reject-skipped-empty-inventory`. It reuses the Papyrus eligibility result, with no native rule. There is one event per acquisition notification, so it fires once per acquisition; a stack Take of n copies is one event.
- **Effect:**
  - `Debug.Notification("[Untamed Tomes debug trap] <tome name> lashes out!")`;
  - `Game.ShakeCamera(None, 0.6, 0.6)`;
  - a `[UntamedTomes][Trap]` Papyrus trace;
  - the native row `event=debug_trap_triggered trigger=acquisition base= count= outcome=`.

  There is no damage, no item change and no extra Papyrus work in the read detour.
- **Read-trigger candidate:** observation only. Every native denial row now carries `trap_candidate=read_attempt`. Nothing is triggered from it.
- **Natives** `UT_IsDebugTrapEnabled` and `UT_ReportDebugTrap` are registered in every mode. If the DLL is missing, Papyrus logs an unbound-native error and the trap stays off, since an unbound `Bool` returns false.
- **Note:** existing rejection already removes the rejected copy silently (`RemoveItem` without a destination, so it is destroyed). The trap does not change that. "Do not destroy yet" and "preserve existing rejection" conflict until section 5 is decided.

### Trap test (not run)

Use mod enabled, base Magicka 100, threshold 150, a dungeon, `UntamedTomes.DebugTrap` plus `UntamedTomes.EnforceTomeReads`, and Read Or Take on.

1. World TAKE of an unlearned tome. Expect the notification and a camera shake about 1 s later, `debug_trap_triggered outcome=reject-removed`, the tome gone, and play continuing normally.
2. World READ through Read Or Take. Expect `tome_read_decision deny … trap_candidate=read_attempt`, then a single trap.
3. Chest TAKE. Expect a single trap with the `source` of the chest.
4. A safe-location pickup, or an eligible character with the threshold at or below base Magicka. Expect no trap.
5. Remove `UntamedTomes.DebugTrap` and restart. Expect `enabled=false` and no trap.

## 4. Interaction models

| Model | Timing available | DESTified fit | Gameplay fit | Cost |
| --- | --- | --- | --- | --- |
| **A. Acquisition trap** | Papyrus decision 0.6–1.4 s after pickup (measured). Exists today for world, chest and Read Or Take paths. | Independent of DEST. Rejected tomes never reach study, once our hook can coexist (section 2). | "The tome resists being taken." Matches the current acquisition rule. | Done (prototype) |
| **B. Read trap** | Synchronous at the `Read` entry. A denial is possible, but the trap must be queued to Papyrus, and eligibility at read time would need a new Papyrus decision per read, with denial first and a later re-read. | Needs our entry gate ahead of DEST (coexistence). That would trap before the study UI. | "Safe to carry, dangerous to study." | New native-to-Papyrus event plus a read-time decision protocol |
| **C. Mixed** | A plus B | As B | Richest | Sum of both |

**Recommendation:** use **A for v1.0**. It is implemented, it needs no new native signalling, and it is compatible with any study mod as long as acquisition is the protection boundary. Keep B as a follow-up behind the existing `trap_candidate=read_attempt` evidence. Revisit C only after DEST coexistence is proven on a runtime where DEST loads.

## 5. Item consequences (analysis only)

The Papyrus handler has the base form and count, and the **source container when there is one**. It logged `source=[ObjectReference < (000371E9)>]` for chest Takes. World pickups arrive with `ref=None source=None` in every logged case: the original world reference is not available to Papyrus.

| Option | Reference preservation | Stacking and ownership | Containers | Save/load | Feasibility |
| --- | --- | --- | --- | --- | --- |
| Leave at original location | Requires vetoing the pickup **before** it commits (native, at the activation or pickup boundary; Inv. 06 and 10). After pickup the reference is gone. | Preserved if vetoed | Container Take would need a pre-transfer veto | No new state | **Major engineering** (pre-commit hook per path) |
| Return to source container | Container acquisitions: `player.RemoveItem(base, 1, true, akSourceContainer)` returns a copy. Exact extra data (ownership, stolen, quest) may be lost, since removal is by base form. | Merges with the container stack | Works for chest and corpse when the source is known | The VM persists the event; low risk | **Small** (Papyrus) |
| Drop near the player | `DropObject` creates a new reference at the player. Original position, quest-alias fill and ownership are lost. | A new reference per drop | n/a | A new persistent reference | Small, but visibly not preservation |
| Destroy (current) | None | n/a | n/a | None | Exists. Risk: quest tomes picked up in the world have no reference for `IsQuestItem` and depend on the exclusions list. |
| Replace with a ruined book | None (new item) | Stacks as a separate base | Could be placed in the source container | None | Needs an ESP record (a ruined BOOK). Small. |

Given that world-reference preservation is a major requirement, only the **pre-commit veto** truly satisfies it for world tomes. That is a separate, major task. "Return to source container" satisfies it approximately, and cheaply, for chest and corpse acquisitions.

## 6. Remaining items

1. Confirm the DEST startup failure on 1.7.104 with one launch, or move DESTified testing to 1.6.1170.
2. Decide whether a 1.7.104-compatible DEST build is acceptable (third-party rebuild) before designing coexistence further.
3. Runtime-test the unified mode, the eligible path (Inv. 14 core matrix) and the debug trap.
