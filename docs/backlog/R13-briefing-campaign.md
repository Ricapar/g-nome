# R13: Briefing, debriefing, campaign progression and save/load

Status: **todo**

## Goal
Decode and rebuild the "between missions" layer: campaign state, mission briefing (with its
animation and objectives), LAUNCH into a mission, the debriefing and results, mission
unlock/progression, training and single-mission selection, and save/load slots. The new
screens use the R11 kit; the rules and content match the original.

Done when a remake run goes New → Campaign → briefing 1-1 → launch (sandbox) → (forced)
win/lose → debrief → briefing 1-2, and a save from that point loads back into the same state.

## Background
- Original path (CLAUDE.md): GAME → NEW → CAMPAIGN → briefing animation (SPACE skips) →
  LAUNCH (598,164) → cockpit. The briefing uses the menu's centre frame and the right column.
- Mission data already exported: `missions.json` (code, name, objectives, world row, layout
  array, main script), `mission_table.json` (array 6984), strings.

## What is already known (leads from the script listing; verify)
- **CAMPAIGN click = `script_8363`**: confirms via `script_8354(0)`, clears every per-mission
  array listed in array 6984 column 1 (34 rows), sets **G2141 = 1** (current mission
  index 1..22) and G2119 = 1, then runs `script_7265`.
- `script_7265`: `s75 7370` (switch screen/scene?), stops wave G2149, sets the close script
  `G2056 = 7270`, runs `script_7256` and `script_7258` (briefing setup, presumably).
- **GAME click = `script_8344`**: if 1 <= G2141 <= 22 (a campaign in progress) it runs
  `script_7269` and `script_8358`: probably "resume at the current briefing".
- Mission table 6984: rows 1..22 campaign, 23..32 training/multiplayer maps
  (analysis.md "Missions, units and layouts").
- File I/O: `FileOpen(8, …)` in scripts 6291/6292 and `FileOpen(5, …)` in 2556/2557 (the
  first argument is probably a string id = filename). Save games are `SGNOME*.SAV` in the
  install folder. `FileGetL/FilePutL/FileRead` are used to read/write them.
- Objectives are text per mission in `missions.json`; mission-start script `script_8737`
  (1-1) sets the objectives at runtime. Win/lose detection is in the mission scripts.
- `RenderToBitmap` (scripts 7280, 8104) draws a 3D object into a bitmap: possibly the
  briefing's rotating vehicle or map, or the Lab (R15).

## Plan
1. **Briefing screen**: disassemble 7256/7258/7265/7270 and children. Record what the
   briefing shows (map? text? FMV? voice-over waves? rotating vehicle?), its timeline
   (the "animation" SPACE skips), and the right-column buttons (LAUNCH, …).
2. **Campaign state**: list every global the campaign keeps (G2141 and the per-mission
   arrays from 6984 column 1), what a mission writes on success/failure, and the unlock
   rules (linear 1-1..4-6? branches? retries?).
3. **Debrief**: find the script that runs after a mission ends (win/lose), what it shows
   (stats, kills, medals?) and where it goes next.
4. **Save format**: decode `SGNOME*.SAV` from scripts 6291/6292 plus a few real save files
   (make saves in the windowed original at known points and diff them). Document it in analysis.md.
5. **Training and MISSION select**: what they list and how they start a mission.
6. **Godot**: `campaign_state.gd` (resource, serialisable), `save_system.gd` (slots in
   `user://saves/`, versioned JSON or binary, the remake's own format), `briefing.tscn`,
   `debrief.tscn`, `mission_select.tscn`, `load_save.tscn`. Optional later: import an
   original `.SAV` into the remake.
7. Hook LAUNCH to the mission scene (R5 sandbox for now) and add a debug "win/lose" key to test the loop.

## Verification
- Reference shots of the original's briefing, debrief and load/save screens (windowed
  drive runs) vs the remake: same content and buttons.
- Save in the original at three known points; the decoder reads the right mission and state from each.
- Remake loop test as in "Goal", including save/load round trip.

## Open questions
- Does the briefing use voice-over (type-12 waves) or FMV (NEWS/WILKINS SMK)?
- How many save slots, and what's in a save (mission index only, or squad/vehicle state)?
- Can a mission be failed and retried, and does the campaign branch?

## Available from R11 (2026-10-14)
- Save/load slots: `ListPicker` (select, then press again or accept to load).
  Overwrite/abort prompts: `UiRouter.confirm`. Loading: `UiRouter.cover("LOADING")`.
- Briefing pieces already in the main menu style frame: `TacticalMap`, `ModelStage`,
  objectives with yellow box bullets (`PaneFrame`). Usage guide: `remake/README.md`, "UI kit".

## Dependencies
- R10 (menu map) for the entry points, R11 (kit), R12 (shell). R5 for a real mission to
  launch. R8 for briefing audio/video.

## Notes to fold into analysis.md
- G2141 = current campaign mission (1..22); script 8363/8344/7265 roles once confirmed; save format.
