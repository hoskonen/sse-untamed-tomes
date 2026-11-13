# Current state audit

Task 01 audited all six tracked files at `1464bca`, when the experimental branch and local `main` pointed to the same commit. This audit also reflects the classifier restored in Task 02 and build verification from Task 03. Git ignores locally produced PEX files and ESPs. The repository still lacks the ESP needed for runtime verification. Other installations, backups and mod-manager profiles remain unverified.

## Source behavior and historical differences

| Feature | Current source | Historical information |
| --- | --- | --- |
| Inventory and tome detection | The alias handles `OnItemAdded` and filters on `MagicTomeKeyword`. A missing keyword causes an early return. | The player alias and vanilla `VendorItemSpellTome` binding were used and tested. |
| Location and barter | Open `BarterMenu` bypasses the hazard. Current-location classification checks dungeon first, then city or town, inn and store. City and town both map to `town`. Town, inn and store are safe. Dungeon and fallback contexts proceed to later checks. | The brief reports location classification and barter handling as tested. Purchase provenance, especially for traveling or nonstandard merchants, remains unresolved. |
| Exclusions | The safe keyword and FormList are checked against the base form when their properties are filled. PO3's `IsQuestItem` runs only when `akItemRef` exists. | The brief reports both exclusions and reference-based quest protection as implemented and tested. |
| MCM | Enable and debug toggles and a base Magicka threshold slider share globals with the monitor. The slider spans 0–500 in steps of 10 and offers 100 as the dialog default. | The brief reports working settings. Actual ESP initial values are unknown. |
| Non-mage detection | Task 02 restored the six-skill progression baseline and classifier in observation mode. Base Magicka remains the sole eligibility measure. Equality meets the threshold. | The restored rule requires at least three levels gained and a magic skill delta of at most ten. |
| Rejection | Below threshold, the monitor checks that the base form is present and requests silent removal of one copy. | Rejection and inventory removal were reported tested. |
| Backlash | No delay, severity calculation or actor-value damage exists. | Severity-based damage after a short delay was proposed in the original development. Runtime validation is unverified. |

Task 03 compiled both scripts from the portable template. Script attachments, property values and in-game outcomes remain unverified.

## ESP records and bindings to verify

Record names below come from the historical brief. Property names come from the scripts. Verify them against the recovered ESP or document the settings chosen for a reconstruction.

| Historical record or expected reference | Script connection |
| --- | --- |
| `UT_MainQuest` and its player alias | Attach `UT_PlayerMonitor` to the alias. Verify the alias resolves to the player and that the quest starts and delivers inventory events. |
| `UT_MCMQuest` | Attach `UT_MCM` to the quest and verify SkyUI registers it. |
| `UT_ModEnabled`, `UT_DebugEnabled`, `UT_MagickaThreshold` | Bind each same-named property on both scripts to the same global record. Verify types, initial values and write behavior. |
| Vanilla `VendorItemSpellTome` | Bind monitor property `MagicTomeKeyword`. |
| `UT_TomeSafe` keyword and `UT_TomeExclusions` FormList | Bind the same-named monitor properties. Verify actual keyword assignments and list membership. |
| Location keywords | Verify the references for `LocTypeCity`, `LocTypeTown`, `LocTypeInn`, `LocTypeStore` and `LocTypeDungeon`. |
| `VendorChestKeyword` | Declared on the monitor. Its only use is commented out, so the current behavior needs no binding for it. |

`O_Enable`, `O_Debug` and `O_Threshold` are MCM option handles assigned by the script. Quest flags, alias fill settings, form IDs, masters, global defaults and FormList entries require plugin evidence. If a reconstruction assigns new IDs, treat save compatibility with the historical plugin as unverified.

## Risks and unknowns

- **Purchase attribution and timing.** The gate checks whether the menu is open when the event handler runs. Menu closure or queued events could change the result. Town, inn and store exemptions also cover looted or stolen tomes. `akSourceContainer` is unused.
- **Repeated checks.** The handler calls the safety gate twice in the rejection path and can call it again for debug output. A changing menu or location could cause diagnostics and the decision to disagree.
- **Inventory identity.** The guard only checks quest status for an available instance reference. Removal targets the base form, so a pre-existing copy or quest copy of the same form may be affected. Stack transfers ignore `aiCount`. Verify reference-less transfers, mixed copies, rapid pickups and Take All before relying on removal.
- **Missing bindings.** A missing enable global behaves as enabled, a missing debug global disables debug, and a missing threshold reads as zero. Missing location or exclusion properties skip those checks. MCM controls can update visually when their backing globals are absent.
- **Build portability and packaging.** The checked-in PPJ template uses locally configured paths and compiles both scripts. Release packaging and runtime-compatible dependency versions still need verification with the ESP.
