# R0: Fix exporter data bugs and fold spec findings into analysis.md

Status: todo

## Goal
Fix the data errors that the R1–R9 spec research found in the exporters and in
`docs/analysis.md`, so later items build on correct data. Then fold each spec's
"Notes to fold into analysis.md" section into `docs/analysis.md`.

## Background
The R1–R9 specs were written in parallel, by agents that read the scripts and exported data
but did no work in REA/Ghidra and launched no game. Several of them found the same bugs
independently. The bugs listed below were found by at least two agents or have concrete evidence. Everything is still
**unverified until checked here**. Don't copy a claim into analysis.md without checking it.

## Exporter bugs (`tools/export_gamedata.py`)
1. **Catalogue categories 161 and 181/182 look swapped.** Found independently by R3, from
   the stats, and R6, from the loadouts.
   - Rows labelled 161 "Hovercraft" carry the codex armoured-support stats and loadouts and
     use `?tl1*` (treaded) textures. Rows labelled 181/182 "Armored Support" carry the
     hovercraft ones and use `?hl2*` textures.
   - Example: unit row 3 (scripts 2762 → 2775) sets 20/1900 and ARC-M + 3cREAP, which is the
     Rapier.
   - With the labels swapped, kph = prop35 × 0.45 holds for all 8 rows.
   - Check by opening the models in the model viewer (tracks vs. hover skirt). Then fix
     `CATEGORY` / `CODEX_MATCH`, re-export `units.json`, and correct the category list in
     analysis.md. Details: R3 "Contradiction", R6 notes.
2. **Mission bounds are truncated by a regex.** `missions.json` has `"10200, -(9150"`. Real
   1-1 bounds: xmax 10200, xmin −9150, zmax 3000, zmin −10200 (`script_2515` → G1833..G1836).
   See R5 and R1.
3. ~~**Layout column 4 is mislabelled `y`.**~~ Done in R1: exported as `level_flag`.
4. `tools/bitmap7l.py` docstring says LZW is not implemented. It is (`decompress_chunks`), and
   72 sprites use it. See R8.
5. ~~Minor: `--from-start` flag never read.~~ Done in R1: removed from the header comment.

## analysis.md corrections (found by the specs; check each one)
- "Template props[1..7] = same model in 7 team colours" is wrong. Props 1/4/7 = LOD0/1/2, and
  props 2/3/5/6 = paint variants (R4).
- "AI/update scripts (props 72/75/93/130)" is wrong. They are cockpit/HUD resources: type-20
  sprite, ViewportCrop script, gauge array, LinkModel script (R3 and R7, independently). The AI
  is template update script 1723 plus the task list (R7).
- Prop 92 = current LOD band (0–2), not difficulty (R7). Difficulty is global `G2114`.
- The object list `+0x40264/+0x40268` is a RENDER.R32 module-relative global
  (`DAT_10040264`), not an object field offset (R2).
- Type 11 = int32 arrays, not "sound/event records". There is no type 22. The palettes equal
  to key 6 are 2510/2511, not the first type-17 palette (R8).
- Palette changes are per **world** for scenery (entries 186..215) and per **mission** only
  for 216..245, mostly sky (R9). Fix any "per mission" wording.
- Props 97/94 vs 95/98 may have armour and shield swapped (R6). This is an open question;
  record it as such until R2 telemetry settles it.

## New facts to fold in
Each spec R1–R9 ends with a "Notes to fold into analysis.md" section. Merge them into the
matching analysis.md sections ("Script VM", "Data tables", "Missions, units and layouts",
"Remake-relevant", the archive format). Main items:
- Scale: 1 game unit ≈ 0.125 m. prop35 is in units/s, so kph = × 0.45 (R5, R3).
- Player = G973. Board/eject scripts. Key presets in arrays 2548–2552 (R5, R2).
- FRME format (R4). Weapon table column map (R6). AI task system (R7).
- Palette ranges and world texture prefixes (R9). Wave header and movie table (R8).
- RENDER.R32 export addresses of movement, animation, weapon and AI natives (R3, R4, R6, R7).
- Model textures taller than 128 px are stacks of 128x128 frames (found during R11): the
  menu's ModelStage samples frame 0 via `viewer/rw_model.gd`. The model and mission viewers
  still use the raw glTF materials (green legs on the Prowler); switch them over, and find
  how RENDER.R32 picks the frame (team colour?).

## Plan
1. Check bug 1 in the model viewer (`godot --path remake/game -- --shots <dir> <ids>`), then
   fix it and re-export.
2. Fix bugs 2–4. Re-run `tools/export_gamedata.py` into `remake/game/_import`. Check that the
   mission viewer still loads 1-1 and that the bounds now parse.
3. Apply the analysis.md corrections, then fold in the notes from each spec. Mark
   hypotheses as hypotheses.
4. If a fix changes something a spec relies on, update that spec. For example, R3/R5/R6 refer
   to the swap as unfixed.

## Verification
- `units.json`: treaded vehicles have the tread models and the codex treaded stats. The 0.45
  speed factor holds for 19/20 vehicles; the Venom is a known outlier.
- `missions.json` bounds are four integers for every mission.
- analysis.md has no statement that contradicts the specs. `git diff` contains only the
  intended changes.

## Dependencies
- Does not block R1 (R1 doesn't use categories or bounds). Do it after R1 and before R3, R5
  and R6.
