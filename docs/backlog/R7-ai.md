# R7 — AI: decode the unit AI scripts and the RENDER.R32 behaviour natives

Status: **todo**

## Goal
Understand the enemy AI well enough to reimplement it in Godot with the original numbers:
target selection, attack, pursuit, circling/strafing, evasion and flight, guarding, patrol,
following and formation, obstacle avoidance and difficulty scaling. Start with the mission 1-1
Merc raiding party (2 Ogres, 3 Minotaurs). Deliverables:
- an annotated AI section in `docs/analysis.md`: task system, task scripts, property names
  and the native semantics;
- property and task-script name tables that `tools/script7l.py` can print;
- a written behaviour spec per task and per movement native, precise enough to port.

## Background
- The remake keeps gameplay faithful (`remake/README.md` "Decisions"): AI parameters must be
  recovered from the scripts and RENDER.R32, not tuned by feel.
- Nearly all AI *decisions* are script bytecode, which `tools/script7l.py` disassembles fully
  (2342 scripts, see `docs/analysis.md` "Script VM"). The *steering* is in RENDER.R32 natives
  (MoveTo*, the task-list natives, ApproachTargetSpeed). So this is mostly script reading plus
  a small set of native decompilations.
- Roadmap: Phase 0 step 4 ("decode ... the AI scripts") and step 5 ("RENDER.R32 natives: ... AI
  behaviours") in `remake/README.md`. R7 is last in the recommended backlog order.

## What is already known

### In the repo docs (`docs/analysis.md`)
- VM: statement dispatcher `FUN_1001f1f7`, expression VM `FUN_10003330`, globals
  `G<id>` (id < 0x13FE), locals `L<n>`. Calls with id ≥ 0xFA are plugin natives in key-11
  order (`script7l.Names`). `script_N(...)` calls type-19 script N.
- Objects: OB3D templates (`res7l.read_object`). The `[6, interval, script]` record is the
  update script. `[2, min, max, 19, script]` runs a script for a distance band. The property
  array sits at runtime object `+0xec+16*count`.
- Missions: table array 6984; 1-1 main script **8744**; layout **8743**; unit catalogue
  array 5843; spawner `script_2523`; unit init scripts (catalogue column 1).

### Found while writing this spec (read from disassembly, not yet in analysis.md)
To reproduce: `.venv\Scripts\python -I tools/script7l.py ISO/G-NOME/G-NOME.BIN <ids>`.
Tables come from `remake/game/_import/data/{units,layouts,objects,globals}.json`, written by
`tools/export_gamedata.py`.

**Mission 1-1 cast.** Layout row = `layouts.json` index + 1, because the JSON omits array
row 0.
- Row 1 = player (Union infantry), `G1` = `G973`.
- Rows 2-6 = `G33[0..4]` = 2 Ogres (catalogue row 11, template 3107, init 3108 → 3119)
  and 3 Minotaurs (row 12, template 3164, init 3165 → 3177).
- Row 7 = `G13[0]` = the Prowler to commandeer (catalogue row 0).
- Rows 8-9 = `G625[0..1]` = waypoints (category 500, init 3818).
- Start-up (8737): `script_2093(&G33, 5, 2, 2, -1)` puts all 5 Mercs on team 2, side 2,
  AI-controlled. It assigns **no explicit tasks**. Their behaviour comes from the defaults below.

**Per-tick chain.**
- Every vehicle template has `[6, 30, 1723]` (update script 1723, interval 30). Script
  1723 does this:
  - player → `1727`;
  - prop 133 set (unit disabled) → stop;
  - otherwise, in single player or as host: `G1812 = dt` and `script_419(obj, dt)`;
  - then `2065` (ApproachTargetSpeed, speed control), `1680`, and `1728`/`2272`.
- `419`:
  - prop 19 is a think countdown, reloaded from prop 18 (the think interval each task sets).
  - prop 124 is a retarget timer. When it expires, an AI unit (prop 77 < 0) runs `2339`
    (vehicles) or `2351` (infantry, prop 0 ≤ 24).
  - When prop 19 expires: `script_417(obj,0)` runs the current task script, then `403`
    processes the command queue in prop 53.
- Default task: `script_2530(1, 8743, G2433)` (G2433 = 1 in key 3) gives every AI vehicle
  `setNextTask(obj, 2024, 1, 0, 3000, …)`, i.e. guard and scan 3000 units. With G2433 = -1
  it would get task 2031 (hold). If a unit has no task, `2339` falls back to
  `script_2347(obj, 1, prop40)`: guard with the sensor range as the scan radius.

**Task system.**
- `script_412` creates a per-unit task list: `setTaskProps(58, 60)`, then prop 58 =
  `Clone(411)` (a 10 x 9 int array: 10 tasks x 9 fields) and prop 60 = current task index.
- A task is a row. Field 0 is the **task script id**, run with `script_L3(obj)` in 417.
  Field 3 is the target object. Fields 4-6 are parameters; field 6 is copied to prop 52.
- `insertTask/setCurrentTask/setNextTask(obj, script, prio, target, f4, f5, f6, f7, f8)`.
  The argument → field mapping is a hypothesis; fields 1, 2 and 8 still need the native.
- `existsGoal(obj, script, target)` returns the row or -1. `activateGoal(obj, row, prio)`
  re-prioritises an existing row. `completeTask` + `script_421` (calls `doNextTask`) pop to
  the next task. Hook `G991` fires on every switch.

Task scripts 2016-2031. Names are hypotheses from reading the code:

| Script | Hypothesis | Evidence |
|---|---|---|
| 2016 | move to target/waypoint | done when prop 108 (distance) < f4; f5 = speed |
| 2017 | infantry: go to / board vehicle | state machine in f5; completes if unit is a vehicle |
| 2018 | follow / escort target | keeps within 4/3·f4, matches target speed (prop 34) |
| 2019 | attack target | vehicle `2020`, infantry `2021`; leash: give up if target > f5 from f4 |
| 2020 | vehicle attack manoeuvre | uses prop 107/109 facing dots (×10000), ranges 450/700/1500 |
| 2022 | attack from a structure/turret | for prop 0 ≥ 200 |
| 2023 | guard object | scans f4 via `2015`, stays within f5 of target |
| 2024 | guard position / idle scan | think 2000 ms, `2015(obj, f4, obj, …)` |
| 2025 | harass, then break off | uses threat matrix 2317, `2033` evade / `2032` circle |
| 2026 | flee from target | `2033` (MoveToEvade) until distance ≥ f4 |
| 2027 | strafe/circle attack | Random(1,5) picks circle 1000-1300 or follow, for Random(10,20) thinks; fires if facing > 9950 |
| 2028 | patrol between f3 and f4 | swaps when < 500; scans f6 |
| 2029 | approach to f3, then parallel + scan | `2011` (MoveToParallel) |
| 2030 | circle target at radius f4, speed f5 | `2032` |
| 2031 | hold / do nothing | think 1000 |

- Order wrappers used by mission scripts:
  - `2342` move;
  - `2343(obj, target, prio)` attack;
  - `2344` guard object;
  - `2346` hold;
  - `2347(obj, prio, radius)` guard area;
  - `2348(obj, target, prio, dist, speed)` follow;
  - `2349` approach;
  - `2121`/`2122`/`2123` composite orders.
- Movement wrappers 2032-2038 map to MoveInCircle/Evade/Flock/Follow/Parallel/Pursue/TrueLead.
  Each wrapper first circles prop 70 (an obstacle) at `GetRadius+100` when prop 70 is set.
  `MoveToFlock` (2034) has 8 arguments, which is the formation candidate.

**Targeting and aggression.**
- `2015` (scan) calls `2337`. 2337 walks the 150-slot active list `G1816` and picks the
  **nearest hostile** object with prop 77 ≠ 0 (manned) that is closer than prop 40 (sensor
  range; Ogre and Minotaur set 17000). 2015 then also requires the target within the task
  radius, then calls `setNextTask(2019 attack)` and hook `G988(target, self)`.
- `2080` (hostility): both objects need a non-zero prop 113 (IFF code) and the codes must
  differ. Infantry compare side (prop 54) instead. `2082` also checks the occupants
  (prop 78).
- Threat matrices 2316/2317/2318 (41 x 41, indexed by the AI slot in prop 59, assigned by
  `2320` on activation):
  - `2323(attacker, victim, dmg)` sums damage within a 60-tick window (G1868 = the tick
    counter from `2571`). If the victim isn't the player it calls
    `424(victim, attacker, prop52)`.
  - 424 means "retaliate": attack the attacker (2019) once the summed damage ≥ the
    threshold, otherwise strafe (2027).
  - `2333` clears stale entries every 120 ticks.
- **Difficulty** is `G2114` (0/1/2, set by menu scripts 6936-6938):
  - `1677` (the AI fire decision) fires only if `Random(1, 3 - G2114) == 1`;
  - mission 1-1 deactivates 3/2/1 of the 5 Mercs (`script_2133(obj, 0)`) and sets the
    kill target `G2432` = 2/3/4.

**Mission ↔ AI hooks.** Missions set callback globals that the AI and damage code call:
- `G985` (destroyed, from 2278): 8740 counts kills of team-2 AI units toward `G2432`, then
  calls `script_8318(1,2)` (objective) and `script_2245` (win).
- `G984` (vehicle entered, from 2240): commandeer objective 8739.
- `G988` (spotted, from 2015): 8738 plays a message when the player is spotted.
- `G983` (from 2199/2241) and `G987` (damage, from 1709): used by other missions, e.g. 1-2.
- Other missions give explicit orders, e.g. 1-2 8759 (`clearTaskList` + `insertTask
  2016/2019`), 8763 (`2348` follow), 8757 (`2343` attack, `SetUpdateScript 1723`).

**Properties (H = hypothesis).**
- 0 class code: <100 infantry, 100-199 vehicle, ≥200 structure, 500 waypoint.
- 12 throttle target (2061/2064 clamp it to [prop 36, prop 35]); 34 current speed;
  35 max speed; 36 min speed.
- 18/19 think interval and countdown (ms, H).
- 40 sensor range.
- 47 hit/destroy handler (2242 default → 2278 explode).
- 52 aggression threshold (H).
- 53 command queue list.
- 54 side; 113 IFF code (H; the 1-3, 1-5 and 3-1 objectives include "Set IFF to …").
- 58/60 task list and current index.
- 59 AI slot.
- 62 secondary target/blocker (H); 63 fire-permission flag (H).
- 70 obstacle to circle.
- 77 control: 1 player, -1 AI, 0 unmanned. 78 occupant/pilot. 115 team (Merc = 2).
- 92 LOD band 0-2, set by distance-band scripts 2147-2149, which call `425(obj, lod)`.
- 107/109 facing dots ×10000 (self → target, target → self); 108 distance to target.
- 124 retarget timer. 133 disabled.

**RENDER.R32 export addresses** (image base 0x10000000, from the PE export table):
- Movement: MoveInCircle 0x10013054, MoveToFlock 0x10013167, MoveToFollow 0x10013179,
  MoveToParallel 0x1001328c, MoveToPursue 0x100133c2, MoveToEvade 0x10013575,
  MoveToTrueLead 0x1001368c, ObjectDeviate 0x10013fc6, ApproachTargetSpeed 0x1000ba71.
- Task list: setTaskProps 0x1001ac50, getTaskField 0x1001ac70, setTaskField 0x1001ad57,
  clearTask 0x1001aec9, clearTaskList 0x1001afd0, doNextTask 0x1001b0e9,
  setCurrentTask 0x1001b24f, setNextTask 0x1001b426, insertTask 0x1001b625,
  TaskSetHighestIndex 0x1001b98c, completeTask 0x1001bb74, changeTaskPriority 0x1001bc47,
  existsGoal 0x1001bd54, activateGoal 0x1001bf97, equalizeGoalPriorities 0x1001c162,
  getHighestPriority 0x1001c2aa, getLowestPriority 0x1001c37e.
- Geometry and properties: GetProperty 0x1001271e, SetProperty 0x10016c09,
  SetUpdateScript 0x100174b3, ObjectDistance 0x10013fd8, DotProduct 0x10011b21,
  PointAt 0x100144af, SetTargetAxis 0x10016dd9, SetTargetAxisAngle 0x100170de,
  StepTwist 0x100177a4, QueryClumpList 0x1000853e.

## Plan
1. Add a property-name table and a task-script name table to `tools/script7l.py`, behind an
   option such as `--names`, so listings print `prop[108:dist]` and `task:attack`. Start from
   the table above and mark each name verified or guessed.
2. Annotate the 1-1 path end to end: 1723, 419, 2339, 417/421, 2024, 2015/2337, 2019/2020,
   2027, 424/2323, 1677, 2008/2010 and 2032-2038. Write pseudo-code for each in
   `docs/analysis.md`. Cover the Ogre (3119) and Minotaur (3177) parameters: speeds via
   2066/2070/2074 (with R3), turn limits, sensor range and weapons (with R6).
3. Decompile the task natives with REA (`open_binary` on `ISO/G-NOME/RENDER.R32`,
   `batch_decompile` at the addresses above). Pin down the field layout (fields 1, 2 and 8,
   priority ordering, what `doNextTask` returns), `setTaskProps(58, 60)` (it tells RENDER
   which properties hold the list and the index) and the difference between set*Task and
   insertTask. Call `close_binary` when done.
4. Decompile the movement natives: MoveInCircle, MoveToPursue, MoveToEvade, MoveToFollow,
   MoveToParallel, MoveToTrueLead, MoveToFlock, ObjectDeviate and ApproachTargetSpeed. Record
   the inputs, the outputs (what the return value means; 2032 adds it to prop 27) and the
   steering law: turn-rate clamp, lead prediction, the mode argument 1/2. Note the units:
   fixed-point ×100 angles and ×10000 dots.
5. Confirm the property hypotheses through the GetProperty/SetProperty sites inside RENDER.R32
   natives: which properties RENDER itself reads (e.g. 12, 34, 35, 70) and how they map to
   object fields.
6. Survey the other missions' explicit orders (grep `insertTask|setCurrentTask|23[0-9]{2}\(`
   in a full listing) to cover patrol (2028), formation (2034/MoveToFlock) and flee (2026)
   before porting.
7. Port to Godot (with or after R5): an `AITaskList` node (10 slots x 9 fields, same
   priority rules), one GDScript per task script, steering functions mirroring the natives,
   a 30 ms update cadence and per-task think intervals, plus the threat matrix and the
   difficulty rules.

## Verification
- Every task script 2016-2031 and every movement native has a documented behaviour. Every
  property used by the 1-1 AI path has a name marked verified or guessed.
- R2 telemetry: record 1-1 runs in the original (windowed, `tools/dev/drive.ps1`) logging
  the position, heading, speed, current task script (prop 58 row at prop 60) and target
  (field 3) of each Merc per tick. Then:
  - Idle scenario: walk the player into sensor range. Engagement time, distance and approach
    path should match the remake within tolerance.
  - Damage scenario: shoot one Ogre. A retaliation switch to 2019/2027 should follow.
  - Difficulty 0/1/2: unit count and fire rate should match.
- Replay the same inputs in the Godot sandbox and diff the traces (time of first shot,
  approach distance, circle radius 1000-1300, strafe durations).

## Open questions / risks
- Field mapping of the task row and the priority semantics: needs the natives.
- Whether prop 113 really is the IFF code. Scripts 406-409 also treat it as `a*10+b` with
  an animation-like hook `G992`, so it may be overloaded.
- `G1225[side % 8]` values (98, 3929, 2234, …) as default IFF codes: unverified.
- RNG: `Random` and `Srand` come from RTLIB/RENDER. An exact replay needs the same generator
  and seed. Otherwise compare statistically.
- Timing: is the 30 in `[6, 30, 1723]` milliseconds or ticks, and how does `dt` (L1) relate?
  This is shared with R3.
- Network play routes AI through the host only (1723 checks `DPPlayerIsHost`). Ignore it for
  now.
- `script_403` command types (1-12) look like wingman/network orders. The scope is unclear.
- Contradiction: the objective says "Commandeer Darken vehicle", but `G13[0]` is catalogue
  row 0 (labelled Union Prowler). Either the catalogue faction labels are off or the team
  colour comes from prop 54. Check with R5.

## Dependencies
- **R2** (telemetry) for verification traces. Needs a task/target readout per entity.
- **R3** (movement): ApproachTargetSpeed, SetTargetAxis, UpdatePos and the speed/turn
  parameters (2066/2070/2074) are shared. Do R3 first.
- **R6** (weapons): the fire decision `1677`, weapons `1656` / array 1281, damage → `2323`.
- **R4** (animations): attack/walk animation types (`getCurrentAnimationType` in 2021).
- **R5** (sandbox) hosts the port. **R1** fixes heading/handedness for steering.

## Notes to fold into analysis.md
- **Correction:** props 72/75/93/130 are *not* AI scripts. In 3119/3177: 72 = a type-20
  sprite (it references a type-1 bitmap, likely the cockpit overlay), 75 = a ViewportCrop
  script, 93 = an array (14 x 8 for the Ogre), 130 = a LinkModel script. They look
  cockpit/HUD-related. The AI comes from the template update script 1723 plus the task list.
- Type-20 resources (913) are mostly 74-byte records that reference a bitmap id at +0x26
  (sprite definitions).
- Template records `[2, min, max, 19, 2147..2150]` are LOD-band scripts. They set prop 92
  (0/1/2) and call `script_425`, which picks per-LOD part ids into props 10/22/31/29.
- Array 427 (26 x 26) is a spatial hash with 1200-unit cells from -15600 (scripts 430-432).
  Arrays 2316-2318 are the threat matrices described above.
- Difficulty global `G2114`; tick counter `G1868` (script 2571); mission callback globals
  G983/G984/G985/G987/G988/G991/G992.
