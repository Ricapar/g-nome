# R16: Decode the original cockpit HUD (elements, data, behaviour)

Status: **todo**

## Goal
A full description of what the original HUD shows for every vehicle and on foot: each element,
where it sits, what game value drives it, how it animates, and how the camera views and
cockpit crops change. Output `hud.json` (from `tools/export_gamedata.py` or a new
`tools/export_ui.py`) and a HUD section in `docs/analysis.md`. This is the functional spec for the
new HUD (R17); the original bitmaps are reference only.

Done when every element type used by the 39 HUD layout arrays is named, its data source
(object property or global) and drawing behaviour are known, and the result is checked
against screenshots of at least three vehicles plus the on-foot view.

## Background
- The 1-1 start shot (R1, on foot) shows: weapon list top centre (`PRIF44` with a
  charge bar, `GASHR` with ammo pips and count 2), a compass tape bottom left (letters
  S/W/N/E and a marker), a green crosshair, a numeric readout `4326` under the visor, and the
  helmet frame. Vehicles have their own cockpit frames (e.g. bitmap 2621).
- Decision: the new HUD is designed from scratch (R11/R17); the original fixes *what*
  information is shown and how it behaves, not how it looks.

## What is already known (facts from the script listing unless marked)
- **Per-vehicle HUD layout = object property 93**, set by each unit's init script
  (e.g. `script_2631`, Union Prowler: `SetProperty(L0, 93, 2628)`). 39 layout arrays exist
  (e.g. 2628, 2685, 2734, ..., 3645, 4548, 4649, 4717; shared 1183 and 1187).
- Layout rows are `[element type, x, y, sprite/resource, a, b, c, d]` in 640x480 screen
  coordinates. Prowler (2628):
  `[2,322,173] [3,390,210] [4,320,248] [5,612,373,813,2,0,0,18] [6,487,349,851,2,0,0,18]
  [7,27,373,832,2,0,0,18] [11,540,369,0,2] [12,93,379,0,2] [9,320,411] [21,320,411,2624]
  [25,0,0,2627] [22,265,24,2622,4] [26,322,24]`.
  1183 = `[11,127,389,0,2] [26,372,423]`, 1187 = `[11,569,374,0,2] [26,214,379]`.
- **`script_1217`** walks the layout every update and calls **`script_1219(type, layout,
  row)`**, a switch from element type to draw script (G973 = player object, G1811 = current target):

| type | script | notes (guesses in italics) |
|---|---|---|
| 1 | 611 | |
| 2 | 599 | gauges with sprites 584-596 (`script_600`) |
| 3 | 717 | 100-frame bar sprite 614/715 (cels 615-714, 9x99): *a vertical bar gauge* |
| 4 | 575 | |
| 5 | 873 (self) | |
| 6 | 872 | |
| 7 | 873 (target) | *same readout as 5, for the target* |
| 9 | 985 | **radar**: `RadarClear`, `RadarDraw(obj, sprite, G1816, range, 101, 113, 77, target, 10, …)`, `MakeSpriteDraw` |
| 11 | 981 (self, 0) | *status: health/armour/shields?* |
| 12 | 981 (target, 1) | same for the target |
| 17 | 938 | |
| 18 | 965 | |
| 19 | 911 (target) | |
| 22 | 1236 | at (265,24) with sprite 2622: *weapon list?* |
| 25 | 1638 | sprite 2627 at (0,0): *the cockpit frame?* |
| 26 | 885 | |
| 27 | 5066 | |
| 21, 24 | (default) | handled elsewhere; 21 = sprite 2624 at the radar's position |

  Element counts across all 39 layouts: 1:25, 2:33, 3:20, 4:33, 5:31, 6:29, 7:29, 9:29,
  11:33, 12:30, 21:29, 22:29, 24:2, 25:33, 26:38, 27:1.
- After the elements, `script_456` draws the **crosshair/target marker**: sprite 444,
  positioned with `XZToScreen(…, 56)`, frame chosen by lock state (G1244).
- **Cockpit table = array 2216** (4 x 13), indexed by object property 115 (0..3):
  `[sprite, sprite2, ?, ?, ?, ?, 3, 0, wave 306, crop l, t, r, b]`, e.g. row 0
  `[2200, 2202, 322, 34, 82, 126, 3, 0, 306, 152, 73, 152, 110]`. Used by `script_2219`
  (ride/enter view: attach camera at the vehicle's eye, play the wave, show the sprite, `ViewportCrop`).
- **`ViewportCrop(l, t, r, b)`** shrinks the 3D view to the cockpit glass; each vehicle sets
  its own (scripts 2629-3643, e.g. 2629 = `(0, 20, 0, 196)`). Units unknown (pixels from
  each edge?). Views 1182/1186/1190/1214/1229 use other crops (camera modes).
- Other HUD natives: `ScreenShake` (script 1709), `SetObjPerspective`, `RenderToBitmap`.
  Weapons: `script_1656(obj, weapon, ammo, hardpoint)` with weapon table 1281 (R6).

## Plan
1. Disassemble every draw script in the table above (and 456, 1217, 2219, the
   view-mode scripts 1182-1229). For each element: name, inputs (properties/globals),
   sprites used, update rule (every frame, on change), and any sound.
2. RE `RadarDraw` and `XZToScreen` in RENDER.R32 (REA): radar range, shape, blip types
   and colours, rotation (heading-up vs north-up); the target box projection.
3. Map element types to a readable schema and export `hud.json`: per vehicle (unit row →
   layout array), the elements with position and parameters; the cockpit table and crops.
4. Camera views: list the view modes (cockpit, chase, zoom-out levels, external), the keys
   that switch them and how the HUD changes in each.
5. Reference shots: windowed drive runs in 1-1 on foot, then commandeer a HAWC (R5 path),
   plus two other vehicle classes from later missions or saves; label every element on the shots.
6. Write the HUD section in analysis.md (element catalogue with screenshots described in words).

## Verification
- For three vehicles plus on foot, every visible HUD item in the shots is accounted for by a
  layout row, and every row is visible (or explained).
- Live check (optional, with R2 telemetry or `tools/dev/peek`): change a value (take damage,
  fire, switch weapon) and see the predicted element change.

## Open questions
- `ViewportCrop` units and the role of the 4 cockpit-table rows vs per-vehicle crops.
- Columns a-d of the layout rows (2 and 18 appear often: maybe a frame count/colour/style).
- What the `4326` readout is (score? credits? range?).

## Dependencies
- None blocking for the static part. Reference shots of vehicles need R5-style navigation in
  the original (commandeer) or saves. R6 (weapons) and R2 (telemetry) help with data sources.
- Feeds R17.

## Notes to fold into analysis.md
- Property 93 = HUD layout array; property 115 = cockpit type (array 2216); G973 = player,
  G1811 = target; scripts 1217/1219/456/2219; element type table above.
