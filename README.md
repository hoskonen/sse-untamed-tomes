# Untamed Tomes v2

Untamed Tomes is a Skyrim Special Edition / Anniversary Edition mod in development. Spell tomes found in the world can retain magical energy and reject a character who lacks the ability to handle them. Merchant purchases are intended to be safe.

## Current implementation

- A player alias script listens for inventory additions and identifies spell tomes by keyword.
- An open barter menu and towns, cities, inns and stores exempt pickups. Safe keywords, a FormList and a reference-based quest-item check provide additional exemptions.
- An eligible pickup below the configured base Magicka threshold triggers silent removal of one copy.
- The SkyUI MCM script exposes enable and debug toggles and the Magicka threshold.
- The progression classifier captures a first-pickup baseline for player level and six base magic skills. Debug logging records its observations. Tome rejection still uses base Magicka.

Both Papyrus scripts compile. The repository lacks the ESP containing the quests, player alias and property bindings required to run the mod. Skyrim runtime verification remains pending. Delayed backlash and reliable purchase attribution are planned.

## Build setup

Install Skyrim SE/AE and Creation Kit with the Bethesda Papyrus compiler, flags file and vanilla Papyrus sources. Obtain the matching SKSE64 scripts, the SkyUI Papyrus SDK/source distribution, and powerofthree's Papyrus Extender sources. Use Pyro from the Papyrus Language Tools VS Code extension or a standalone installation. Task 03 verified the Pyro bundled with Papyrus Language Tools 3.2.0.

If you already have a local `skyrimse.ppj` set up, keep using it. Otherwise copy [skyrimse.ppj.example](skyrimse.ppj.example) to `skyrimse.ppj` in the repository root and replace the four placeholder values in its `Variables` section.

| Variable | Required directory |
| --- | --- |
| `GameFolder` | Skyrim installation root with `Papyrus Compiler\PapyrusCompiler.exe`. The template imports `Data\Scripts\Source` from this root. Adjust that import if your Creation Kit sources are under `Data\Source\Scripts`. Make sure the imported source directory contains `TESV_Papyrus_Flags.flg`. |
| `SkseSources` | SKSE64's `Data\Scripts\Source`, containing `UI.psc` and the extended declarations. |
| `SkyUiSources` | SkyUI's `dist\Data\Scripts\Source` or equivalent full SDK source directory containing `SKI_ConfigBase.psc` and its dependencies. |
| `PapyrusExtenderSources` | Papyrus Extender's `Source\scripts` directory containing `PO3_SKSEFunctions.psc`. |

The SkyUI source directory needs its own import. Installing only the runtime files or pointing at the parent of the SkyUI source tree leaves the compiler without the MCM base declarations.

## Compile

From the repository root in PowerShell, set `$pyro` to the path of `pyro.exe` and `$game` to the same Skyrim root used in the project variables.

```powershell
& $pyro skyrimse.ppj --game-path $game --no-incremental-build
```

Check the build summary for two successes and verify that `Scripts\UT_PlayerMonitor.pex` and `Scripts\UT_MCM.pex` were generated. For VS Code, open `SkyrimSE.code-workspace` with Papyrus Language Tools installed. The local build task uses type `pyro`, `projectFile` set to `skyrimse.ppj`, `gamePath` set to your Skyrim installation, and the `$PapyrusCompiler` problem matcher. Store the task under `.vscode/tasks.json`. The local PPJ, VS Code settings and PEX outputs are ignored.

Task 03 verified a fresh build with the official dependency sources and no compiler warnings or errors. The sandboxed run failed while loading `Antlr3.Runtime`. The same installed compiler worked outside the sandbox. An earlier staging run also produced Pyro path warnings when the project and imports were on different drives. The verified build used staging on the dependency drive.

## Roadmap

1. Recover the ESP and verify quest, alias and MCM wiring in an isolated test profile.
2. Verify baseline capture and save/load behavior before integrating the classifier into tome eligibility.
3. Prototype delayed backlash and test inventory event handling.
4. Investigate tome spell metadata, magical effects and merchant purchase attribution.

See the [project overview](docs/01-project-overview.md), [current-state audit](docs/02-current-state-audit.md) and [recovery roadmap](docs/03-recovery-roadmap.md).
