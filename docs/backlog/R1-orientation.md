# R1: Fix mission viewer orientation against the original

Status: **todo**

## Goal
Make the Godot mission viewer (`remake/game/viewer/mission_viewer.gd`) place and view a
mission exactly as the original game does. That means the right heading sign and zero
direction for objects and for the camera, and the right left/right handedness for world and
models. Done when a viewer render from the mission 1-1 player start matches a screenshot of
the original at the same spot, and a second landmark confirms it.

## Background
- Every later remake item builds on this convention: R5 (sandbox), R3 (movement), R2
  (telemetry comparison), R6/R7 (aiming, AI). A mirrored world or a 180-degree-off forward
  axis would quietly corrupt all of them.
- Symptom: at mission 1-1 the viewer's start camera faces a canyon wall at close range. The
  last session flagged that "heading direction or left/right handedness is probably flipped".
- `docs/analysis.md` ("Remake-relevant") still lists **handedness** as undecoded ("needs a
  mirrored-text check").

## What is already known

### Data path (facts)
- Layouts come from `tools/export_gamedata.py` and are written to
  `remake/game/_import/data/layouts.json` (gitignored). Each row is
  `[unit_row, runtime_id, x, z, y, heading, flag]`, stored by the exporter as keys
  `x, z, y, heading`. See `docs/analysis.md` "Missions, units and layouts".
- Mission 1-1 is main script 8744 with layout array 8743. Layout row 1 is the player (Union
  infantry, on foot). `script_8737` sets `G973` (the player object) to the runtime id of row 1.
- Scale: game units / 100 = model units (one ground tile = 600 = 6 model units). Headings are
  in hundredths of a degree.
- Models: `tools/export_models.py` copies RenderWare coordinates **unchanged** into glTF. It
  does no axis flip and no winding change. RW row-vector matrices map 1:1 onto glTF
  column-major (`docs/analysis.md` "Model stream"). The Godot glTF loader does not rotate the
  scene either, so model space in Godot equals raw RW model space.

### What the viewer does now (`mission_viewer.gd`, `_load_mission` / `_goto_start`)
- `pos = Vector3(e.x, e.y, e.z) * 0.01`: game x maps to Godot X, game z to Godot Z, and the
  "y" column becomes height.
- `node.rotation_degrees.y = heading / 100`, with no sign change and no offset.
- Camera: `_yaw = start heading`, `_pitch = -5`, eye height 1.2 model units. A Godot camera
  at yaw 0 looks down **-Z**.
- FOV: Godot's default of 75 degrees vertical. The project viewport is 1280x720, while the
  original is 640x480 with a cockpit HUD.
- The player start is the first layout entry (`first` flag), which is row 1.
- Shot mode: `godot --path remake/game res://viewer/mission_viewer.tscn -- --shots <outdir> 1-1[,1-2] [--top]`
  renders from the player start (`_load_mission` calls `_goto_start`). The `--from-start`
  flag in the header comment **is not parsed**: it is a no-op, because start is already the
  default.
- Godot executable (installed with winget):
  `~/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe`.
  Earlier runs used `cd remake/game && "$G" --path . -- --shots "$(cygpath -m $TMP/gx/shots)" ...`.
- The model viewer's X key (and `mirror=1` in `--shots`) sets `model.scale.z = -1`. It is a
  per-model handedness check; the mission viewer has no equivalent yet.

### Evidence from the scripts (facts unless marked; listing from `tools/script7l.py`)
- **Spawn chain:** `script_2523` (layout spawner) calls
  `script_2039(class, template, x=col2, z=col3, heading=col5, y=col4, category)`, which calls
  `script_2040`/`2041`: `AddObject(obj, 0, x, h, z)`, then `ObjectYaw(obj, heading)`, then
  `UpdatePosOrient(obj, 1)`.
  So the heading goes straight into the RENDER.R32 native `ObjectYaw`, and `AddObject`'s
  argument order is (x, height, z).
- **Column 4 is not a height.** In 2040/2041: `h = 0; if (col4 == 1) h = G1846`. It is a flag
  that selects a raised level (G1846). The viewer's `e.y * 0.01` is harmless (0 or 0.01),
  but the exporter's name "y" is misleading. In 1-1 every row has 0.
- **Rotation sense, from `script_2524`.** For category 252 (corner-pivoted 1200x1200
  pieces), the spawner first runs `script_2524(&x, &z, heading)`:
  - 0 → (x-600, z-600)
  - 9000 → (x-600, z+600)
  - 18000 → (x+600, z+600)
  - -9000 → (x+600, z-600)

  The exported category-252 models (e.g. `modl_04184`) span local [0,12] x [0,12] in X/Z, so
  the origin is at a corner. The table therefore equals `origin = centre - R(h)*(600,600)`,
  where R(+9000) maps raw +x → -z and +z → +x. That is exactly Godot's
  `rotation_degrees.y = +90` on unmirrored coordinates.
  **Conclusion (high confidence):** in raw game coordinates the viewer's object heading sign
  is already right. If the world is ever mirrored (z → -z), the heading must be negated too.
  This holds only if the purpose of 2524 is to centre the piece on (x, z); check it with a
  252 piece in a mission that uses them (layouts 8796, 8834, 8894, ...).
- **Object forward is +Z (strong hypothesis).** The chase camera is `AttachCamera(obj, 0, 0,
  10, -20)` (`script_2170`), and the zoom-out views use `AttachCamera(G973, 0, 0,
  h + 2k, -(12k))`. Both put the camera behind the object at **negative local z**. The
  cockpit camera is `AttachCamera(G973, 0, 0, 44, 0)` (`script_2191`), or
  `AttachCamera(G973, GetProperty(G973, 10), 0, L1, 0)` (`script_2171`).
- **Camera at mission start:** `script_2528` runs `SetCamera(x_row1, 0, z_row1, 0, 0, 100)`.
  The 4th and 5th arguments are probably yaw and pitch, and 100 may be the zoom/FOV
  (unverified). After that, the camera is attached to the player, so the view follows the
  player's `ObjectYaw`. `SetCameraYaw(G1819)` with `G1819 = 0` is a look offset.
- Clipping: `SetCameraClipping(10, 3000|5000|7000)` (`script_2529`, by detail setting
  `G2117`). Near = 0.1 model units.
- `ViewportCrop(l, t, r, b)` shrinks the 3D view for the HUD in some modes. Measure the 3D
  region in the screenshot before matching FOV.

### Why the start view hits a wall (inference)
- The 1-1 player sits at x=-4950, z=75 with heading 18000. The ground bounds
  (`script_2515(10200, -9150, 3000, -10200)`, read as x∈[-9150, 10200], z∈[-10200, 3000])
  put the player near the +z/-x edge, while the enemies and HAWCs lie at +x and -z.
- If forward is +Z at heading 0, heading 180 faces **-Z, into the map**. Godot's camera at
  yaw 180 faces **+Z**, toward the edge, where rocks sit about 5 units ahead. So the likely
  fix is camera yaw = heading/100 + 180. Objects keep their rotation, since models also face
  +Z.
- Handedness is still open. If RW2 is left-handed relative to the raw numbers, the whole
  viewer image is a mirror of the original. A mirror is self-consistent, so only a visual
  comparison shows it.

### RenderWare 2.0 conventions (unverified)
- This could not be confirmed from docs. RW3 is right-handed with the camera looking down
  **+Z** (its "right" vector points screen-left). Assume RW2 is the same until the screenshot
  says otherwise. If so, raw coordinates in Godot (also right-handed) are not mirrored.
- To settle it from code: decompile `ObjectYaw`, `SetCamera`, and `AttachCamera` in
  RENDER.R32 (natives are exports, so look them up by name). Also look at how it builds the
  RW camera matrix and `RwSetCameraViewwindow` (FOV = 2*atan(viewwindow)).

## Plan
1. **Reference shot (windowed, allowed without asking).** Use
   `tools/dev/drive.ps1 -Dir test-install\G-Nome -Out $env:TEMP\r1 -Steps @('wait:4','key:SPACE','click:162,455','click:40,164','click:598,164','wait:3','key:SPACE','click:598,164','wait:8','shot:start','hold:LEFT:400','shot:left','hold:RIGHT:800','shot:right')`.
   Don't move forward before `shot:start`. The left/right shots show which way the
   landmarks rotate.
2. **Viewer shot.** Add a matching mode to `mission_viewer.gd`: viewport 640x480, the
   cockpit eye height (44 game units → 0.44, or the player's prop-56 value / 20), and a
   vertical FOV fitted to the 3D region (start near 60 degrees and refine). Add flags such as
   `--yaw-offset <deg>`, `--heading-sign <±1>`, and `--mirror-z` (scale the world root
   z=-1). Render 1-1 with each combination: offset {0, 180} x sign {+1, -1} x mirror
   {off, on}. Make sign = -1 the default when mirror is on.
3. **Compare** with `Read` on the PNGs: the nearest rock formations and the backdrop
   mountains. Pick the combination that matches. Expected: offset 180, sign +1, no mirror.
4. **Confirm with a second landmark**, e.g. drive forward or turn 90 degrees in the
   original, or use another mission whose start view is distinctive (1-2 "Drawbridge"). Also
   check one category-252 piece in a mission that uses it, and an asymmetric model with text
   or markings for handedness.
5. **Bake it in.** Fix the camera yaw (and any mirror) in the viewer. If a mirror is needed,
   apply it once at import (exporter or a root transform) so R5 and later items inherit it.
   Rename the exporter's "y" key to `level_flag`, or document it. Remove or implement
   `--from-start`.
6. **Document** the convention in `docs/analysis.md` and the controls in
   `remake/README.md`.

## Verification
- A side-by-side of the original `start.png` and the viewer render shows the same nearest
  rock layout and the same horizon features, on the same sides.
- Turning left in the original and decreasing yaw in the viewer move landmarks the same way.
- A second landmark or mission also matches, and a 252 piece lines up with its neighbours.

## Open questions / risks
- Does the HUD/cockpit hide too much of the 3D view at the 1-1 start? Fall back to the
  external view (`AttachCamera` with negative z) if a key toggles it.
- The meaning of `SetCamera`'s 6th argument (100) and the real FOV both need RENDER.R32.
- Godot's PanoramaSky maps longitude differently from RW's `SetCameraBackdrop` strip. The
  backdrop may need its own offset or flip, independent of the world. Don't use it as the
  only cue.
- The player may be re-oriented after spawn by mission-start scripts (8737, 2530).
  Telemetry (R2) would settle this.

## Dependencies
- None blocking. It helps R2 (telemetry gives exact heading and position to compare) and
  feeds R3, R5, R6, R7, and R9.

## Notes to fold into analysis.md
- `script_2040`/`2041`: `AddObject(obj, 0, x, level, z)` + `ObjectYaw(obj, heading)`.
  Layout column 4 is a flag (1 → height G1846), not a y coordinate.
- `script_2524`: corner-pivot offsets for category 252. The models span local [0,1200]^2.
  This implies the game's yaw rotates +x toward -z for positive headings, the same as
  Godot's +Y rotation in raw coordinates.
- Camera natives: `AttachCamera(obj, part, x, y, z)` (chase cam at z=-20 → object forward
  +Z), `SetCamera(x, y, z, ?, ?, 100)` at mission start (`script_2528`),
  `SetCameraClipping(10, far)`.
- Mission bounds `script_2515(a, b, c, d)` → G1833..G1836. The ground loops run
  x from G1834 to G1833 and z from G1836 to G1835.
