# Safe branch-mining pilot

For a first underground ATM10 deployment, use the [one-turtle deployment checklist](ATM10_FIRST_TURTLE.md): pinned existing installer, starter supplies, tight bounds, private bay and supervised acceptance record. Do not start a fleet before the single-turtle Minecraft gate passes.

The single-turtle engine prepares one bounded mining job. An optional [bounded fleet coordinator](FLEET_MINING.md) now assigns approved jobs to compatible workers. The reproducible tests use actual Lua modules in CraftOS-PC with a simulated turtle, world, inventory, and persistent filesystem. They do not establish survival or fleet readiness. Gates C and D below remain unverified in Minecraft.

## Reproduce the local checks

Install CraftOS-PC for your platform. On macOS the default runner executable is `/Applications/CraftOS-PC.app/Contents/MacOS/craftos`; elsewhere set `CRAFTOS_BIN` to its installed executable.

From the repository root:

```sh
for part in $(seq 1 16); do
  python3 cc-factory/tests/run.py --part "$part/16" || exit 1
done
python3 cc-factory/tools/verify_distribution.py
```

The 88 single-turtle cases run in sixteen disjoint ordinal parts, with five or six cases per part. The harness yields between engine instructions, matching the factory event loop and avoiding accumulated emulator watchdog time across simulated actions. Each native emulator invocation has a 240-second harness budget; a whole-suite timeout is a harness limit, not evidence of product safety or failure.

The runner creates an isolated emulator directory, mounts source read-only, prints an evidence directory, and exits nonzero for a failed assertion, crash, missing report, or emulator timeout. It never opens Minecraft or connects to a world. The evidence directory contains the test report and actual terminal screen dumps. No npm test dependency is required. `verify_distribution.py` checks source/bundle equality, manifest inclusion and native installer readback. Render the final status screens with `python3 cc-factory/tests/run.py --screens`; this produces native terminal dump JSON for every detail page.

The simulation models physical turtle pose independently of the job journal, solid and open cells, finite or unlimited fuel, sixteen inventory slots, receiver capacity and transfer readback, supported torch placement, failures and interruption after physical motion. Its scope excludes game physics, pack recipes, real chunk loading, fluid flow, falling-block timing, and physical readability of the user's display.

## Build and stage the installer

From `cc-factory`:

```sh
node bundle.js
```

`dist/factory.lua` is an **unpacking installer**. Transfer this exact reviewed artifact using a disk or another chosen file-transfer method. Save the installer on the turtle as a distinct filename such as `safe-mining-install.lua`; do not name the installer `factory.lua` in the directory it will unpack into. Run `safe-mining-install` to write the modules, then run the extracted `factory` program. This local change has not been published as a pinned remote installer URL.

Preserve old job journals when updating files. A journal belongs to a specific job, turtle identity, configuration, world declaration, home, and saved pose. Changing files does not authorize deleting or resetting that record.

## Prepare the bay and pilot area

Before any destructive run, make a world backup. Verify the current pack's mining turtle recipe and actual tools in its recipe viewer. Choose one small solid test area, away from builds, containers and other turtles. Keep a walkable rescue route and the whole route loaded during the supervised pilot.

Record the actual dimension, coordinates, heading and complete excavation bounds, including neighbour inspection and lighting niches. The program checks supplied coordinates and generated geometry; it does not independently authenticate its physical location or dimension. A marked home bay and human verification are required.

Default bay: output inventory **below** the turtle and supply inventory **above** it. These must be distinct inventories, readable through the inventory peripheral API. Keep the forward entrance clear of storage and machines. Supply only coal, torches and cobblestone unless you deliberately configure another supported fuel or solid fill item. Load carried fuel, torches and fill material before the first run. Leave inventory capacity for mining.

The mine uses a two-level route with symmetric branches, inspected neighbours and lighting niches. Branch interval 3 is not a fleet separation guarantee. Unknown blocks, fluids, unknown openings, unsealable ore holes and failed operations stop with a reason; they do not permit destructive bypasses.

## Launch and keyboard controls

In the existing TurtleOS menu, choose **Mine → Branch Mining**. The setup wizard asks one labelled question at a time, collects explicit home/heading/world and job identity, and proposes bounds for the tiny default mine. Invalid input is reprompted. **Q + ENTER** cancels setup without turtle actions. The wizard then opens the same factory preflight screen as the CLI; it still requires ENTER confirmation before mining.

The following is a command template for a **future supervised test**, using an illustrative home at `0,64,0` facing north. Replace the home, dimension and bounds with the actual prepared area before use. The illustrated bounds include neighbour inspection around the tiny 6 / 3 / 2 mine; review the displayed bounds before starting.

```text
factory mine --job pilot-one --dimension minecraft:overworld --home 0 64 0 --heading north --bounds-min -4 63 -8 --bounds-max 4 66 0 --length 6 --branch-interval 3 --branch-length 2 --torch-interval 3 --output-side down --supply-side up
```

- **ENTER: START** confirms the displayed physical home or saved pose. No turtle action occurs before this confirmation.
- **Q: STOP** saves a stopped job. It does not return home automatically.
- **R: RETURN HOME** requests checked path retracing and output unloading.
- **LEFT / RIGHT** and **PAGE UP / PAGE DOWN** show details, including complete long failure reasons. Detail keys do not advance mining.

Status uses white text on black, explicit state labels and keyboard controls. Small terminals reflow details into labelled pages. The terminal's font size is controlled by the actual game/emulator display; verify readable size and contrast on the user's screen before starting.

Rendered examples from synthetic status fixtures using the native terminal renderer: [READY at 39×13](docs/evidence/ready-home-39x13-page1.png), [saved-pose confirmation](docs/evidence/ready-saved-39x13-page1.png), [complete error details](docs/evidence/needs-help-39x13-page2.png), and [DONE at 51×19](docs/evidence/done-51x19-page1.png). These illustrate display behavior, not an in-world mining run.

The [setup prompt at 39×13](docs/evidence/setup-home-39x13-page1.png) shows the one-question layout, input correction, and keyboard cancellation.

The engine keeps a recorded cleared return route, budgets its fuel reserve, unloads only into a verified inventory, retains configured supplies during service, and restores the exact work pose and instruction before continuing. Successful completion requires verified home pose and output transfer. `DONE` is not a claim that the surrounding world was inspected by a human.

## Resume and reconcile

To resume a clean stopped or safely failed job, repeat its exact command with `--resume`, verify the saved physical pose and heading, then press ENTER. The default journal is `mining-<job>.checkpoint`; `--checkpoint <path>` chooses a different path. Keep the same job and configuration.

An interrupted physical action, unresolved action intent, corrupted journal, or leftover `.next` staging file requires manual reconciliation. Automatic movement is refused. Compare the physical turtle, inventory and world with the saved record before deciding how to repair or retire the job; do not blindly delete the journal and relaunch at a guessed origin.

## Current local evidence

The ATM10 first-turtle refresh adds four tight-bound, starter-loadout cases at a nonzero underground origin. Its [validation receipt](tests/atm10-first-turtle-results.txt) records the current run separately from the historical evidence below. Minecraft gates C and D remain unverified.

The original foundation native runner passed 83 cases with exit status 0. One subsequently added factory R dispatch case also passed in a focused run, bringing the verified set to 84 unique cases. [Retained test output](tests/validation-results.txt) records the exact commands and counts. Native status/setup rendering produced 16 terminal pages across 39×13, 39×19 and 51×19. The current fleet change packages 53 modules; both native installers passed source readback, and the existing ArcadeOS suite previously passed all 53 cases. The current source refresh completed 77 unique cases with no assertion failures across four disjoint parts: two parts passed, and two were cancelled when delivery was requested, leaving seven cases unrefreshed. [Current refresh receipt](tests/fleet-baseline-results.txt) preserves those exact limits.

Regenerating the installer also synchronizes previously stale bundled copies of unchanged designer, JSON, schema and UI modules. Their source files were not edited for this mining change; the existing ArcadeOS regression suite covers that distribution update.

## Remaining acceptance gates

**C — Supervised survival pilot: unverified.** One turtle must finish the tiny two-sided mine, return to the marked home facing, transfer output into the intended receiver, and stop. Inspect mined bounds, untouched containers, torches and support, floor/headroom, fluids, dropped items and remaining fuel. Repeat a stop/resume exercise and a forced-interruption reconciliation exercise. Check pack-specific ores and chunk unloading separately.

**D — Separate-area scale test: unverified.** Start with two independently labelled turtles and jobs, separate bays and inventories, and non-overlapping full excavation/lighting/return areas. Measure supply and storage capacity. Verify whole-route chunk loading and repeat complete cycles before expanding. Shared routes require explicit traffic control. The optional [fleet coordinator](FLEET_MINING.md) reserves disjoint approved work and supports same-worker known-home reuse; its software tests do not establish gate D in-world acceptance.
