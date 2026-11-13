# Untamed Tomes v2

Untamed Tomes is a Skyrim Special Edition / Anniversary Edition mod in development. Spell tomes found in the world can retain magical energy and reject a character who lacks the ability to handle them. Merchant purchases are intended to be safe.

## Current implementation

- A player alias script listens for inventory additions and identifies spell tomes by keyword.
- An open barter menu and towns, cities, inns and stores exempt pickups. Safe keywords, a FormList and a reference-based quest-item check provide additional exemptions.
- An eligible pickup below the configured base Magicka threshold triggers silent removal of one copy.
- The SkyUI MCM script exposes enable and debug toggles and the Magicka threshold.
- The progression classifier captures a first-pickup baseline for player level and six base magic skills. Debug logging records its observations. Tome rejection still uses base Magicka.

Both Papyrus scripts compile. The repository contains a snapshot of the reconstructed MO2 development ESP with the main and MCM quests and shared settings. Skyrim runtime verification remains pending. Delayed backlash and reliable purchase attribution are planned.

## MCM configuration

`UT_MCM` reads and writes three mutable ESP globals. `UT_PlayerMonitor` reads the same records when processing pickups. Assign `UT_ModEnabled`, `UT_MagickaThreshold`, and `UT_DebugEnabled` on both scripts to their respective shared records. The menu rebuilds its option IDs internally. Leave SkyUI's `Pages` empty for the single unnamed page, and let `OnConfigInit` set `ModName`. The existing matching `ModName` override is harmless. SkyUI supplies `CurrentPage` and its constants.

Add future settings through the existing globals when both scripts need the value. The [configuration audit](docs/04-mcm-configuration.md) explains the decision, the recorded defaults, and the remaining runtime checks.

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

## Deploy to Mod Organizer 2

Create or select an existing Untamed Tomes mod folder in MO2. In the repository, create the ignored file `.vscode/mo2-deploy.json` with the absolute path to that mod folder. Forward slashes work in the JSON path.

```json
{
  "destination": "D:/path/to/MO2/mods/Untamed Tomes"
}
```

Add this entry to the `tasks` array in your local `.vscode/tasks.json`, alongside the Pyro task. It uses the Windows PowerShell executable by absolute path and sets the execution policy for that process.

```json
{
  "label": "Deploy to MO2",
  "type": "process",
  "command": "${env:SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe",
  "args": ["-NoProfile", "-ExecutionPolicy", "RemoteSigned", "-File", "${workspaceFolder}/tools/Deploy-ToMO2.ps1"],
  "problemMatcher": []
}
```

Compile first. Once Pyro succeeds, use **Tasks: Run Task → Deploy to MO2**, or run `& .\tools\Deploy-ToMO2.ps1` from the repository root in PowerShell. The deploy task runs only when selected.

The script validates both compiled inputs before copying `UT_PlayerMonitor.pex` and `UT_MCM.pex` into the mod's `Scripts` directory. It overwrites only those two files and leaves existing files such as MO2's `meta.ini` in place. The resulting PEX files still require an ESP with the correct script bindings for in-game use.

## Snapshot the ESP from MO2

Edit Papyrus sources in the repository, compile them, then deploy the PEX files to MO2. Edit the active ESP in the MO2 development mod through Creation Kit or xEdit. After saving and closing the plugin, use **Tasks: Run Task → Snapshot ESP from MO2**. Review and commit the resulting `UntamedTomes.esp` in the repository. Git stores versioned snapshots, and MO2 remains the active editing location.

The snapshot uses the same local `.vscode/mo2-deploy.json` configuration. Set `"espFile": "Untamed Tomes.esp"` if the MO2 filename contains a space. The default source filename is `UntamedTomes.esp`. Both map to the repository's `UntamedTomes.esp`, regardless of the name used in MO2.

Add this entry to the local VS Code `tasks` array.

```json
{
  "label": "Snapshot ESP from MO2",
  "type": "process",
  "command": "${env:SystemRoot}/System32/WindowsPowerShell/v1.0/powershell.exe",
  "args": ["-NoProfile", "-ExecutionPolicy", "RemoteSigned", "-File", "${workspaceFolder}/tools/Snapshot-EspFromMO2.ps1"],
  "problemMatcher": []
}
```

You can also run `& .\tools\Snapshot-EspFromMO2.ps1` from the repository root in PowerShell. The task prints both paths and verifies SHA-256. If the repository copy differs, type `SNAPSHOT` to replace it. Matching files require no write. Compilation and PEX deployment run independently, and the snapshot reads the MO2 plugin without writing to it.

## Roadmap

1. Verify the reconstructed quest, alias and MCM wiring in an isolated test profile.
2. Verify baseline capture and save/load behavior before integrating the classifier into tome eligibility.
3. Prototype delayed backlash and test inventory event handling.
4. Investigate tome spell metadata, magical effects and merchant purchase attribution.

See the [project overview](docs/01-project-overview.md), [current-state audit](docs/02-current-state-audit.md) and [recovery roadmap](docs/03-recovery-roadmap.md).
