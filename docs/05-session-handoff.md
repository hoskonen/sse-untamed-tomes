# Session handoff — schema 17 checkpoint (16 November 2026)

Start here to continue without repeating earlier investigations. Each detail below links to the investigation that holds it.

> **Update (18 November 2026): schema 19 shadow evaluator, deployed and uncommitted.** World-path parity is 13 of 13, at 4–9 µs per decision ([Investigation 23](investigations/23-native-eligibility-shadow.md)). It found a defect: with the mod disabled, world tomes are refused (§11).
> - **Next:** fix the §11 and §13 prerequisites, run the container session (§12), then Task 15C (§15).
>
> **Update (17 November 2026): schema 18 is committed and runtime-tested in part.** Single-Take pickup, two references and movement cancellation were verified in game ([Inv. 21](investigations/21-single-interaction-acquisition.md) status). [Investigation 22](investigations/22-native-eligibility-feasibility.md) recommends a native eligibility evaluator, validated first in shadow mode (Task 15B).
> - **What it adds:** single-Take acquisition. After approval, the original activation is replayed automatically through `ActivateRef` from an SKSE task, under a one-shot `Continuing` token. [Investigation 21](investigations/21-single-interaction-acquisition.md) covers the design, the test procedure S1–S13 and the rollback.
> - **Next recommended task:** run S1–S13. Then build the immediate native visual reaction at activation.
>
> The rest of this document describes the schema 17 checkpoint.

## Current state

Schema 17 provides:
- interception of world-tome activation;
- asynchronous Papyrus eligibility;
- authorisation per reference, bound to the actual inventory transfer;
- safe failure handling: never forward without an answer;
- DEST-compatible unified read enforcement.

It is an experimental, opt-in checkpoint, **not production-ready**.

| Item | Value |
| --- | --- |
| Native repository | `untamed-tomes-skse`, branch `dev/untamed-tomes-v2`, commit `b4a8568` |
| Papyrus repository | `sse-untamed-tomes`, branch `dev/untamed-tomes-v2`, the commit that adds this file |
| Schema | 17 (`observer_load schema=17`) |
| Runtime tested | Skyrim SE/AE 1.7.104, SKSE 2.3.1, Address Library format 5 |
| Dependencies in the test profile | Read Or Take 1.5.1, Don't Eat Spell Tomes 1.2.3 (overriding DESTified's bundled 1.2.2), DESTified 2.0 RC3 with the user's Script Fixes, PapyrusExtender |
| Deployed DLL | `89A638E42C7F9108188D8CAC95ED4DB4050B49C5FACE4FCC26B32A491417B90F` |
| Deployed PEX | `2E1FE3358B4E81839DEE042FBB7FDDB1BB638EF7ECFDBDDA1A26BEEA3D8577E4` |
| Markers (`%USERPROFILE%\Documents\My Games\Skyrim Special Edition\SKSE\`) | `UntamedTomes.WorldTomeHandshake` (Firebolt `000A26FD` only), `UntamedTomes.EnforceTomeReads`, `UntamedTomes.DebugTrap`, `UntamedTomes.FireTrap` |
| Build note | Builds are not byte-reproducible (MSVC and Pyro embed timestamps). The deployed files are the runtime-tested binaries, preserved as `task12-preservation/hardened-schema17.dll` and `hardened-UT_PlayerMonitor.pex`. Also, `xmake` installs into the MO2 mod on every build |
| Rollback | Inv. 20 §11. Native `task12-preservation/` holds schema 16; `task11-preservation/` holds schema 15 |

## Verified in game

[Inv. 20 §1](investigations/20-handshake-validation-and-hardening.md#1-schema-16-runtime-evidence-16-november-2026-18521855) and [§12](investigations/20-handshake-validation-and-hardening.md#12-schema-17-runtime-results-16-november-2026-19381944):

- world rejection, with the tome left in place and a pulse on it;
- re-evaluation after the cooldown;
- eligible pickup of a previously rejected reference;
- grant binding and consumption, with no second evaluation and no trap;
- two references authorised and collected independently;
- inventory reads forwarded through the DEST-compatible read hook;
- reset and Papyrus re-registration on save and load.

## Verified offline only

There are ten suites; `world_tome_handshake` has 26 cases. They cover:
- the timeout, unavailable and capacity paths;
- stale, duplicate and mismatched answers;
- overlapping and interleaved grants;
- persistent-reference matching;
- the scope filter.

## Open

[Inv. 20 §13](investigations/20-handshake-validation-and-hardening.md#13-open-validation-gaps-not-passed-offline-tests-do-not-substitute):

- DESTified study completion. DESTified logs property-initialisation warnings at every load.
- Save and load while a request is pending or an authorisation is active.
- Exemptions: safe location, `UT_TomeSafe`, quest references, exclusions.
- Missing-handler recovery.
- Read Or Take disabled.
- Unusual concurrent transfers.
- The ineligible chest path with the handshake active.
- The full Ancestries load order.

## Remaining work

1. **Single-activation pickup** for eligible and exempt world tomes. This is the high-priority item ([Inv. 20 §14](investigations/20-handshake-validation-and-hardening.md#14-the-two-activation-limitation-high-priority-follow-up)).
2. **An immediate visual response at activation**, from native code, before the roughly 0.6 s Papyrus evaluation.
3. **Real defensive effects that originate from the tome.** The world reference stays loaded, so it can be the caster (Inv. 18 §5). The post-pickup firebolt hit 2 of 6 indoors (Inv. 17–18).
4. **More gameplay and compatibility testing**, using the sessions in Inv. 20 §9 and the gaps above.

## Next recommended task

**Investigate safe automatic continuation of the activation for eligible or exempt world tomes, without weakening the pre-pickup veto.**

Answer the six questions in Inv. 20 §14:
1. `ActivateRef`, the previous handler, or `PickUpObject`;
2. the owning thread and game state;
3. recursion and a one-time continuation token;
4. Read Or Take's Take or READ choice;
5. movement, cell, menu and load while pending;
6. owned items and theft.

Do this before writing any implementation.

## Key facts not to rediscover

| Fact | Detail | Source |
| --- | --- | --- |
| Activation slot and veto | Book activation is `TESObjectBOOK` vtable slot `0x37`. Read Or Take replaces it at `kPostLoad` and never chains. Untamed Tomes wraps it at `kPostPostLoad`. Returning false skips `ActivateRef`'s post-activation work, so the tome stays in the world | Inv. 18 |
| Threads | Activation, SKSE tasks and the Papyrus natives all run on a shared pool of game worker threads, not the input thread | Inv. 20 §6 |
| Inventory event timing | The player-inbound container event fires synchronously inside the forwarded activation | Inv. 18, 20 §12 |
| Papyrus timing | Evaluation takes about 0.55–0.6 s and dominates the latency. The location context lookup runs twice | Inv. 20 §8 |
| Existing saves | Script arrays added to an existing save fail at runtime; use scalar variables | Inv. 17 |
| DEST version | DEST 1.2.3, not 1.2.2, is needed on 1.7.104 (Address Library format 5) | Inv. 15 |
| `UT_ConsumeWorldTomeGrant` | Takes `(Form, Int, ObjectReference)`. Deploy the DLL and PEX together | Inv. 20 §11 |
