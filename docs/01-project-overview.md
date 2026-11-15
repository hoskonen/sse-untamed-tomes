# Untamed Tomes project overview

Untamed Tomes is a Skyrim Special Edition / Anniversary Edition mod. Wild spell tomes can reject characters with insufficient magical capability. Merchant purchases are intended to be safe. The original development PC failed, leaving an earlier source snapshot in Git. Continue on `dev/untamed-tomes-v2` and compare any recovered files separately before integrating them.

## Architecture

| Component | Role in the audited snapshot |
| --- | --- |
| [UT_PlayerMonitor.psc](../Scripts/Source/UT_PlayerMonitor.psc) | A `ReferenceAlias` script designed to receive the player's `OnItemAdded` events. It identifies tomes, applies safety gates and silently removes one copy when base Magicka is below the configured threshold. |
| [UT_MCM.psc](../Scripts/Source/UT_MCM.psc) | A SkyUI `SKI_ConfigBase` script with enable and debug toggles and a Required Magicka slider. It writes the globals read by the monitor. |
| [ESP snapshot](../UntamedTomes.esp) | Versioned copy of the reconstructed MO2 development plugin with main and MCM quests and shared settings. The [audit](02-current-state-audit.md) records the expected runtime bindings. |
| [skyrimse.ppj.example](../skyrimse.ppj.example) | Template for an ignored local `skyrimse.ppj`. Inputs are under `Scripts/Source`, compiled output targets `Scripts`, and packaging and zip generation are disabled. |
| [SkyrimSE.code-workspace](../SkyrimSE.code-workspace), [meta.ini](../meta.ini), [.gitignore](../.gitignore) | VS Code Papyrus language settings, placeholder mod-manager metadata, and ignore rules for compiled PEX files and local developer settings. |

## Build and runtime requirements

| Dependency | Purpose |
| --- | --- |
| Skyrim SE/AE and Creation Kit | The CK provides the SSE Papyrus compiler, vanilla script sources and `TESV_Papyrus_Flags.flg`, and is used to inspect or reconstruct the ESP. |
| SKSE64 | Compile with its script sources, including `UI.psc`, and run with a build matching the installed Skyrim executable. `UI.IsMenuOpen` supplies the barter check. [SKSE releases](https://skse.silverlock.org/) |
| SkyUI | Add a compatible SDK source directory containing `SKI_ConfigBase.psc` and its dependencies. Install SkyUI in the test profile for MCM registration and callbacks. [SkyUI MCM base source](https://github.com/schlangster/skyui/blob/master/dist/Data/Scripts/Source/SKI_ConfigBase.psc) |
| powerofthree's Papyrus Extender | Compile against the matching `PO3_SKSEFunctions.psc`. Install the compatible native plugin, scripts and its release-specific prerequisites so the reference-based quest-item guard can run. [Papyrus Extender source](https://github.com/powerof3/PapyrusExtenderSSE/blob/master/Papyrus/Source/scripts/PO3_SKSEFunctions.psc) |
| PPJ runner or direct compiler | Use a PPJ-aware runner such as Pyro, or invoke the SSE compiler directly with the same source imports and flags. VS Code is optional. [Pyro build tool](https://github.com/fireundubh/pyro/blob/master/README.md) |

Follow the [README build instructions](../README.md#build-setup) to configure the local PPJ. The template imports the full SkyUI source directory explicitly and lists the SKSE sources ahead of the game sources to resolve extended declarations. It performs a script-only build.

Task 06 generated both PEX files using the installed dependencies and the working Pyro project. The [MCM configuration audit](04-mcm-configuration.md) lists the remaining Skyrim runtime checks for the reconstructed ESP.
