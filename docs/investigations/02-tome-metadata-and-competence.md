# Investigation 02 — Tome Metadata and Magical Competence

## Recommendation

Start with a read-only Papyrus metadata probe using the existing SKSE installation. A book can supply its taught spell directly. The spell's costliest effect can supply a school and minimum skill, which Untamed Tomes can map to a difficulty tier after checking the mapping against the winning records in xEdit. Use a deterministic competence check for the first gameplay experiment. A character who meets it should handle the tome safely every time.

The current fixed base-Magicka threshold remains the live rule. The historical progression classifier is still present and its output does not affect rejection. The design below requires no new saved character state.

## Verified API findings and feasibility

Here, “stock Papyrus” means the Creation Kit API. “Papyrus with SKSE” means scripts calling functions supplied by the project's existing SKSE dependency. Findings are based on source and installed declarations. Exact results on AE 1.6.1170 still need runtime comparison.

| Question | Stock Papyrus | Papyrus with SKSE and existing Extender | CommonLibSSE-NG C++ |
| --- | --- | --- | --- |
| Does the book teach a spell? | Can cast to a `Book` and check the tome keyword as a content convention. | `(baseForm as Book).GetSpell()` returns a usable `Spell` or `None`. `Book.GetSkill()` concerns skill books. | Cast the form to `RE::TESObjectBOOK`. `TeachesSpell()` reads the teaching flag and `GetSpell()` returns the linked spell. This distinguishes a malformed spell-teaching book with a missing link from a regular book. `IsBookTome()` tests a separate book type. [SKSE Book implementation](https://github.com/ianpatt/skse64/blob/v2.2.6/skse64/PapyrusBook.cpp) · [NG Book implementation](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/src/RE/T/TESObjectBOOK.cpp) |
| Which spell? | `Form.GetFormID()` is available once a spell form is known. | Keep the returned `Spell` for queries. Its inherited `GetFormID()` identifies the winning loaded form for diagnostics. | `SpellItem::GetFormID()` via `TESForm`. Both IDs are runtime IDs. For a durable fixture or override, key by plugin filename and local FormID or use a form property. [Form.psc](https://github.com/ianpatt/skse64/blob/v2.2.6/scripts/vanilla/Form.psc) · [NG TESForm](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/include/RE/T/TESForm.h) |
| Which school? | `MagicEffect.GetAssociatedSkill()` is available when the effect is already known. Stock Spell lacks the needed effect traversal. | `Spell.GetCostliestEffectIndex()` plus `GetNthEffectMagicEffect()` selects an effect, and `GetAssociatedSkill()` reads its school. Check count, bounds and the returned effect. SKSE's helper can return zero when the engine finds no costliest effect, so zero alone proves nothing about selection. | `SpellItem::GetAssociatedSkill()` exposes an engine spell-level query. For parity with the script policy, use `GetCostliestEffectItem()` then `EffectSetting::GetMagickSkill()`. Compare both native queries in mixed-effect cases before treating them as equivalent. [SKSE Spell implementation](https://github.com/ianpatt/skse64/blob/v2.2.6/skse64/PapyrusSpell.cpp) · [NG MagicItem](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/src/RE/M/MagicItem.cpp) · [NG SpellItem](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/include/RE/S/SpellItem.h) · [NG EffectSetting](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/include/RE/E/EffectSetting.h) |
| Which tier? | No direct book-to-spell tier lookup. | `MagicEffect.GetSkillLevel()` exposes the effect's minimum skill. `Spell.GetPerk()` exposes the associated spell perk. Cross-check recognized vanilla half-cost perks where present. | Read `EffectSetting::GetMinimumSkillLevel()` and the spell's `SPIT` perk. An effect's minimum skill and a spell's half-cost perk are distinct fields. A single school/tier for a composite spell is a policy decision. [SKSE MagicEffect implementation](https://github.com/ianpatt/skse64/blob/v2.2.6/skse64/PapyrusMagicEffect.cpp) · [xEdit Skyrim record definitions](https://github.com/TES5Edit/TES5Edit/blob/dev-4.1.6/Core/wbDefinitionsTES5.pas) |
| What does it cost? | No stock spell-cost getter in the inspected declarations. | `Spell.GetMagickaCost()` reads the loaded spell's integer base-cost field. `Spell.GetEffectiveMagickaCost(actor)` invokes a caster-dependent engine routine and returns an integer. `MagicEffect.GetBaseCost()` returns the base-cost coefficient on a magic effect. | `SpellItem::data.costOverride` and its override flag expose the loaded cost field and manual-cost status. `MagicItem::CalculateMagickaCost(actor)` returns a float from an engine routine. Test rounding and parity with SKSE. Evaluate actorless calculation only after verifying null-actor behavior and semantics on the target runtime. [SKSE Spell bindings](https://github.com/ianpatt/skse64/blob/v2.2.6/skse64/PapyrusSpell.cpp) · [SKSE SpellItem layout](https://github.com/ianpatt/skse64/blob/v2.2.6/skse64/GameObjects.h) · [NG cost implementation](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/src/RE/M/MagicItem.cpp) |
| Do mod-added tomes work? | Keyword checks include any tagged form in the active load order. | The link lookup reads the loaded book record, including standard mod-added books and overrides. It also identifies an untagged spell-teaching book if the lookup is reached. | The same content-based lookup applies to the winning loaded records. Standard ESP/ESM and light-plugin records need no static tome list. [SKSE Book implementation](https://github.com/ianpatt/skse64/blob/v2.2.6/skse64/PapyrusBook.cpp) · [NG Book implementation](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/src/RE/T/TESObjectBOOK.cpp) |

Papyrus Extender is useful for cataloging loaded forms with `GetAllForms` and identifying nonstandard teaching targets with `GetSpellType`. That function returns the spell subtype, such as spell, power or ability. It does not provide a skill tier. The core per-book lookup needs no additional Extender function. For character evaluation, use the player's `GetBaseActorValue("Magicka")` and `GetBaseActorValue(school)`, or the corresponding native actor values. Whitelist the five spell schools and check the base readings with temporary buffs and depletion in the runtime probe. [Papyrus Extender declarations](https://github.com/powerof3/PapyrusExtenderSSE/blob/master/Papyrus/Source/scripts/PO3_SKSEFunctions.psc) · [Extender Spell implementation](https://github.com/powerof3/PapyrusExtenderSSE/blob/master/src/Papyrus/Functions/Spell.cpp) · [Actor.psc](https://github.com/ianpatt/skse64/blob/v2.2.6/scripts/vanilla/Actor.psc) · [NG ActorValueOwner](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/include/RE/A/ActorValueOwner.h)

### Classification policy

1. Preserve existing acquisition eligibility and exemptions in the first experiment. Inside that population, resolve the book and taught spell from the loaded record. Record tagged books with no spell and untagged books with a spell as coverage differences. Script-only spell grants on book activation need explicit integration to yield a taught spell.
2. Use the costliest effect for both school and tier so the two values describe the same effect. Log all effects in the probe to see how often that choice conflicts with spell intent. If the selected effect lacks a valid school, has unsupported minimum skill, or conflicts with a recognized vanilla school/tier perk, mark the result unresolved during the first pass. For later support, use an explicit pair override for outliers backed by record inspection.
3. Start by checking the conventional exact values `0 → Novice`, `25 → Apprentice`, `50 → Adept`, `75 → Expert` and `100 → Master` against representative records. Treat this as a project mapping of effect metadata. The perk's unlock requirement, vendor availability and ritual quest requirements are separate progression systems. Log custom values such as 90 and review them before defining any bucketing rule. A valid zero on a school effect is possible. A failed lookup must produce a distinct unknown result.
4. For a later rollout, a candidate unresolved-data policy is to retain the existing Magicka decision for that tome and omit school-specific backlash. This preserves current handling for malformed or unusual records until they have an explicit classification. Keep the probe observational for both resolved and unresolved results.

## Spell difficulty

| Input | Value for the design | Compatibility and limits |
| --- | --- | --- |
| Effect minimum-skill tier | Predictable baseline, easy to explain and tune. Characters can anticipate which books are safe. | Requires the primary-effect policy above. It will follow changes to winning effects and can disagree with a mod's perk or displayed categorization. |
| Loaded spell base cost | Captures some differences within a tier without looking at the current caster. | Manual overrides, auto-calculation, casting type, magnitude, duration and area can make the number a poor model of comprehension. A cheap utility spell may be complex. Concentration cost per second and a one-shot cost have different units. Check raw/loaded values, including zero and sentinel values. |
| Effective casting cost | Useful to compare recorded costs against engine behavior. | Character-dependent. Skill and cost reduction can enter twice if effective cost is added to a model that already measures skill. Perks, gear, discounts and runtime changes can dominate. Keep it diagnostic. |
| Tier with bounded cost refinement | Retains predictable tier progression and lets unusually demanding spells move slightly within a tier. | Needs a measured cost baseline for comparable spells. If later justified, use a reference median per school, tier and casting type, and limit the offset to ±5 competence points. Start with comparable fire-and-forget spells. Leave the offset at zero for sparse groups and unreliable costs. |

For a future hybrid experiment, define `costOffset = 5 × clamp((baseCost / referenceMedian) − 1, −1, 1)` for validated comparable costs and a positive reference median. Add it to the tier target. The 10-point maximum swing is smaller than the 20-point spacing between tier targets. Keep the offset disabled initially so the tier and competence weights can be tested independently.

## Provisional competence model

Use a single score for the current player and the current tome. All values below are design knobs. Read them once per evaluated acquisition. Apply the model only after the usual exclusions and context gates.

~~~text
M = player's base Magicka
S = player's base skill in the chosen school
t = tier index, Novice 0 through Master 4

magickaContribution = clamp((M - 100) / 5, -10, 30)
competence         = clamp(S, 0, 100) + magickaContribution
target             = 15 + 20 * t + costOffset
margin             = competence - target
~~~

At 100 Magicka, school skill does all the work. Each additional five base Magicka adds one point up to +30. A Magicka-heavy character with skill 15 can qualify for Apprentice, while even the full bonus leaves them short of Adept. A character with skill 75 and starting Magicka can qualify for Expert. A school specialist at skill 100 and Magicka 75 can handle Master at the provisional boundary. Uncapping Magicka would eventually let a large pool substitute for any skill. The cap gives investment a benefit while preserving the value of school training. Skill clamping also limits runaway totals in progression overhauls. The examples use a zero cost offset.

### Trigger, resistance and severity

1. **Trigger.** For deterministic testing, every eligible acquisition with a valid classification activates its protection check. Successful resistance can be silent. If occasional protection is desired later, roll once per eligible acquisition with a context-specific probability `pTrigger`, independent of player competence. Keep it fixed across tiers initially to avoid conflating frequency with difficulty. Safe contexts and exemptions have `pTrigger = 0`. For repeat trials use one draw per acquisition under test, with explicit batch semantics before supporting stacks or Take All.
2. **Resistance.** Recommend `margin >= 0` as a guaranteed safe outcome. For an optional softer variant, use `pResist = clamp(1 + margin / 25, 0, 1)` with an independent draw when a protection triggers. Characters within 25 points below threshold may resist and those at or above it always do. Randomness adds variety but makes outcomes harder to learn from and invites repeated attempts or reloads. Deterministic resistance keeps the first balance experiment reproducible.
3. **Severity.** Only apply severity on a triggered, unresisted outcome. Use `severity = clamp((target − competence) / 40, 0, 1)` as a normalized effect intensity. A near miss can map to a mild feedback band, while a 40-point shortfall reaches the maximum band. Choose school-specific effect bounds separately in the ESP. A successful resistance produces no harmful effect. The probability roll does not alter the severity of a failure.

The severity and resistance formulas both use the margin, but frequency, success and intensity can be tuned independently. Under the optional randomized model the total failure probability is `pTrigger × (1 − pResist)`. Any triggered consequence in this design is hypothetical.

| Character | Base Magicka / school skill | Tome tier | Score / target | Deterministic result | Optional resist chance if triggered | Severity if failed |
| --- | ---: | --- | ---: | --- | ---: | ---: |
| Starting character | 100 / 15 | Novice | 15 / 15 | Safe | 100% | — |
| Starting character | 100 / 15 | Apprentice | 15 / 35 | Fails | 20% | 0.50 |
| Magicka investment, little training | 250 / 15 | Apprentice | 45 / 35 | Safe | 100% | — |
| Magicka investment, little training | 250 / 15 | Adept | 45 / 55 | Fails | 60% | 0.25 |
| Trained specialist, small pool | 100 / 75 | Expert | 75 / 75 | Safe | 100% | — |
| Master specialist, reduced base pool | 75 / 100 | Master | 95 / 95 | Safe | 100% | — |
| Broad investment | 200 / 65 | Master | 85 / 95 | Fails | 60% | 0.25 |
| Starting character | 100 / 15 | Master | 15 / 95 | Fails | 0% | 1.00 |

## School-specific protection

Use the resolved school to select a separate mod-owned protection spell or effect profile. A failed Restoration check could present a ward flare and a custom short drain. The ward itself is a visual reference. The taught healing spell is never part of the execution path. Keep severity separate from spell selection so effect magnitudes, durations and visuals can be tuned within each school.

| School | Vanilla inspiration | Candidate protection design |
| --- | --- | --- |
| Alteration | Paralyze hit presentation | Brief stagger or movement slow. Keep full paralysis out of the first test. |
| Conjuration | Soul Trap visuals and impact | A short binding or Magicka drain with no summon or soul capture. |
| Destruction | Fire Rune burst or a shock-impact effect | A bounded elemental hit with no lingering world rune or area damage. |
| Illusion | Fear or Calm audiovisual effects | Brief disorientation using an image-space or sound cue, with no change to nearby actors' AI. |
| Restoration | Lesser Ward art and audio | Ward flare with a separate detrimental effect aimed at the handler. Avoid the ward's armor and absorption benefits. |

Inspect the corresponding vanilla records in xEdit for effect archetypes, delivery, impact art, sounds and attached scripts. The named spells are starting points for visuals and audio. Build the later ESP records around controlled delivery to the player and verify resistance, animation, sound and collateral effects on their own. [Official Skyrim Special Edition guide spell catalog](https://primagames.com/eguides/elder-scrolls-v-skyrim-special-edition-eguide/Training/inventory/spells) · [NG EffectSetting](https://github.com/alandtse/CommonLibSSE-NG/blob/ng/include/RE/E/EffectSetting.h)

## Implementation boundaries and edge cases

- **Papyrus** can resolve the link, classify the spell, read base stats, compute the policy and select a protection record. Keep the first pass on demand with no progression tracking or serialized cache. If repeated metadata reads prove material, measure before adding a load-scoped cache. Check whether any supported mod changes effects or schools at runtime before assuming metadata is immutable.
- **Native code** is useful when [Investigation 01](01-pickup-pipeline.md) establishes a time-sensitive detection or interception requirement. It can inspect typed effect data and manual-cost flags directly and avoid a chain of VM calls. Use the same effect selection, tier mapping and formulas on either side. A synchronous interception needs the complete decision available at the engine boundary. Papyrus can still handle outcomes or reporting asynchronously. Keep ownership of each decision and mutation singular. A native metadata bridge alone is unnecessary for the initial model.
- **ESP and MCM** can later supply form properties, exception records and bounded effect profiles. MCM can expose stable policy settings once they are chosen. The existing Required Magicka slider retains its current meaning during evaluation. Reinterpreting it as a competence or difficulty setting would need a separate settings and migration decision.
- **Content exceptions** include empty or mixed effect lists, tied costs, school-less visuals or scripted effects, custom spell subtypes, noncanonical skill values, missing or mismatched perks, and zero/negative or extreme recorded costs. Book names, keywords, equipment slots, and which spells the player already knows do not establish the teaching link or tier. Preserve quest and safe-tome checks. Test a tome that teaches an already-known spell separately from handling a fresh tome, and inspect whether explicit exceptions are needed.
- **Acquisition exceptions** include vendor exemptions, same-base copies, repeated pickups and batch transfers. A later random mode needs an unambiguous decision unit to avoid accidentally giving one stack several rolls or processing the same transfer twice. The read-only probe needs no per-item saved state.

## Remaining runtime experiments

1. Compare read-only Papyrus output against the winning BOOK, SPEL and MGEF records in xEdit. Log the book, taught spell and effect FormIDs, effect indices, school and minimum skill, half-cost perk, and available costs. Include tagged and untagged mod-added tomes, a light plugin, an override, ordinary and skill books, script-only grants, mixed-school effects, an empty/invalid link and several Master records. Use a separate test harness in a later task so this investigation leaves the installed scripts alone.
2. Verify the primary-effect rule and five tier boundaries against each school's vanilla records and representative spell overhauls. Compare SKSE's index and the native pointer/query if a native observer is later available. Record disagreements, including any ambiguous zero-index result. Keep unresolved values out of the new rule until reviewed.
3. Compare base and effective costs on manual and auto-calculated spells, zero-cost spells, concentration and fire-and-forget spells, with and without perks or gear. Compare the effective reading with the UI cost and record conditions and rounding. Verify that temporary effects, current Magicka loss, and equipment leave the intended competence inputs stable, while legitimate base changes move them.
4. Run a trace-only pass of the formula with the table builds and exact threshold boundaries. Check prediction stability after save/load and with older saves, including the unchanged live decision and town, barter, quest and exclusion controls. Measure the metadata pass under single and burst acquisition using the timing guidance from Investigation 01. Use these results to decide whether tier-only competence is sufficient and whether any native work is justified.
