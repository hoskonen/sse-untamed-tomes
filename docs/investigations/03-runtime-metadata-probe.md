# Task 03 — Runtime Spell Tome Metadata Probe

The player alias runs the probe once per tagged-tome addition event when Untamed Tomes and MCM **Debug logging** are enabled. This includes tagged tomes accepted in safe contexts or by exclusions. The existing pickup decision and any removal run first. The probe reads the base form, so the diagnostic can still run after a rejection removes one copy. The existing keyword gate defines the sample population. An untagged spell-teaching book will produce no probe lines.

## Read the trace

Find the `[UntamedTomes][Pickup ...] metadata` lines in `Papyrus.0.log`. Match them to the existing pickup trace by entry time and item. Log IDs are decimal signed Papyrus integers. Convert to their unsigned 32-bit hexadecimal representation before lookup in xEdit. Use the same load order and light-plugin slots. The probe emits one row per effect slot and identifies missing entries.

- The book's teaching link supplies the spell. The probe logs the spell type, half-cost perk ID if present, effect count, costliest index, and each effect's FormID, associated skill and minimum skill.
- A valid costliest effect can resolve to one of five schools and an exact minimum skill of 0, 25, 50, 75 or 100. If effects disagree on school or minimum skill, the trace reports an ambiguous candidate and skips the prediction. This conservative rule also flags school-less secondary effects that disagree with a valid primary. Compare the half-cost perk against the effect-derived pair in xEdit. The probe logs the perk without interpreting its tier.
- SKSE can return index zero both for a selected first effect and for no costliest effect. The probe labels this limitation. It can still classify a complete list whose effects unanimously identify the same supported school and minimum skill, because the classification is independent of the selection in that case. Missing effects, invalid indices, unsupported spell types, unsupported schools and noncanonical values yield no prediction.
- `baseCostRaw` is the loaded spell cost field. `effectiveCostRaw` is the SKSE integer result for the current player when the spell is an ordinary spell and its effect list is complete. Negative values are marked invalid or unset. Zero is reported as returned and must be checked against the record and UI. Concentration and one-shot costs should be compared separately.
- Competence uses base school skill clamped to 0–100 plus `clamp((baseMagicka − 100) / 5, −10, 30)`. The target is `15 + 20 × tierIndex` with Novice at index zero. Margin is score minus target. A nonnegative margin predicts safe. An unsafe result logs `clamp(−margin / 40, 0, 1)` as predicted severity. The cost offset is zero. The fixed MCM Magicka threshold still controls the actual decision.

The metadata begin and end samples bracket investigation work in engine real-time seconds. Existing pickup samples still bracket removal. The probe adds work after the current event's decision and removal, which can affect later events during bursts. The samples describe script execution after entry and cannot measure input-to-dispatch latency. Use single-pickup trials for record comparison and Take All for a separate overhead check. [Investigation 01](01-pickup-pipeline.md) · [Investigation 02](02-tome-metadata-and-competence.md)

## Next Skyrim runtime test

1. Deploy the two freshly compiled PEX files into the existing MO2 dev mod using `tools/Deploy-ToMO2.ps1`. Verify the winning PEX files and runtime-matched SKSE and Papyrus Extender. Use a disposable save. Set `bEnableLogging=1` and `bEnableTrace=1` in the test profile's Skyrim.ini under `[Papyrus]`, and turn on Untamed Tomes and **Debug logging** in the MCM.
2. Pick up one tome at a time. Close menus when necessary and open `Logs\Script\Papyrus.0.log` in the Skyrim user-data directory. Compare the actual pickup decision and metadata lines. Repeat with debug off to confirm metadata silence, and check town, barter, quest and rejected dungeon cases against the existing behavior.
3. Open xEdit with the same load order. Compare the rightmost winning columns. Follow the logged BOOK's teaching flags and spell link to SPEL. Compare its effect order and links, spell type, `SPIT` cost/manual-cost flag, and half-cost perk. Follow each MGEF link and compare Magic Skill and Minimum Skill Level. The runtime costliest index is engine-selected. Check which xEdit effect corresponds to the logged index and verify the resolved pair against it. Compare effective cost to the in-game UI under the same perks, gear and casting context.

| Fixture | xEdit and runtime evidence to capture |
| --- | --- |
| Vanilla Novice | Flames, or another verified 0 minimum-skill spell-teaching book. Compare the teaching link, selected effect and Novice result. |
| Vanilla Apprentice | Stoneflesh, or a verified 25 fixture. Check Alteration and Apprentice. |
| Vanilla Adept | Frenzy, or a verified 50 fixture. Check Illusion and Adept. |
| Vanilla Expert | Grand Healing, or a verified 75 fixture. Check Restoration and Expert. |
| Vanilla Master | Flame Thrall, or a verified 100 fixture. Check Conjuration and Master. Inspect unusual values rather than forcing the expected tier. |
| Mixed effects | Use a spell whose effects differ by school or minimum skill. Compare each logged slot and the costliest candidate. Expect an ambiguous result with no prediction. Include a same-school/same-tier multi-effect control. |
| Mod-added and overridden tomes | Include a tagged ESP or ESL tome and an overridden vanilla spell and effect. Compare against the winning columns. Use an untagged teaching book as a coverage control. |
| Missing or unusual metadata | Use existing examples or separate test fixtures for a tagged book with no teaching spell, empty/missing effects, no school, custom minimum skill such as 90, a power/ability, and zero/manual cost. Check explicit status and absence of an invented school or tier. |

The named spells are proposed fixtures. Confirm their metadata in the active load order, and use a matching tome that actually reaches the player's inventory.

## Offline verification

Run `./tests/Test-TomeCompetence.ps1` from the project root. It checks the reference tier mapping, exact boundaries, skill and Magicka clamps, and severity. The test runs the reference arithmetic in PowerShell. Pyro compiles the Papyrus implementation. In-game acquisition, xEdit comparison and engine cost behavior remain to be verified.
