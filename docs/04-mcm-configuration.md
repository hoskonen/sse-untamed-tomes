# MCM configuration audit

## Shared settings

Bind these properties on both `UT_MCM` on `UT_MCMQuest` and `UT_PlayerMonitor` on the `UT_MainQuest` player alias. Each pair must point to the same mutable global record.

| Control | Property and record | Reconstructed ESP value | Missing binding fallback |
| --- | --- | --- | --- |
| Enable Untamed Tomes | `UT_ModEnabled` | 1 (enabled) | Enabled |
| Required Magicka | `UT_MagickaThreshold` | 100 | 0 |
| Debug logging | `UT_DebugEnabled` | 1 (enabled) | Disabled |

The MCM reads the saved globals as it builds the page and writes them when the player changes a control. The inventory monitor reads those same values during normal processing. The slider still opens at the current value, with a range of 0–500, step 10, and dialog default of 100. The dialog default is independent of the saved setting. A missing binding disables its MCM control and logs the property name during page construction. The gameplay fallbacks stay the same.

## SkyUI and save/load

- The old `O_Enable`, `O_Threshold`, and `O_Debug` properties exposed option IDs as CK fields. The reconstructed snapshot has no assignments for them. SkyUI returns the IDs each time `OnPageReset` builds the page, so ordinary script variables hold them. Old option IDs have no settings data to migrate.
- `OnConfigInit` assigns `ModName` to “Untamed Tomes”. The reconstructed ESP supplies the same name, so cleanup is optional. Keep `Pages` empty for the unnamed page. `CurrentPage` is computed by SkyUI, and layout and option flags are inherited constants.
- SkyUI's inherited initialization and reload callbacks handle registration. `OnConfigInit` runs on first initialization and does not reset globals. Existing saves should keep their global values. Verify registration and settings on both fresh and upgraded saves.
- The MCM consolidated the duplicated threshold read and removed the generic initialization trace. Missing-binding diagnostics use the Papyrus log. Gameplay debug messages remain in the inventory monitor.

## Why keep the globals

The three globals use Skyrim's save persistence, require six CK assignments across the two scripts, and already work with SkyUI's option callbacks. Direct reads give the monitor the current values without a separate refresh step. A quest-based settings script could reduce wiring as shared settings multiply, but would introduce a settings instance that consumers must resolve and initialize. Moving existing values would require a one-time migration from the old globals, with tests for new saves, upgraded saves and missing references. The current three settings do not justify that change.

For future shared settings, assign a CK default, bind the same record wherever it is read or written, and document the missing-binding fallback. Keep dialog defaults explicit where SkyUI needs them. Keep menu-only state in the MCM script. Revisit centralization if additional consumers or settings make the direct bindings difficult to maintain.

## Verification

Task 06 compiled both scripts with the working Pyro configuration and generated both PEX files with zero warnings or errors. Skyrim runtime checks remain pending.

- On a fresh disposable save, verify SkyUI registration, the single page, and the initial values of all three controls.
- On a save made with the previous scripts, verify the menu reopens with the saved settings. Change both toggles and the slider, close and reopen the menu, then save and reload. Confirm the values persist and the slider range, step and default work.
- Verify the monitor observes the same settings by exercising the enable toggle, debug toggle and Magicka threshold on eligible tome pickups. Include a safe pickup to check the existing exemptions.
- In a disposable test setup with an omitted global binding, verify the corresponding control is disabled, the trace names the missing property, and the monitor keeps its documented fallback.
