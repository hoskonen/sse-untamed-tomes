# Recovery roadmap

Continue recovery on `dev/untamed-tomes-v2`. Keep the original or recovered files intact for comparison. Use the [overview](01-project-overview.md) for dependencies and the [audit](02-current-state-audit.md) for source behavior and bindings to preserve.

## v1.0 contract and interception status

The v1.0 gameplay contract was decided in Task 05B and is recorded in [Investigation 13](investigations/13-spell-tome-lifecycle-and-eligibility.md):

- Acquisition and spell learning are both protected.
- Papyrus eligibility rules stay authoritative, with merchant and safe-location exemptions.
- Accepted inventory tomes read normally. Retrieving a stored tome is a new acquisition.
- Read Or Take is optional, and containers and corpses are supported where feasible.
- Already-known spells do not bypass restrictions.
- World-reference preservation, carrier hazards, defensive enchantments and Dispel Magic come after v1.0.

Steps toward that contract:

1. **Done (Inv. 12):** an opt-in schema 8 denial of the Read Or Take world READ, runtime-tested on 1.7.104.
2. **Runtime-tested in part (Inv. 13 §13, 15 November 2026):** an observation-only pending ledger (schema 9), with a Papyrus acknowledgement at every exit of the tome handler. Six additions produced six matched acknowledgements and no anomalies. `would_gate` was observed for a Read Or Take world READ (`pending_acquisition`) and an accepted inventory read. Container-side READ, two-copy counting, save/load while pending and expiry are still untested. Schema 9 stays observation-only until the container-side case has run.
3. **Done (Inv. 14, schema 10):** opt-in pending-acquisition denial and container-side denial as separate modes. Container mode was runtime-verified (8 denials, `original_invoked=0`). Pending mode is supported by the Papyrus log and a user report; its native log was not preserved.
4. **Built, not runtime-tested (Inv. 14, schema 11):** unified `UntamedTomes.EnforceTomeReads` (pending first, then external container), plus clearer `ledger_ready` and `papyrus_decision` diagnostics.
5. **Built, not runtime-tested (Inv. 15):** opt-in debug acquisition trap (`UntamedTomes.DebugTrap`). Recommended v1.0 interaction: acquisition trap (model A).
6. **Built, not runtime-tested (Inv. 15, schema 12):** coexistence with Don't Eat Spell Tomes 1.2.3, which reads format 5 and overrides DESTified's bundled 1.2.2. The install is accepted only when DEST is loaded and every `Read` byte outside its `[0x11D, 0x173)` window is unchanged.
7. **Built, not runtime-tested (Inv. 16, schema 13):** a debug-only fire defense (`UntamedTomes.FireTrap`, vanilla `TrapFirebolt01` cast from a temporary XMarker), deferred while a menu is open, with load, expiry and location cancellation. DEST coexistence was verified at runtime on 16 November 2026.
8. **Built, not runtime-tested (Inv. 17, schema 14):** a fix for the Task 08 array failure on existing saves (scalar slots), a facing-corrected TrapFirebolt01 (`UntamedTomes.FireTrap`), and a direct flame-pillar burst at the player (`UntamedTomes.FireBurstTrap`) with hit and health verification. The burst is the recommended baseline if the run confirms it.
9. **Runtime-tested in part (Inv. 18, schema 15):** an opt-in pre-pickup veto of one test tome (`UntamedTomes.VetoTestTomePickup`), wrapping `TESObjectBOOK::Activate` ahead of Read Or Take. On 16 November 2026 the first activation was vetoed with the reference intact, and the second was forwarded and picked up. Experiment A runtime: 1 of 3 interior firebolts hit (Inv. 17).
10. **Built, not runtime-tested (Inv. 19, schema 16):** the world tome eligibility handshake (`UntamedTomes.WorldTomeHandshake`):
    - a per-reference state machine;
    - a main-thread ModEvent request;
    - shared Papyrus eligibility;
    - one authorised activation;
    - a refusal shader pulse on the tome.

    World-reference preservation for world pickups is therefore implemented experimentally. Containers still need a different boundary; return-to-source-container is a small interim option for chest and corpse acquisitions.
11. **Checkpoint, runtime-verified in part (Inv. 20, schema 17, 16 November 2026).**
    - **Verified:**
      - rejection and re-evaluation;
      - eligible pickup of the same reference;
      - grant binding and consumption with no trap;
      - two independent references;
      - DEST-compatible inventory reads;
      - reset on save and load.
    - **Schema 17 changes:**
      - Grants are bound to the inventory transfer of the authorised activation.
      - There is no forward without an answer.
      - Generations are unique per process.
    - **Open:** study completion, save and load mid-handshake, exemptions, failure recovery in game, Read Or Take disabled, the full load order (Inv. 20 §13). Not production-ready.
12. **Next, high priority:** a single-activation world tome. Investigate safe automatic continuation of the activation (Inv. 20 §14), then an immediate native visual reaction, then tome-origin defenses. See the [session handoff](05-session-handoff.md).
5. **Open design questions** (Inv. 13 §12): container reads in safe locations; corpse, stolen and owned provenance; console and script additions; untagged teaching books; merchant-side reads; player feedback; fail-open versus fail-closed expiry.

Known v1.0 limitations:

- Skyrim 1.7.104 only.
- Spells granted without `Read` are not intercepted.
- DEST, Lodestone and Heart of Magic prevent the hook.
- The Read Or Take world READ becomes a Take.
- No denial feedback.

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
