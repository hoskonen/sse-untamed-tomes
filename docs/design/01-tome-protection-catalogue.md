# Tome protection catalogue

This design builds on the metadata and competence investigations and the distinction between reading a placed book and acquiring it. A teaching link identifies the spell. School and tier describe the spell's requirements. Neither identifies a lawful acquisition or directly determines a protection's strength.

## Generated record data

The native exporter enumerates loaded, non-deleted BOOK records with the teaches-spell flag. It includes the book, taught spell, effect list and casting perk. Stable identities consist of the originating plugin name plus the record's local FormID, with a 12-bit local ID for light plugins and a 24-bit local ID for full plugins. The runtime FormID and winning override plugin are also recorded. A form with no origin has no stable plugin key. A plugin rename or FormID compaction can invalidate an authored key.

To export, put an empty file named `UntamedTomes.ExportCatalogue` in the Skyrim user-data `SKSE` folder before launching through MO2. The first verified input callback after data load writes `UntamedTomesCatalogue.json` and `UntamedTomesCatalogue.md` to that folder. Remove the marker after the run. An ordinary launch leaves the exporter inactive. Move the mouse at the main menu if the export is still pending.

Use the engine's costliest-effect pointer to select the primary effect, and confirm it is present in the spell's effect list. Read the school and minimum skill from that same MGEF. Exact values 0, 25, 50, 75 and 100 map to Novice, Apprentice, Adept, Expert and Master. Missing metadata, an unsupported school or a noncanonical minimum yields unresolved confidence. An engine spell-school mismatch yields review confidence. Auxiliary effects can differ or be school-less and remain visible as evidence without vetoing a valid primary. The casting perk is exported as a cross-check for record review. It does not override the primary or set the tier.

Regression targets are Firebolt (Destruction, Apprentice) and Dead Thrall (Conjuration, Master). For Dead Thrall, inspect the primary reanimation effect separately from auxiliary effects. Verify the winning records when an overhaul changes either result.

## Proposed protection families

These are hand-authored categories for future mappings. The names describe design intent. No effects are implemented.

| School | Family 1 | Family 2 | Family 3 |
| --- | --- | --- | --- |
| Alteration | Warding and hardening | Binding and restraint | Displacement and environmental change |
| Conjuration | Summoning | Binding and banishment | Necromancy |
| Destruction | Fire | Frost | Shock |
| Illusion | Fear | Calm and suppression | Frenzy and misdirection |
| Restoration | Wards | Turning undead | Restoration and cleansing |

Store mappings separately from the generated catalogue. Each rule can match a stable spell key or a reviewed spell family, with school and tier as defaults. Firebolt can map to Fire and Dead Thrall to Necromancy. Never infer a family solely from localized names. Leave ambiguous records unmapped until reviewed. Record a separate `potency` or tuning profile per rule. An Apprentice spell can carry a weak or strong protection without changing its metadata or the competence threshold.

## First gameplay implementation

After reproducing the interaction baseline, start with one explicitly mapped vanilla tome and one deterministic competence decision on a verified interaction boundary. Keep protections initially limited to a visible cue on a loaded placed book in a disposable save. Preserve existing Papyrus behavior until acquisition and reading can be distinguished reliably, and avoid using the deferred inventory observer as a real-time decision point. The placed-reference visual test from Investigation 05 can precede any attempt to intervene in pickup or reading.
