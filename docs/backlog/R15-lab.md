# R15: The Lab (vehicle database and trivia)

Status: **todo**

## Goal
Rebuild the original's LAB section: the vehicle database (stats and description for each
vehicle, with a rotating 3D model), and the trivia. Same content and structure as the
original, presented with the R11 kit and a modern 3D turntable.

Done when every Lab page of the original has a remake counterpart with the same entries and
text, and each vehicle shows its model (imported original until new art exists) on a
lit turntable you can rotate.

## What is already known (leads; verify)
- LAB = array **8622**: four entries (action ids 12-15, click scripts 8372-8375), each
  opening the same right column **8623** (entries 8376-8379, action ids 16-19).
  8376 = `script_8354(0)` + `script_8093(0)`. Four categories × four views is a guess.
- Data: `LABTEXT.DAT` (vehicle database text: height, weight, …) and `TRIVIA.DAT/.IDX`. The
  unit catalogue (array 5843) is already joined with the codex/LABTEXT by
  `tools/export_gamedata.py` (`units.json`). Codex stats come from `script_2056`/`2057`.
- `RenderToBitmap(G2402, G2403, G2416, 0, G2404, G2405, G2406, G2399, G2401)` in script
  8104 (and a similar call in 7280) renders a 3D object into a bitmap: probably the Lab's
  rotating model. The globals give object, size and rotation.
- 640x480 Lab frames exist among the full-screen bitmaps (e.g. 1181, "Lab-style frame"; R8).

## Plan
1. Disassemble 8372-8379, 8093 and 8104: list the Lab pages, how entries are chosen
   (next/prev, list?), what is shown (text fields, stats, model, sounds/voice).
2. Decode `TRIVIA.DAT/.IDX` and check `LABTEXT.DAT` parsing covers every field shown. Export
   `lab.json` (vehicles with stats/text/model ids; trivia entries) via `tools/export_gamedata.py`.
3. Reference shots of each Lab page (windowed drive run).
4. Godot: `lab.tscn` with a list/browser, a stats panel (vector bars/graphs from R11), text,
   and a `SubViewport` turntable (studio lighting, orbit with mouse/stick, zoom). Trivia page.
5. Keep text as `tr()` keys; text content stays game data (never committed; loaded from the import).

## Verification
- Entry count and text match the original for every page (spot check 5 vehicles and 5 trivia entries word for word).
- Turntable shows the right model per vehicle, in team colour 0, at the right scale (compare with LABTEXT height).

## Open questions
- What the four LAB entries and four sub-entries are exactly.
- Does the Lab play voice-overs or animations (FRME, R4)?

## Dependencies
- R11 (kit), R12 (entry). Better with R4 (animations) and R8 (sounds), not required.
