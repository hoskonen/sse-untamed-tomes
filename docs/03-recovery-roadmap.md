# Recovery roadmap

Continue recovery on `dev/untamed-tomes-v2`. Keep the original or recovered files intact for comparison. Use the [overview](01-project-overview.md) for dependencies and the [audit](02-current-state-audit.md) for source behavior and bindings to preserve.

## 1. Restore the historical progression classifier

- **Historical implementation restored.** The player alias stores the baseline level, sum of six base magic skills and initialized flag at the first tome event that passes the enabled, context and exclusion checks and resolves a player. The sum includes Destruction, Conjuration, Restoration, Illusion, Alteration and Enchanting. The classifier returns true when level gain is at least 3 and the magic skill sum increased by at most 10. Debug mode traces both snapshots, both deltas and the result. The base Magicka threshold still controls rejection.
- **Offline validation complete.** Task 02 passed nine tests against the local offline mirror, covering decision boundaries, a negative skill delta, a missing player and first-observation initialization. The local `tests/` directory is ignored.
- **Papyrus compilation complete.** Task 03 verified both PEX outputs from a clean Pyro build with the installed dependency sources. See the [README](../README.md#compile) for the build command and verification details.
- **Skyrim runtime verification pending.** A verified test ESP is needed to check baseline initialization on fresh and pre-change saves, persistence across save/load and behavior after a quest or alias reset. Verify trace output without new notifications, then exercise the disabled, barter, location and exclusion gates and the below-threshold and at-threshold pickup paths.

The formula is provisional gameplay design. A baseline captured after substantial character progression misses earlier growth and can misrepresent the character's development. A Legendary skill reset can reduce the skill sum and still satisfy the historical rule.

## 2. Restore and test runtime wiring

Look for the ESP and newer sources in backups, archived mod packages and mod-manager profiles. Record the provenance of any recovered files. Inspect the ESP in Creation Kit and verify the bindings in the audit. If recovery fails, build an isolated test ESP and record its masters, quest startup, alias fill settings, global defaults and property bindings. Smoke-test MCM registration, shared global updates and player alias events on a disposable save. Keep the rebuild distinguishable from the historical plugin.

## 3. Integrate the classifier

Use the diagnostic results or a recovered implementation to define how the classifier should interact with the Magicka threshold. Document the desired treatment of insufficient data, late installs and skill resets. Test mage, non-mage and mixed progression at, above and below the threshold. Repeat the safety-gate cases before enabling classification as a gameplay input.

## 4. Prototype generic backlash

Define a small severity rule and explicit bounds for health, Magicka and stamina damage. Keep the calculation separate from the short delay and actor-value changes. Test zero and maximum damage, rapid consecutive pickups, and transitions such as disable, death and save/reload while damage is pending. Verify that exempt tomes never schedule damage. Visual effects are a separate investigation.

## 5. Audit event handling and make builds reproducible

Check safety gate timing, reference-less quest items, stacks and mixed inventory copies using captured event parameters. Fix each confirmed issue separately. The script-only workflow is verified. For an integrated build, pin the tested game, compiler and dependency versions, document the Creation Kit record setup and verify the ESP and PEX files in a fresh-profile smoke test. Record the test results with the source commit.

## 6. Investigate, prototype and compare

| Investigation | Evidence to capture |
| --- | --- |
| Tome spell metadata | Try Papyrus, SKSE and Papyrus Extender APIs on representative vanilla and mod-added spell tomes. Record whether they expose the taught spell, school, cost and difficulty and what happens when data is absent. |
| Backlash presentation | Try existing spells, magic effects, explosions and projectiles in small test cases. Check how each looks and record targeting, collateral effects and cleanup. |
| Purchase provenance | Compare event parameters and menu timing for normal shops, traveling merchants, theft, loot and transfers. Identify which cases existing APIs can distinguish reliably. |
| Native hook feasibility | Evaluate a native hook only for a specific remaining gap after existing APIs have been tested. Record the signal it would need to expose and the supported-runtime maintenance cost. |

Integrate successful prototypes independently. When newer source or plugin files surface, compare behavior and bindings against the experimental branch and use the same test cases to select what to carry forward.
