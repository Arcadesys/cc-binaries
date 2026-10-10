# ATM10: one private underground mining turtle

This deploys the existing **cc-factory safe miner**, not cc-turtleos's other branch miner. One manually launched job, no fleet, no startup loop, no shared storage. Minecraft survival acceptance is **pending** until you perform the checklist below.

## 1. Gather and verify prerequisites

Record your server's exact ATM10 version, Minecraft/CC:Tweaked versions and dimension. The upstream files reviewed on 2026-10-09 were ATM-10 commit `e5e3d1d83ec6885bb9a5e9fb309fb8e9730db025`; these are not evidence of your installed server settings.

- In the installed pack's recipe viewer, check Computer → Turtle → Mining Turtle. CC:Tweaked's normal baseline is 7 iron ingots + computer + chest for a turtle, then a diamond pickaxe upgrade. The computer itself needs its own ingredients. Verify the actual pack recipes before crafting. A normal mining turtle is sufficient; advanced turtle, GPS tower, modem, RF power and chunkloader upgrade are not required by this miner.
- Gather two **separate vanilla single chests**, 32 coal, 32 ordinary torches and 128 cobblestone, plus your own lights, food and rescue tools. This includes carried and spare supplies. Avoid charcoal for this first job: its default fuel item is specifically `minecraft:coal`.
- Put 16 coal, 16 torches and 64 cobblestone in three turtle slots; keep the other 13 empty. Put the other 16 coal, 16 torches and 64 cobblestone in the supply chest. Initial fuel may be zero: after ENTER the engine consumes carried coal as needed. Default fuel margin is 8 movements, torch reserve 1 and fill reserve 8; these are return/service thresholds, not a guarantee for arbitrary terrain.
- The reviewed upstream CC config enables HTTP, permits non-private hosts, and requires fuel. Your server's effective configuration may differ. Test download access below, and verify a diamond-pickaxe upgrade is equipped. The miner does not authenticate the upgrade before starting; a failed dig stops it.

Primary references: [CC:Tweaked turtle APIs and baseline recipes](https://tweaked.cc/mc-1.21.x/module/turtle.html), [reviewed ATM10 CC config](https://github.com/AllTheMods/ATM-10/blob/e5e3d1d83ec6885bb9a5e9fb309fb8e9730db025/config/computercraft-server.toml). A search of that upstream snapshot's KubeJS server/startup scripts and datapacks found no ComputerCraft turtle recipe override; this does not establish recipes supplied by mod jars, your release or server customizations.

## 2. Mark a private bay

Back up the world. Choose a solid stone/deepslate pocket beside your underground starter room, away from existing builds, caves, fluids, bedrock and other players' mining. The first test is about return/unload correctness; diamond depth can wait. There is no automatic descent: place the turtle at the mining level yourself.

| Relative to home turtle at X, Y, Z | Place / purpose |
| --- | --- |
| X, Y-1, Z | Empty output chest: label **PRIVATE MINING OUTPUT** |
| X, Y+1, Z | Separate supply chest containing only coal, torches, cobblestone |
| Forward | Solid mining entrance; no container or machine |
| Rear / sides | Lit starter room and access to turtle and both chests |

Leave the turtle's entry cell open; leave the planned mine solid. Do not pre-dig a corridor through it: unknown openings stop this fail-closed miner. Maintain access from the room behind the turtle; follow its cleared passage for rescue after stopping it. Keep players, blocks and other turtles out of the recorded return route. Return retraces cleared cells and never digs/attacks a shortcut. Clear a blockage only while stopped, without moving the turtle or disturbing its journal.

The tiny job is a 6-block spine, branches at 3 and 6, two blocks on **each side**, with an upper return level and torch niches. Its complete local bounding box is right/left -3..3, vertical -1..1, forward 0..7. These include neighbour checks and lighting, not just turtle travel. The home floor and ceiling inventories are protected. The world box is 7 × 3 × 8 blocks, including the home plane; not every cell is excavated.

Claim every chunk intersecting the box and bay using your personal FTB team. Configure block interaction/edit access to exclude other players and allies; a shared team may grant members access, so do not assume a claim is personal. Verify with a non-OP second player that they cannot open either chest, operate/break the turtle or place/remove route blocks. Verify your turtle can mine inside the claim too; adjust only the required fake-player permissions under your server's policy. If either check fails, stop deployment until permissions are fixed. Claims are not protection against server operators.

Keep both inventories disconnected from pipes, hoppers, wireless/ender inventories, public terminals and shared storage networks. Never export this output to server shops or communal resource supplies. Separate storage is isolation, not an access-control mechanism by itself. Suggested sign: “I have automated my production to the point that it makes resources meaningless. If you like gathering things for yourself, it's best to avoid this system.”

[FTB Chunks](https://docs.feed-the-beast.com/mod-docs/mods/suite/Chunks/) and [FTB Teams](https://docs.feed-the-beast.com/mod-docs/mods/suite/Teams/) document claims and team permissions; actual settings and turtle authorization require the in-game checks above. Stay beside this small job, keeping the entire bay/mine loaded; pick a one-chunk footprint using chunk borders if convenient. No unattended/offline chunk-loading acceptance is implied.

## 3. Install the existing bundle

Use this immutable reviewed installer (existing artifact, no new installer). These commands run **inside the turtle shell**, one line at a time:

```text
label set Austen-private-pilot-01
mkdir /safe-mining
cd /safe-mining
wget https://raw.githubusercontent.com/Arcadesys/cc-binaries/26cd98b7992a8c8c8204c84acd96bc5386d46904/cc-factory/dist/factory.lua safe-mining-install.lua
safe-mining-install
```

Use a fresh directory and stable label before creating the job; identity includes computer ID and label. The download is an unpacking installer, so its filename must differ from the extracted `factory.lua`. If HTTP is unavailable, transfer the same artifact via disk as `safe-mining-install.lua`, copy it into `/safe-mining`, and run it there. The installer writes source modules; it does not launch a miner or create an autostart script. Preserve journals on every update. Do not enable the other TurtleOS miner's “Start on boot.”

## 4. First run: wizard or exact CLI

From `/safe-mining`, run `turtle_os` and choose **Mine → Branch Mining**. Enter:

| Wizard field | Value |
| --- | --- |
| Job | `atm10-pilot-01` |
| New or resume | `new` |
| Home | Actual turtle block X Y Z (not player's feet) |
| Heading | Actual turtle forward direction |
| World / dimension | Actual resource ID, e.g. `minecraft:overworld` |
| Spine / branch interval / branch length / torch interval | `6` / `3` / `2` / `3` |
| Output / supply side | `down` / `up` |
| Bounds min / max | Review and keep generated values only if the full box is approved |

Q + ENTER cancels the wizard without turtle actions. The miner then waits on READY; read every detail page and verify physical home, heading, bounds, job and inventories before **ENTER**. Coordinates/dimension are human declarations, not GPS measurements.

For a CLI launch, replace **all** example coordinates and the dimension below. For north-facing home X,Y,Z, bounds are X-3,Y-1,Z-7 through X+3,Y+1,Z. For east: X,Y-1,Z-3 through X+7,Y+1,Z+3; south: X-3,Y-1,Z through X+3,Y+1,Z+7; west: X-7,Y-1,Z-3 through X,Y+1,Z+3. The wizard calculates these for you.

Example **only if** home really is `120 -48 -220`, north in the overworld:

```text
factory mine --job atm10-pilot-01 --dimension minecraft:overworld --home 120 -48 -220 --heading north --bounds-min 117 -49 -227 --bounds-max 123 -47 -220 --length 6 --branch-interval 3 --branch-length 2 --torch-interval 3 --output-side down --supply-side up
```

Save the exact final command/settings outside the game. Stay present throughout; use left/right or page keys for status details. **Q stops in place** and saves; **R after ENTER returns via the checked route**, unloads, then stops the partial job. Successful completion returns to the exact home heading, unloads all remaining items (including unused carried supplies) into the output chest and reports DONE. Move supplies back by hand before a later new job.

## 5. Recovery without guessing

| Observed state | Action |
| --- | --- |
| Clean Q stop | Repeat identical launch with `--resume`, or wizard `resume` with identical values. Verify saved physical position/heading, then ENTER. Do not put it back at home manually. |
| R return / STOPPED at home | Same resume process; resupply first. Resume restores the recorded work pose before continuing the partial job. |
| Receiver full / missing, supply exhausted, route blocked | Read full reason, stop, correct only that condition, verify saved pose and journal, then resume identical settings if no unresolved intent exists. No output spills or destructive route clearing are authorized. |
| Unknown ATM10 ore/block, fluid, cave opening, failed sealing | Stop and inspect. Modded ores are not automatically allowed by namespace or tags. Do not edit allowlists or dig around a live job; use a separately reviewed new test area if the job must be retired. |
| Termination/reboot during action; `.next`; corrupt journal; uncertain pose | Automatic resume is refused. Preserve checkpoint, staging file, screen/error and physical evidence. Compare pose, facing, route, inventory and action intent manually. Do not delete journals, relabel, pick up/re-place the turtle or relaunch at a guessed origin. Restore a backup or retire the job after reconciliation if exact state cannot be established. |
| DONE | Keep its journal. Do not reuse that job name to mine again or launch another turtle in its area. |

## 6. Physical acceptance record — fill in during play

All entries start **NOT RUN**. No second turtle or fleet until this single-turtle gate passes.

- Record pack/mod versions, dimension, turtle ID/label, full command, home/heading/bounds, initial fuel and supplies, and a screenshot of the bay.
- Verify owner access, non-OP visitor denial, turtle dig permission, readable terminal and loaded full footprint.
- Press ENTER; watch the complete tiny mine. Record DONE, exact home position/heading, actual chest output, remaining fuel, and no dropped items. Inspect full bounds, untouched containers, floor/headroom, torch niches/support, fluids and return route.
- In another disjoint approved tiny area with a new job name, exercise Q stop → verify saved pose → identical `--resume` → finish. Exercise R partial return → STOPPED → identical resume → finish. Preserve identity and both journals.
- On a backed-up sacrificial test, interrupt during an action; confirm an unresolved intent/staging record refuses motion on resume and perform manual reconciliation. A clean boundary reboot can resume and does not establish this interruption case.
- Record encountered pack block IDs and behavior. Unknown ore rejection is an expected safe stop, not evidence the ore can be mined. Chunk unload/reload needs its own controlled test later; stay present for this first run.

See [SAFE_MINING.md](SAFE_MINING.md) for engine details and acceptance gates. Passing this pilot permits planning a separate scale test; it does not itself establish fleet readiness.

## Local validation

Reuse `tests/run.py` and `tools/verify_distribution.py`; no new mining engine or installer. The ArcadeOS turtle-package manifest was refreshed from the existing generator to include current source dependencies and remove obsolete TurtleOS paths; unrelated package entries were preserved. The regression suite adds starter-supply/tight-bound cases for four headings at a nonzero underground origin. They model zero initial fuel, 16 coal, 16 torches, 64 cobblestone and finite output capacity. The simulator's capacity is an item-count abstraction, not real chest slot/stack packing. See [validation receipt](tests/atm10-first-turtle-results.txt) for actual commands and outcomes. Simulation cannot establish pack recipes, real tool dig permissions, claim privacy, fluids/gravity timing, actual chunk loading or Minecraft survival acceptance.
