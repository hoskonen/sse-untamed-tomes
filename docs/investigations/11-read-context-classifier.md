# Investigation 11 — Spell-tome read context classifier

## Purpose and status

Task 02B proposed a future read guard that forwards reads from the player's own inventory and treats every other spell-tome read as an acquisition. That guard depends on recognising player-side reads without hard-coded caller addresses. This prototype records the evidence needed to judge that classification. It is observation only. It forwards every read, preserves the original return value, and changes no inventory, spells, Papyrus scripts or ESP records.

The schema 7 build compiled and was deployed to the MO2 development mod on 15 November 2026. Cases A and B were run on 1.7.104 the same day with the Task 03A diagnostics build (`883459F0…`). See the runtime matrix and [Investigation 12](12-world-read-denial.md). The native and Papyrus logs are preserved as `task04-preservation/classifier-ab-*.log` in the native checkout. Cases C–H are **untested**.

## Implementation

The classifier extends the existing `TESObjectBOOK::Read` entry detour (`RELOCATION_ID(17439, 17842)`, RVA `0x280290`, Skyrim 1.7.104 only). It adds no second hook. An empty marker file selects entry mode with classification. It must be at `%USERPROFILE%\Documents\My Games\Skyrim Special Edition\SKSE\UntamedTomes.ClassifyRead`, the same directory as `UntamedTomesSKSE.log` (CommonLib `logs::log_directory()`). On this machine that is `C:\Users\Petri Hoskonen\Documents\My Games\Skyrim Special Edition\SKSE\UntamedTomes.ClassifyRead`. Markers in the mod's `SKSE` or `SKSE\Plugins` folders are not read. Like the existing markers, it is mutually exclusive with `UntamedTomes.TraceReadEntry`, `UntamedTomes.TraceRead` and `UntamedTomes.DenyFirebolt`. With two markers present, nothing is installed. The Firebolt denial branch cannot be active in classifier mode. The existing runtime, body-hash, call-site and competing-module guards are unchanged.

| Native file | Change |
| --- | --- |
| `src/TomeReadContext.h` | New. Pure `ClassifyTomeRead(TomeReadObservation)` with no engine dependencies, and log string conversions. |
| `src/main.cpp` | `classifyReads` flag set before the hook is enabled. `LogReadContext` samples and logs the observations. `ObserveBookRead<0>` captures `_ReturnAddress()` at entry and logs one row before forwarding. Marker parsing, ready-message mode and `schema=7`. |
| `tests/tome_read_context.cpp` | New. Compile-time tests of the pure classifier. |

For each spell-teaching book read in classifier mode, the existing `tome_read_enter` row is followed by one `tome_read_observed` row with the same `read` sequence, then the existing `tome_read_exit` row. Ordinary and skill books produce no rows, as before.

### Observations

- `thread` comes from `GetCurrentThreadId`, and `main_thread` from `RE::Main::threadID`. `on_main_thread` compares the two. `verified_input_thread` is the earlier input-boundary check, included for cross-checking.
- Menu state is sampled **only when `on_main_thread=1`**. It uses `UI::IsMenuOpen` for InventoryMenu, ContainerMenu and BarterMenu. CommonLib implements this as an unsynchronised lookup in the menu map with no lock (`src/RE/U/UI.cpp`). Off the main thread, all menu fields are `-1`.
- `container_side` invokes `Menu_mc.isViewingContainer`, and `barter_side` invokes `Menu_mc.isViewingVendorItems`. These calls are made only on the main thread, for an open menu. Both SkyUI functions return `inventoryLists.categoryList.activeSegment == 0` ([ContainerMenu.as](https://github.com/schlangster/skyui/blob/master/src/ItemMenus/ContainerMenu.as), [BarterMenu.as](https://github.com/schlangster/skyui/blob/master/src/ItemMenus/BarterMenu.as)). They are declared private in ActionScript 2, which the language does not enforce at runtime. DEST calls the container function the same way from its read callback ([SpellTomeManager.cpp](https://github.com/Exit-9B/Dont-Eat-Spell-Tomes/blob/v1.2.2/src/SpellTomeManager.cpp)). `other` means segment 0: container contents or vendor stock. A failed invoke or a non-boolean result gives `unavailable`. That the segment means the same thing under vanilla or other menu replacers is unverified.
- `caller_module`, `caller_rva` and `initiator` come from `GetModuleHandleExW(FROM_ADDRESS)` on the return address. They are diagnostic only and never affect the classification. A chained detour or a thunk in another module would appear as the caller.
- Correlate rows with Papyrus `[UntamedTomes][Pickup` rows by book FormID, wall-clock `capture_unix_us` and trial order. Correlate with native inventory rows by `session` and capture time.

### Classification

The categories are hypotheses under evaluation. Every inferred result has confidence `tentative`, and every `unknown` has confidence `none`. Rules apply in order:

| Observation | Classification / reason |
| --- | --- |
| Reader missing or not the player | `unknown` / `reader_unavailable`, `non_player_reader` |
| Main-thread ID unavailable | `unknown` / `main_thread_unavailable` |
| Off the main thread | `unknown` / `off_main_thread`. A worker read is **not** assumed to be a world read. Any menu sample present off the main thread gives `inconsistent_observation`. |
| Any menu state unavailable on the main thread | `unknown` / `menu_state_unavailable` |
| Side sampled for a closed menu | `unknown` / `inconsistent_observation` |
| More than one of the three item menus open | `unknown` / `multiple_item_menus` |
| InventoryMenu | `player_inventory` / `inventory_menu` |
| ContainerMenu, player side | `player_inventory` / `container_player_side` |
| ContainerMenu, other side | `external_container` / `container_external_side` |
| ContainerMenu, side unavailable | `unknown` / `container_side_unavailable` |
| BarterMenu | `barter` / `barter_menu`. The side is logged and does not change the category. |
| No item menu open | `world` / `no_item_menu` |

An open menu shows what was on screen, not which code issued the read. Another plugin reading while InventoryMenu is open would be classified `player_inventory`. The caller fields exist to expose such cases.

## Offline verification

`tests/tome_read_context.cpp` holds 20 `static_assert` cases covering the required eight situations: inventory, player-side container, external container, barter, worker thread, main thread without a menu, missing data, and conflicting observations. It also covers reader checks. Compiled with MSVC 14.51 (`cl /std:c++20 /W4 /WX /EHsc`), it passed, and the existing `tome_read_decision` and `observation_queue` tests still passed. A negative control asserting that a worker read is classified `world` failed to compile, which confirms the assertions are evaluated. `xmake -y` (releasedbg, SE+AE, VR off) built schema 7 without warnings.

## Deployment and preservation

The deployed DLL was the dormant forwarding entry-probe build, SHA-256 `D116BC7D9BE3FC51551C6C7D8ADAF105CEA115E526527FD73601A7173D6D0063`. It and its PDB, together with the previous native and Papyrus logs, are preserved in the native checkout under `classifier-preservation/` as `pre-classifier-*`. xmake installed the schema 7 DLL, SHA-256 `23613C007BA4294E6E4CB05E8CEF088C5A67D66908229473248E5AB4B4629951`, which is copied there as `classifier.dll` and `classifier.pdb`. To roll back, restore `pre-classifier-forwarding.dll` and `.pdb`.

### Activation fix (Task 03A)

The first runtime launch of schema 7 at 11:19 logged load, runtime verification, input registration and `observer_ready`, but no read-probe line. The marker was at `D:\Modding\Ancestries\mods\Untamed Tomes\SKSE\UntamedTomes.ClassifyRead`, which appears to the game as `Data\SKSE`. It had also been tried in `SKSE\Plugins`. `InstallReadProbe` runs at `kPostPostLoad` and only checks the log directory above. When it found no marker there, it returned without logging. The hook was never attempted. Installation did not fail, and no later lifecycle event was involved.

The same build now always logs one `event=tome_read_probe_config` row. The row gives the directory checked, each of the four markers as `true`/`false`, whether a filesystem check failed (`marker_check_error`), and the `selected` mode (`none`, `conflict`, `forward_only`, `call_sites`, `deny_firebolt` or `classify`). A marker found in `Data/SKSE` or `Data/SKSE/Plugins` produces `event=tome_read_marker_ignored path=... expected_directory=...` and still does not activate anything. Every refusal now carries `mode=` and `attempted=0`. `event=tome_read_probe_install attempted=1` marks the point after all guards pass. A failure in SafetyHook creation or enabling reports SafetyHook's error type, such as `error=failed_to_unprotect`. A missing log directory is reported instead of being ignored. Marker locations, guards, mutual exclusion and classification are unchanged.

This build's SHA-256 is `883459F0E03970F681A8EF7D997D5C640EA793AE0BCD25EB887359D11A863C00`, copied as `classifier-preservation/classifier-diagnostics.dll` and `.pdb`. The 11:19 schema 7 build (`23613C00…`) is preserved as `classifier.dll`. The 11:28 relaunch, with the marker in the corrected location, logged `selected=classify`, `tome_read_probe_install attempted=1` and `tome_read_probe_ready mode=classify`. Its `marker_check_error=true` was a false positive. MSVC reports a missing file through the error code, and schema 8 ignores that case.

## Runtime checklist (Skyrim 1.7.104)

1. Create only `UntamedTomes.ClassifyRead` in `Documents\My Games\Skyrim Special Edition\SKSE`, next to `UntamedTomesSKSE.log`. Keep Papyrus debug logging and `bEnableTrace=1`. Launch through MO2 and require `observer_load schema=7`, `runtime_verified`, `tome_read_probe_config ... classify_read=true ... selected=classify`, `tome_read_probe_install attempted=1 mode=classify strategy=entry` and `tome_read_probe_ready mode=classify strategy=entry`. Use a disposable save, and note whether Read Or Take is enabled in the profile.
2. Run each case once, reloading between cases as needed. Record the user-visible outcome, spell list and book count. Copy `UntamedTomesSKSE.log` and `Papyrus.0.log` from the same launch into `classifier-preservation/`.
3. Remove the marker afterwards. A running game keeps the hook until it exits.

| Case | Action | Hypothesis to check | Status |
| --- | --- | --- | --- |
| A | World READ with Read Or Take | Earlier runs observed worker threads, which would give `unknown/off_main_thread`, `initiator=other_module` with the Read Or Take DLL as caller. A main-thread occurrence would give `world`. | **Observed:** Firebolt on worker 19640 (main 11908), `po3_ReadOrTakeBooks.dll` caller RVA `256C`, `unknown/off_main_thread`. Original returned true, and Papyrus `skipped-empty-inventory`. |
| B | Read from the player inventory | `on_main_thread=1`, `player_inventory/inventory_menu`, caller in `SkyrimSE.exe` (earlier call site `945D97`) | **Observed:** main thread 11908, InventoryMenu open, `SkyrimSE.exe` RVA `945D9C`, `player_inventory/inventory_menu`. Original returned true, `known_after=1`. |
| C | Read from the player side of a ContainerMenu | `player_inventory/container_player_side` | Untested |
| D | Read from the container side | `external_container/container_external_side`. Record whether the tome ever enters the inventory. | Untested |
| E | Read in BarterMenu, if the menu offers it | Actual thread, side and outcome | Untested |
| F | Read through another SKSE plugin, if one is installed | Caller module and classification | Untested |
| G | Ordinary and skill books | Opening and skill increase as before; no classifier rows | Untested |
| H | World READ in a dungeon, a town and the wilderness | The classification does not vary with location | Untested |

For every row, confirm `tome_read_exit original_invoked=1`. The original result and the learning and consumption outcome should match the corresponding earlier forwarding results. Report any case that cannot be exercised as untested.

## Known limitations

- Supported on 1.7.104 only, and the entry-hook guards still refuse DEST, Lodestone, SpellLearning and Heart of Magic. Classifier rows cannot be collected in load orders that use them.
- Off-main-thread reads are always `unknown`. The prototype cannot positively identify a world read on a worker thread. The guard proposed in Task 02B only needs positive identification of player-side reads, so this matters only if a world read must be recognised as such.
- Menu state and side are sampled at `Read` entry. A read issued by code while a menu is open is attributed to that menu.
- The side lookup depends on SkyUI's `Menu_mc` and `activeSegment` semantics. A menu replacer can change or remove them, which yields `unavailable`.
- The return address is meaningful only without other entry detours. Module lookups take the loader lock briefly, which is acceptable for a diagnostic but not appropriate for a production decision path.
- Logging is synchronous and flushed, so it adds latency on the read path.

## Recommendation

Do not use the classifier for a read guard yet. Approve it only if cases B and C reliably produce `player_inventory` on the main thread, D produces `external_container`, and A never produces `player_inventory`. If those hold, the conservative guard rule is "forward only on `player_inventory`, otherwise treat the read as an acquisition", which is consistent with the classifier's `unknown` results. Any `player_inventory` result for a world or container-side read, or an `unknown` result for a genuine inventory read, would reject that rule.
