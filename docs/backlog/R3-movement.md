# R3: Decode HAWC, vehicle and soldier movement (RENDER.R32 + unit scripts)

Status: **todo**

## Goal
Recover the movement model of every player-drivable class: bipedal/multipedal HAWCs,
treaded armoured support vehicles, hovercraft and on-foot infantry. That covers speed,
acceleration, turn rate, torso twist and weapon pitch, collision, ground/height handling,
camera and controls, in the original units, so that the Godot controller (R5) can copy it
1:1. The item also answers the ordering question in `docs/REMAKE-BACKLOG.md`: **is movement driven
by the walk animation (FRME, R4) or by parameters?**

Done when:
- every movement native the scripts use has a documented formula, units and timestep
  (`docs/analysis.md`);
- every movement property index has a name (list below, extended);
- a per-unit parameter table can be built by a tool (a `units.json` extension in
  `tools/export_gamedata.py`, written to the gitignored `_import/`);
- R2 telemetry from the original matches a simulation of the formulas (speed ramp, turn
  ramp, stop distance) for at least one HAWC, one tank, one hovercraft and the soldier.

## Background
- The remake README says "gameplay numbers come from the original code, not tuning by feel".
  Movement is the first system R5 needs.
- Script natives live in RENDER.R32 as exports. RTLIB resolves them with `GetProcAddress`.
  They are `__cdecl (void *ctx, int args...)`; see the hooks in `patch/gnomefix.c`
  (`hSetCameraClipping`, `hGetProcAddress`). The script call id is `0xFA + index` in the
  key-11 name list (`docs/analysis.md` "Script VM").
- All script arithmetic is int32: angles are in hundredths of a degree, positions in game
  units (600 = one ground tile = 6 model units).

## Already known (facts, from the script disassembly unless marked)
Listing: `.venv\Scripts\python -I tools/script7l.py ISO/G-NOME/G-NOME.BIN [ids]`.
Catalogue and codex join: `tools/export_gamedata.py` → `remake/game/_import/data/units.json`.

### Answer to the ordering question (preliminary: parameters)
Speed and turning are **parameter-driven**. The scripts set a throttle setpoint, a forward
velocity and angular limits directly. Animations follow the movement state (scripts call
`installAnimationType` when the throttle changes) and do not drive it. Still to check in
RENDER: does `doAnimationUpdate`/`AnimateFrame` move the object (root motion), and is the
walk playback rate scaled by speed? If neither, R5 can come before R4, and R4 only fixes
foot sliding.

### Per-unit setup (init script = catalogue column 1, e.g. 2619 → 2631 Prowler)
- `script_2066(obj, rev, fwd, a, b)`: prop36 = `rev` (max reverse throttle, negative),
  prop35 = `fwd` (max forward throttle). Units with `prop0 < 237` also get backups
  prop136 = fwd and prop137 = rev; `script_2315` restores 35/36 from them, so something
  (damage?) lowers the limits temporarily. prop15 = `a` (read by no script, so probably read
  natively; meaning unknown). prop33 = `b` is the creep speed: turning from a standstill sets
  the velocity to prop33 (scripts 1972/1973).
- `script_2074(obj, clumpA, clumpB, pmin, pmax)`: props 28/30 = arm clump indices, which
  `script_425` maps through the damage-state array (prop84) into props 29/31. prop26/25 =
  weapon pitch min/max (e.g. -900/1900 = -9..19 deg). prop27 = current pitch (clamped by
  `script_2075`/`2076`) and prop32 = pitch rate (keys add ±, decaying by 40 per tick,
  `script_1961`).
- `script_2070(obj, torsoClump, limit)`: prop21 → prop22 torso clump, prop20 = twist limit
  (18000 = unlimited), prop23 = twist command, prop24 = current twist. `StepTwist(obj, dt, 24,
  20)` and `script_2072` integrate it. `RotateSubClump` applies twist and pitch to the clumps
  (`script_2077`).
- `SetMaxAngularVelocity(obj, 700, 700, Y)` and `SetMaxAngularAccel(obj, 700|500, ..., Y)`:
  the third value varies per unit (HAWCs about 6000-11000, infantry 12000/9000). It looks like
  yaw (axis 2, see `SetTargetAxis` below); the 700s are probably pitch and roll.
  `SetMaxAccel(obj, n)` takes n = 20..70.
- `SetModelDimensions(model, idleFRME, obj, 55, 56, 57)` writes the collision box into props
  55-57, apparently measured from an FRME (hovercraft rows pass FRME 0). `SetProperty(obj, 40,
  17000)` is common to all units (prop40 feeds `script_2053`; not movement).
- Variants and quirks: the Union Lion checks `G982` (multiplayer flag) and uses fwd 110 and
  stats 20/1000 in multiplayer, but 200 and 90/2200 in the campaign. The Merc Legionnaire calls
  `SetMaxAngularVelocity` twice (10000, then 7000) and never sets angular accel, so the native
  default applies. That is probably a 1997 bug and must be reproduced. The Merc Ogre sets its
  angular accel before its velocity.

### Per-tick flow
- The player uses update script **1727** (`script_1724`/`1725` re-target `G973` = the player).
  AI units use **1723**, set by `SetUpdateScript(obj, 1723)`. `L1` = dt, also stored in
  `G1812`. Order in 1727: `SetTargetAxis(obj, prop37, 2, dt)` (yaw toward command prop37) →
  twist → `script_2065` = `ApproachTargetSpeed(obj, dt)` (velocity toward the setpoint),
  whose return value is added to prop98 clamped to [0, prop95] (`script_2055`) → recharge timers
  → **`script_1728`**: `UpdateTimeStep(obj, dt, 41)`, then `UpdateCollideCheck(obj, G1814, 30,
  0)` → collision response `script_2227` (uses `RevertPosition`) → `script_2077`
  (clump twist/pitch, camera pitch).
- Properties: prop12 = throttle setpoint (`script_2064` clamps it to [prop36, prop35], `2061`
  adds, `2063` reads). prop34 = current forward velocity (`script_2062` sets it and calls
  `SetVelocityForward`). prop37 = yaw command, -1/0/+1 for the player (1972/1973/1976). AI
  tasks pass prop35 as their speed (`setCurrentTask(..., GetProperty(u, 35))`, script 1991).
- Other paths: falling/landing (`script_1755`: `UpdatePosOrient` until `UpdateGroundCheck`
  reports ground, then y=0 and `SetGravity(obj, 0)`), projectiles (`SetGravity` from weapon
  table 1281 col 10, `SetVelocityForward`, scripts 1679/1682 → R6), infantry stances
  (types 5/7 = kneel/prone, 9/10 = stand up, `SetObjectFramerate(obj, 1500)`, scripts
  1748-1752).

### Controls
- Control schemes: **1978** and **1979** (throttle; they differ only in `script_1975(1, 0|1)`)
  and **1980** (no throttle). Actions are tested with `CheckActionState(2544, 2546, action,
  G1854+2, G1857)`. Action ids index arrays 2544-2547 (not decoded) and are **not** the
  string-table order ("Turn Left".. "Custom 4" are strings 136-198 in key 4).
- Throttle keys add ±5 to prop12 (scripts 1959/1960). The joystick throttle is
  `RangeJoystickAxis(2546, 72, prop36, prop35, 1)`. Key presets are set with `MapActionKeys(2544,
  2545, 2547, ...)` (scripts 2558/2559).
- Camera: `AttachCamera(G973, prop10, 0, dy, dz)` puts the camera on the cockpit clump prop10
  (scripts 2171/2199/2219). Camera pitch follows weapon pitch unless the camera sits on an arm
  clump (`script_2077`). Trailing and external cameras are in scripts 2191-2194.

### RENDER.R32 entry points (export table, read with pefile; image base 0x10000000)
`SetMaxAccel 0x1001671e`, `SetMaxAngularVelocity 0x1001678e`, `SetMaxAngularAccel 0x10016835`,
`ApproachTargetSpeed 0x1000ba71`, `SetVelocityForward 0x10017516`, `GetVelocityForward
0x1001284e`, `SetVelocityXZ 0x100175dc`, `SetTargetAxis 0x10016dd9`, `SetTargetAxisAngle
0x100170de`, `SetTargetTwist 0x1001714a`, `StepTwist 0x100177a4`, `UpdateTimeStep 0x10011ec1`,
`UpdatePos 0x1001817e`, `UpdatePosOrient 0x1001821f`, `UpdateOrient 0x100180fe`,
`UpdateCollideCheck 0x100182d0`, `UpdateGroundCheck 0x10017fbb`, `UpdateGroundHeight
0x1001804c`, `SetGravity 0x1001662f`, `SetGroundFlag 0x1001669c`, `SetLevel 0x100166c5`,
`RevertPosition 0x100162fe`, `CollisionBounce 0x10010d0f`, `ObjectPositionCollision
0x1002338f`, `Process_Sector_Collisions 0x100289d0`, `SetModelDimensions 0x100087ab`,
`SetRadius 0x10016d31`, `RotateSubClump 0x10016374`, `AttachCamera 0x1000748b`,
`SetCameraPitch 0x10009f15`, `CheckActionState 0x1000c631`, `MapActionKeys 0x1000d6e7`,
`RangeJoystickAxis 0x1000d184`, `EnableJoystick 0x1000d80b`, `doAnimationUpdate 0x1000b75a`,
`installAnimationType 0x1000b573`, `addAnimation 0x1000ae57`, `AnimateFrame 0x100105ec`,
`SetObjectFramerate 0x10016b8f`, `GetProperty 0x1001271e`, `SetProperty 0x10016c09`.
Also known (`docs/analysis.md`): object list at `+0x40264` (count `+0x40268`), object
`+0x98` model, `+0x54` flags, property count at `+0xe4`, property records after `+0xec`.
There is no heightfield in any mission: ground = flat plane, `DAT_10037ae4` NULL.

## Plan
1. ~~Check the class labels first.~~ Done in R0 (2026-10-14): 161 = treaded, 181/182 =
   hovercraft, confirmed by the models, stats and loadouts; `units.json` is re-exported.
2. Extend the exporter: per unit, parse the init script (and the `script_X(L0)` it calls) and
   record `script_2066/2070/2074` args, `SetMax*`, `SetModelDimensions`, and the `G982`
   branches. Output goes to `units.json` (gitignored).
3. REA (CLAUDE.md "Environment"): load the tools with ToolSearch, `open_binary`
   `ISO/G-NOME/RENDER.R32`, then `batch_decompile` the export addresses above in this order:
   setters (`SetMax*`, `SetVelocityForward`, `SetGravity`, `SetLevel`) to get the object-struct
   field offsets; then `ApproachTargetSpeed`, `SetTargetAxis`, `StepTwist`, `UpdateTimeStep`,
   `UpdatePos*`, `UpdateCollideCheck`, `UpdateGroundCheck`, `RevertPosition`,
   `Process_Sector_Collisions`. Name the struct fields (`set_address_name`, comments). Find what
   reads prop15 natively (`xrefs` on the property accessor used by `GetProperty`). Other agents
   share the backend: call `close_binary` when done.
4. Settle the timestep: what dt is (ms or ticks), where it comes from (RTLIB timer or
   `timeGetTime`), and whether `UpdateTimeStep` sub-steps or clamps (arg 41).
5. Check animation coupling: decompile `doAnimationUpdate`, `installAnimationType` and
   `AnimateFrame`. Do they write the object position, or scale the framerate from velocity?
   Record the answer in `docs/REMAKE-BACKLOG.md` (R4 before or after R5).
6. Decode control arrays 2544-2547 (action id → key, string, joystick axis), the three schemes
   and the presets ("G-NOME Flight Sim/Arcade", "MechWarrior2", ...).
7. Camera: `AttachCamera` offsets, trailing/external camera scripts 2191-2194, and the pitch
   coupling.
8. Write the formulas and a per-class summary into `docs/analysis.md`. Write a small reference
   simulator (Python, `tools/`) that R5 can be tested against.

## Verification
- **Codex speed**: with the class fix from step 1, `LABTEXT.DAT` kph = prop35 × 0.45 within
  rounding for 19 of 20 vehicles. Examples: Stalker 150 → 67.5 exact, Jinx 125 → 56.25 exact;
  Scorpion 65 → 29.25 vs 30 is loose. The decoded velocity
  units must explain the factor 0.45 (e.g. game units per tick × tick rate). Venom (prop35 100,
  codex 31.5) is the outlier to explain.
- **Telemetry (R2)**: log prop12/34/37, position and heading per tick for the player in mission
  1-1, on foot and after commandeering. Use `tools/dev/drive.ps1` with `hold:UP:<ms>` /
  `hold:LEFT:<ms>` (windowed runs only, per the CLAUDE.md launch rules). Compare the
  acceleration ramp, top speed, turn ramp, stop and creep behaviour against the simulator.
  Units in other missions are needed for the tank, hover and multipedal classes.
- The user judges feel side by side once R5 exists.

## Open questions / risks
- ~~Class labels look swapped.~~ Confirmed and fixed in R0. After the fix, Rampage, Stalker,
  WidowMaker, Scorpion and some stat-B values still differ from the codex text; the scripts
  are authoritative.
- What stat B (props 95/98) is. `ApproachTargetSpeed`'s return value drains or refills it, and
  1723/1727 reset prop98 to prop95 every tick. Energy? Shields?
- Meaning of prop15 and of `SetMaxAngular*`'s first two axes; angular units (deg/100 per
  second or per tick?).
- Hovercraft and tanks: is there any inertia, sliding or strafing (`SetVelocityXZ` is
  exported, but no script calls it)? Does the hover height come from `SetLevel`?
- Many movement natives (`MoveTo*`, `ObjectMoveForwardUp`, `SetObjectMotion`) have no direct
  script call. They may be called inside RENDER (AI tasks, R7) or be unused.
- Network (`G982`) code paths override some values; the campaign is the reference.

## Dependencies
- R1 (heading sign and handedness) before trusting yaw signs.
- R2 (telemetry) for verification; the decoding can start without it.
- Feeds R5 (controller) and, depending on step 5, decides R4's place. Shares natives with R6
  (pitch limits, projectile gravity) and R7 (AI speed via prop35, `MoveTo*`). The joystick
  path (`RangeJoystickAxis`, `EnableJoystick`) is relevant to P6.

## Notes to fold into analysis.md
Folded in by R0 (2026-10-14; analysis.md "Gameplay systems" → Movement, and the unit
catalogue bullets). Still to add when found: the native formulas and the export addresses'
decompiled semantics.
