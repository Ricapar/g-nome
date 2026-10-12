# R5 — Mission 1-1 sandbox in Godot 4

Status: **todo**

## Goal
The first playable piece of the remake. Load mission 1-1 ("Renegade Mercs") from the exported
data, start as the Union soldier on foot, walk to the parked Union HAWC (Prowler), climb in
(commandeer), drive it inside the mission bounds, collide with rocks and the parked Mercs,
eject again, and switch between cockpit and trailing camera. No weapons (R6), no AI (R7), no
animations (R4), no HUD art. Movement numbers come from R3. Until R3 lands they are
placeholders and are marked as such in code.

## Background
- Roadmap Phase 1 ("vehicle controller driven by the original parameters") and the start of
  Phase 2 (vertical slice 1-1) in `remake/README.md`. Decisions that apply here: data
  definitions are kept apart from visual slots, original models are placeholders and set the
  scale, and gameplay numbers come from the original code and are checked against telemetry.
- Builds on the mission viewer `remake/game/viewer/mission_viewer.gd` (loads the JSON, places
  glTF models at runtime with `GLTFDocument`, builds sky, fog and the ground plane) and on
  `tools/export_gamedata.py` → `remake/game/_import/data/*.json` (gitignored, never commit).
- Godot 4.7.2 (winget `GodotEngine.GodotEngine`, `godot` on PATH). The project is
  `remake/game/project.godot` (main scene: the model viewer).

## What is already known
### Mission 1-1 data (facts, from `script7l.py` listings and `layouts.json`)
- Main script 8744: `script_2515(10200, -(9150), 3000, -(10200))` → setup 8736 (world row 0
  = desert) → `script_2523(1, 8743, 0)` spawns layout array 8743 → `script_8746` stores ids →
  `script_8737` starts the mission (`docs/analysis.md` "Missions, units and layouts").
- Layout 8743 has 75 rows of `[unit_row, runtime_id, x, z, y, heading*100, flag]`:
  - row 1: Union infantry (unit row 5, init 2834 → 2842, model 2813) at (-4950, 75), heading
    18000. `script_8737` sets `G973 = row 1 object`, so **G973 is the player object**.
  - rows 2–6 = `G33[0..4]`: 2 Merc Sentry HAWCs "Ogre" (unit 11, init 3108 → 3119, model
    3072) and 3 Merc Tactical Defense HAWCs "Minotaur" (unit 12, init 3165 → 3177, model 3129).
    The difficulty switch in 8737 (`G2114`) deactivates 1–3 of them with `script_2133(obj, 0)`.
  - row 7 = `G13[0]`: **Union Sentry HAWC "Prowler"** (unit 0, init 2619 → 2631, model 2583)
    at (-4988, -1238), heading 9000, about 1310 units from the soldier. 8737 makes it empty
    with `script_2094(G13[0], 0, 0, 0)` (cockpit type 0, team 0). This is the HAWC to board.
  - rows 8–9 = `G625[0..1]`: waypoints (unit 32, category 500). The rest are rocks (cat. 250)
    and scenery (cat. 253/255).
- Objectives (`missions.json`): head for waypoint one, destroy the Merc raiding party,
  commandeer a Darken vehicle. No Darken unit is in the layout, so a later script spawns it
  (not needed for R5).

### Map bounds (facts, scripts 2515/2359–2366/2418)
- `script_2515` stores the bounds: G1833 = x max (10200), G1834 = x min (-9150), G1835 = z max
  (3000), G1836 = z min (-10200). They equal the layout's x/z extents.
- Desert ground (script 2418) tiles exactly this rectangle in 600-unit steps with four tile
  templates (2414/2416 alternate along z, 2415/2417 on the next column), at `SetLevel -100`.
  The viewer instead uses a fixed 600x600 plane.
- `script_2359(obj)` returns 1 outside the rectangle. The player update script 2360 checks the
  player's vehicle (`GetProperty(G973, 126)`, else G973). When outside it plays a warning
  (wave 2352, or 2355 in the x<0, z<0 corner) and arms a timer (`sc4` statement, read as
  slot 10 → script 2363 after 10000 ms; hypothesis). 2363 and 2364 escalate (waves 2353/2356,
  then 2354). 2365/2366 then set prop100 = 0 and call `script_1649(obj, 0)`, which kills the
  unit. Coming back inside calls 2362 (clear). Nothing in the scripts clamps the position.
  Whether RENDER.R32 also clamps natively is unknown.
- **Exporter bug:** `export_gamedata.py` parses the bounds with
  `script_2515\(([^)]*)\)`, which stops at the first `)`. `missions.json` therefore holds
  `"10200, -(9150"`. Fix it (parse `-(n)`) and export the bounds as four integers.

### Scale (new, strong hypothesis)
- Exported glTF heights (model units, computed from node matrices × vertices) × 100 = game
  units: Prowler 52, Ogre 55, Minotaur 76, soldier 16. The codex heights (`LABTEXT.DAT`) are
  6.8 / 6.9 / 9.5 m, so **1 game unit ≈ 0.125 m** (Ogre and Minotaur match exactly).
- This explains R3's codex factor: kph = prop35 × 0.45 = prop35 × 0.125 m × 3.6, so **prop35
  is in game units per second**. Prowler 155 → 70 kph, Ogre 189 → 85, Minotaur 160 → 72.
- Consequences: a ground tile is 75 m, the 1-1 map is about 2.4 × 1.65 km, the far clip of
  3000 is 375 m and fog 2000 is 250 m. The soldier starts about 164 m from the Prowler.

### Original controls (facts from arrays; column meanings partly hypothesis)
- Arrays **2548–2552** are the five keyboard presets, in the order of strings 199–203 (G-NOME
  Flight Sim, G-NOME Arcade, MechWarrior2, EarthSiege2, Shattered Steel). Each is 63 × 8: one
  row per action, in the order of action-name strings 132–194. Row layout:
  `[action_id, oneshot, mod1, key1, mod2, key2, mod3, key3]`, keys are Win32 VK codes.
  `mod`: 1 = CTRL, 2 = SHIFT (confirmed: Exit Game = 2:Esc, the README's SHIFT+ESC),
  3 = joystick input n (n → string 314+n: 1 Joy Right … 13 Hat Up … 17 Joy Btn 1),
  5 = key with no modifier, 0 = key regardless of modifiers (0 vs 5 is a hypothesis).
  `oneshot` is 0 for held actions (turn, throttle, pitch, fire, pan) and 1 for presses.
- Array **2544** (98 × 17) is indexed by action_id. Column 0 is the handler script; 0 means
  the action is handled natively in RENDER.R32 (turn 0/1, throttle 2/3, torso 5/6, pitch 7/8,
  fire 29–32, pan 36–41, move 69/70, joystick 72/73). Examples: Stop 4 → 1957, Full Throttle
  11 → 1956, Reverse 68 → 1929, Eject 27 → 1942, Eject Passengers 28 → 1944, Trailing Camera
  34 → 2191, External Camera 35 → 2172, Align Body 74 → 1966. Columns 1–16 are unknown flags.
- Preset 0 (Flight Sim) bindings that matter for R5: Turn Left/Right = Left/Right (held);
  Increase/Decrease Throttle = Pad+/Pad- or CTRL+Up/CTRL+Down (held); Full Throttle =
  CTRL+Enter or 9; Reverse = SHIFT+Enter or 8; Stop = Enter; Pitch Down/Up = Up/Down
  (Arcade swaps them); Twist Torso = `,`/`.`; Center Torso = Space; Align Body = CTRL+Space;
  Eject = Backspace; Eject Passengers = CTRL+Backspace; Trailing Camera = C; External Camera
  = V; VISOM cam = CTRL+V; Kneel/Stand/Prone = K/L/J; Fire 1–4 = 1–4; Exit Mission = Esc.
  Move Forward/Backward (69/70) are unbound in presets 0–2.
- So **movement is throttle-based**: speed is a setpoint that persists (`script_2064(obj, v)`
  clamps v to [prop36, prop35] and writes prop12). Up/Down aim. This also holds on foot (1956
  has an infantry branch). Which preset is the default is unknown: there is no `Keyboard=` in
  the INI, and `GKEY0-3.MAP` on the disc are empty placeholders for custom maps.
- `docs/transcripts/README` (named in the task) does not exist. The disc `README.TXT` lists
  only ALT+F4, SHIFT+ESC, PAUSE and SPACE.

### Commandeer and eject (facts from scripts; offsets in `script7l.py` output)
- Properties: 0 = class code (<100 infantry, 100–199 vehicles, ≥200 structures), 54 = team,
  115 = cockpit type (row of array 2216: overlay sprites, offsets, engine wave col 8,
  `ViewportCrop` cols 9–12), 77 = occupancy (-1000 = cannot be boarded), 78 = pilot,
  126 (on the pilot) = vehicle occupied, 127 = last vehicle.
- Boarding is **collision-triggered**: the infantry contact handler `script_2229` (reached
  through 2227 for class < 100) calls `script_2240(actor, target, 0)` for targets of class
  < 240 and ≠ 237. 2240 rejects class < 100, class ≥ 231 or prop77 = -1000. From a collision
  it also requires `DotProduct(actor, 0, target, 0) ≥ 9000` (a facing check; units unknown).
  For a friendly occupied vehicle it calls `script_2223`. The empty and enemy ("steal")
  branch starts at offset 0x04cc and has not been read.
- `script_2223(pilot, vehicle)`: pilot.126 = vehicle, `SetPosition(pilot, 0, 1000, 0)` (parks
  the pilot), pilot.18 = 5000, clears goal 2016, `script_423`. If the pilot is the player:
  `script_2219(vehicle)` (cockpit overlay, `ViewportCrop`, camera mode G972 = 1).
- Eject (1942): if G973's class ≥ 100 → `script_2241`; else if G973.126 is set →
  `script_2226(G973, G982, 0)`. `script_2226` puts the occupant at vehicle position
  + (100, 0, −150) game units (world axes, not rotated), clears props 37/23/111 and sets
  127 = vehicle. For the player it calls `script_2222` (overlay off, `ObjectSetState(vehicle,
  0)`, G973.126 = 0). Eject Passengers (1944 → 2225) does this for every object in `G781[150]`
  whose prop126 is the vehicle.

### Camera (facts from scripts 2171, 2191–2194)
- G972 = camera mode: 1 cockpit, 2 trailing, 4 external (free camera object from template
  2169), 5 = script 2170.
- Cockpit: `AttachCamera(G973, GetProperty(G973, 10), 0, L1, 0)`. Prop10 looks like the eye
  clump. L1 = prop56/20 when the model (prop39) has no clumps.
- Trailing (C): `AttachCamera(G973, 0, 0, base + 2d, −12d)` with base 30 (infantry) or 47
  (vehicle). d grows by 3 every 40 ms (timer → 2193) up to 15 (infantry) or 30 (vehicle).
  Pressing C again zooms back (2194), then returns to the cockpit. With 0.125 m/unit the
  vehicle trailing camera ends about 13 m up and 45 m behind.
- `SetCameraClipping(10, 3000)` (near/far in game units).

### Placeholder movement values (raw, from init scripts; meanings per R3's draft)
| | prop36/35 (rev/fwd throttle) | prop15 / prop33 | SetMaxAngularVelocity / Accel | SetMaxAccel |
|---|---|---|---|---|
| Prowler (2631) | -70 / 155 | 60 / 10 | 700,700,11000 / 700,700,7000 | 40 |
| Soldier (2842) | -15 / 71 | 5 / 5 | 700,700,12000 / 500,500,9000 | 70 |

Interpretation until R3 confirms: throttle in game units/s; yaw rate = 3rd component in
1/100 degree per second (110°/s Prowler); SetMaxAccel in units/s² (**guess**).

## Design
### Scene structure (`remake/game/sandbox/`)
```
Sandbox1_1 (Node3D, sandbox.gd)       loads data, spawns, owns the player controller
├─ World (WorldEnvironment, sun)      reuses the viewer's sky/fog/ground code (factor it out)
├─ Ground (StaticBody3D)              plane clipped to the bounds rectangle, collision layer 1
├─ Units (Node3D)
│  └─ Unit (CharacterBody3D, unit.gd) one per layout row with class < 200
│     ├─ Visual (Node3D)              visual slot: glTF placeholder now, new art later
│     ├─ CollisionShape3D             from the model AABB (see below)
│     └─ Eye (Marker3D)               cockpit camera mount
├─ Props (Node3D)                     rocks/scenery: StaticBody3D + shape + Visual
├─ PlayerRig (player.gd)              input → active Unit's controller; camera rig
│  └─ Camera3D
└─ Debug (CanvasLayer)                speed, throttle, heading, bounds warning, FPS
```
- Shared code goes into `remake/game/core/`: `units.gd` (one constant `M_PER_UNIT = 0.125`,
  heading conversion from R1, `game_to_world()`), `gamedata.gd` (JSON loading, cached),
  `model_cache.gd` (the viewer's `_model()`). The viewer is switched to it as well.
- Work in **metres** (game units × 0.125). The glTFs are in model units (game/100), so the
  visual slot scales them by 12.5. Using metres keeps Godot physics defaults sane. If the
  scale hypothesis fails, change the one constant.

### Data definitions vs visual slots
- `UnitDef` (Resource, built at load time from `units.json` and the R3 export): class code,
  team, speeds, turn/accel limits, eye offset, collision size, `visual_slot` (model id). No
  gameplay code reads the mesh. Collision size comes from the original model AABB, so new art
  cannot change gameplay.
- The R3 output (planned extension of `units.json`) fills `UnitDef`. Until then
  `placeholder_params.gd` holds the table above. Every value carries a
  `# PLACEHOLDER until R3` comment, and the debug overlay shows "PLACEHOLDER PARAMS".

### Vehicle controller (`unit.gd`, one script for soldier and HAWC for now)
- State: `throttle` (setpoint, units/s, clamped to [rev, fwd]), `speed` (actual), `heading`,
  `yaw_rate`, `torso_twist`, `pitch` (aim only, no gameplay yet).
- Per physics tick: speed approaches throttle with max accel; yaw rate approaches input ×
  max yaw rate with max angular accel. Turning from a standstill sets speed to the creep value
  (prop33, R3 scripts 1972/1973). Velocity is along the heading, gravity keeps the body on the
  flat ground, `move_and_slide()` handles collisions.
- The controller takes an abstract command struct (turn axis, throttle delta, set-throttle,
  stop, twist, pitch). Player input and later AI (R7) both drive it through that struct.
- If R3 or R4 shows root motion or animation-scaled speed, swap the integration step only.

### Input map (`project.godot` InputMap, names = original actions)
`turn_left`, `turn_right`, `throttle_up`, `throttle_down`, `full_throttle`, `reverse`,
`stop`, `pitch_up`, `pitch_down`, `twist_left`, `twist_right`, `center_torso`, `align_body`,
`eject`, `eject_passengers`, `camera_trailing`, `camera_external`, `kneel`, `stand`, `prone`,
`exit_mission`. Default bindings follow preset 0 above, including CTRL/SHIFT chords.
Godot `InputEventKey` modifiers must match exactly for "mod 5" bindings and be ignored for
"mod 0". Later (not R5): a loader that builds the InputMap from arrays 2548–2552, plus a
preset picker.

### Commandeer flow (sandbox version of the scripts above)
1. The soldier collides with a vehicle (`move_and_slide` collision, class 100–230, prop77 ≠
   -1000) while facing it (angle threshold: placeholder 90° until `DotProduct` is decoded).
2. Same-team or empty vehicle → board: hide and disable the soldier body (the original parks
   it at y=1000), set `pilot`/`vehicle` links, give the vehicle's controller the player
   input, switch to the cockpit camera at the Eye marker.
3. Eject (Backspace): place the soldier at vehicle position + (100, 0, −150) units in world
   axes, re-enable it, give it input, set the vehicle's `last_pilot`, and leave the vehicle
   empty (stopped, throttle 0).
4. Steal (enemy vehicle) is out of scope until branch 0x04cc of `script_2240` is read. Log
   "steal attempt" instead.

### Collision
- Units: `CollisionShape3D` box (or capsule for the soldier) from the model AABB in metres,
  centred on the AABB (rough sizes: Prowler 8.4 × 6.5 × 4.5 m, soldier 1 × 2 × 0.6 m).
  The original uses radii (`SetRadius`, `ClumpToClump`, `CollisionClump`,
  `Process_Sector_Collisions`). Replace the boxes with R3's radius model when it is known.
- Rocks and scenery: `StaticBody3D` with a convex hull (`Mesh.create_convex_shape()`) per
  glTF mesh, cached per model id. Rocks have no texture in the model; reuse the viewer's
  `rock_w<world>.png` override.

### Map bounds
- Read the four integers from the fixed `missions.json` `bounds`. Draw a faint boundary line.
- Behaviour as in the scripts: outside → warning stage 1, 2, 3 at 10 s intervals (show text,
  and play waves 2352–2357 once wave export, R8, exists), then destroy and respawn. Inside again
  → reset. Add an invisible wall about 300 m outside the bounds so you can't drive off the
  ground (remake-only, flagged in code).

### Camera
- Cockpit: Camera3D at the vehicle's Eye marker (placeholder: AABB top − 10%; later prop10's
  clump from the glTF part tags). Soldier: eye at about 1.7 m.
- Trailing (C): offset (0, (base + 2d) × 0.125 m, −12d × 0.125 m) with the original zoom-out
  animation (d += 3 every 40 ms up to 15/30); C again zooms in, then returns to the cockpit.
- External (V): a free orbit camera, enough for debugging.
- Near/far 1.25 m / 375 m × DrawDistance factor; fog depth from `worlds.json` × 0.125.

## Step-by-step plan
1. Fix the bounds parsing in `tools/export_gamedata.py`, re-export, and check that 1-1 gives
   `[10200, -9150, 3000, -10200]`.
2. Factor `core/units.gd`, `core/gamedata.gd`, `core/model_cache.gd` out of the mission viewer.
   The viewer must look the same afterwards (`--shots 1-1`).
3. Apply R1's heading/handedness convention in `units.gd`. If R1 isn't done, use the viewer's
   current `rotation_degrees.y = heading/100` and mark it.
4. Write the sandbox scene: world, ground clipped to bounds, units and props with collision.
5. Write `unit.gd` with placeholder params, the input map and `player.gd`. Spawn the player as
   layout row 1.
6. Add the commandeer and eject flow and the camera modes.
7. Add bounds warnings, the debug overlay and a Godot telemetry recorder in the R2 CSV format
   (`P` rows per physics tick: x, y, z in game units, heading in 1/100°, vfwd, actions).
8. Add a `--script` CLI mode, mirroring the viewer's `--shots`: a list of timed inputs
   (`hold:turn_left:2000`, `shot:name`) so runs are repeatable without a human.
9. When R3 lands, replace the placeholders, delete `placeholder_params.gd` and re-run the
   comparisons.
10. Update `remake/README.md` (roadmap, how to run) and `docs/analysis.md`.

## Verification
- Starts at the soldier position facing the original heading. The Prowler is about 164 m away
  in the same direction as in the original (compare drive.ps1 screenshot at mission start).
- Throttle up, turn, stop and reverse work with preset-0 keys. Speed plateaus at
  fwd × 0.125 m/s (Prowler 19.4 m/s, about 70 kph on the overlay).
- Walk into the Prowler while facing it → cockpit view. Backspace → soldier beside it.
- You can't pass through rocks or Mercs. Leaving the bounds gives three warnings, then death.
- Trailing camera zoom-out and return match the original's distances.
- With real R3 numbers: R2 CSV comparison (`tools/telemetry.py original.csv remake.csv`)
  agrees on top speed, time to top speed and turn rate within about 5%.

### Side by side with the original
- Original (windowed, `Display=1`; go ahead without asking per CLAUDE.md): boot path to the
  1-1 cockpit, then e.g. `shot:start`, `hold:LEFT:2000`, `shot:turned`, `key:9`, `wait:5`,
  `shot:moving`, `key:ENTER`. `drive.ps1` has no Backspace, Pad+ or CTRL chords yet. Add
  `BACK = 0x08`, `ADD = 0x6B`, `SUBTRACT = 0x6D` and a `chord:CTRL+UP:<ms>` step (small
  tool change, part of this item).
- Remake: the same sequence through the `--script` mode, screenshots at 640x480. Compare with
  Read: horizon, positions of the Prowler, rocks and Mercs, camera height.
- Telemetry: run both with the R2 recorder and diff.

## Open questions / risks
- Default keyboard preset (0 or 1)? Check the in-game Options → "Change Keyboard Mapping"
  screen with a windowed screenshot.
- Exact meaning of mod 0 vs 5 and of array 2544's flag columns.
- Boarding facing check (`DotProduct` units), the empty/steal branch of 2240, and what
  prop40 = 17000 means (script 349 compares it with `ObjectDistance`, so it may be a
  hint/boarding range in other units).
- G973 as a vehicle: 1942's class ≥ 100 branch suggests the player object can itself be a
  vehicle in other missions. Does boarding swap G973 (`script_423`/`2219`)?
- Does RENDER.R32 clamp positions to the bounds, or are only the script warnings used?
- Scale: 0.125 m/unit rests on model heights and the codex factor. Confirm with R2
  (measured speed in units/s against prop35).
- Root motion (R3/R4): if speed is animation-driven, the controller's integration changes.

## Dependencies
- **R1** (heading/handedness): needed for correct spawn orientation. A temporary convention is
  OK.
- **R3** (movement parameters and units): replaces the placeholders. R5 can start before it.
- **R2** (telemetry): needed for the numeric comparison step only.
- **R4** (animations): optional. Static poses are fine for R5 unless R3 finds root motion.
- **R8** (waves): optional, for bounds warnings and engine sounds.
- Feeds R6 (weapons on the controller), R7 (AI drives the same command struct).

## Notes to fold into analysis.md
- Bounds: `script_2515` → G1833..G1836 (xmax, xmin, zmax, zmin). Ground tiles fill exactly the
  bounds (script 2418). Out-of-bounds: 2359/2360 → 2361 → 2363 → 2364 → 2365/2366 (kill).
- Scale: 1 game unit ≈ 0.125 m (model heights vs codex). prop35 throttle in units/s
  (kph = × 0.45).
- Key presets: arrays 2548–2552 (63 × 8, row layout above). Action table: array 2544 (handler
  script per action id). `GKEY0-3.MAP` are empty placeholders.
- Player = G973 (layout row 1). Vehicle/pilot properties 0/54/77/78/115/126/127. Board =
  2223, dismount = 2226, eject all = 2225, contact boarding via 2229 → 2240. Cockpit table
  = array 2216.
- Camera modes G972 and `AttachCamera` offsets (scripts 2171, 2191–2194).
- 1-1 globals: G1 = row 1, G33[0..4] = Mercs, G13[0] = Prowler, G625[0..1] = waypoints.
- Exporter bug: `missions.json` `bounds` truncated by the regex.
