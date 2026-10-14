# R0: Fix exporter data bugs and fold spec findings into analysis.md

Status: **done** (2026-10-14)

## Goal
Fix the data errors that the R1–R9 spec research found in the exporters and in
`docs/analysis.md`, so later items build on correct data. Then fold each spec's
"Notes to fold into analysis.md" section into `docs/analysis.md`.

## Background
The R1–R9 specs were written in parallel, by agents that read the scripts and exported data
but did no work in REA/Ghidra and launched no game. Several of them found the same bugs
independently. Everything below was **checked against the data** on 2026-10-14 before it
went into analysis.md; the method is noted per item so it can be repeated.

## Results

### Exporter bugs (`tools/export_gamedata.py`) — all fixed, data re-exported
1. **Catalogue categories 161 and 181/182 were swapped. Confirmed, fixed.**
   161 = treaded armoured support, 181/182 = hovercraft. Four independent checks:
   - Models: row 3 (category 182) template 2761 → model 2745 renders as a hovercraft (skirt,
     no tracks) with `hhl2*` textures; row 4 (161) → 2783 is a tracked tank with `htl1*`
     textures (`ModelStage` renders, `t2.gd`).
   - Stats: row 3's init 2762 → 2775 sets 20/1900 and weapons (29 ARC-M, 2000) + (6 3cREAP,
     220) = the codex Rapier (hovercraft). Row 4's 2792 → 2805 sets 30/1000, (5 3cROCK, 30) +
     (6, 800) x2 = the Titan (treaded). Same pattern for Darken (8/9), Merc (15/16), Scorp
     (21/22).
   - Speed: with the swap, LABTEXT kph = `script_2066` fwd throttle x 0.45 for all eight rows
     (and for 19 of 20 vehicles overall; the Venom is the outlier, the Lion matches in its
     campaign branch).
   - Fix: `CATEGORY`/`CODEX_MATCH`; `units.json` now joins Rapier/Vulture/Razor/Wasp to the
     181/182 rows and Titan/Boulder/Legionnaire/Stinger to the 161 rows.
2. **Mission bounds truncated.** The listing prints negatives as `-(n)`, so `[^)]*` stopped
   early. Now parsed into four ints; 1-1 = `[10200, -9150, 3000, -10200]`, all 22 missions
   have four values.
3. ~~Layout column 4 mislabelled `y`.~~ Done in R1 (`level_flag`).
4. `tools/bitmap7l.py` docstring said LZW was not implemented; it is (`decompress_chunks`),
   and 72 of the 1240 sprites use that path. Docstring fixed.
5. ~~`--from-start` flag.~~ Done in R1.

### analysis.md corrections — all checked, applied
- Template props[1..7]: props 1/4/7 = LOD0/1/2 → object props 79/80/81 (`script_2146`);
  props 2/3/5/6 = the same LODs in the `w`/`s` texture sets, put on list `G1849`. Triangle
  counts confirm the LODs (Prowler 330/318/318, 169/179/179, 100).
- Props 72/75/93/130 are cockpit resources (2620 type-20 sprite, 2629 = `ViewportCrop`,
  2628 array, 2630 = `LinkModel` script), not AI. Index types and disassembly checked.
- Prop 92 = current LOD band (scripts 2147/2148/2149 set it 0/1/2 with `setLOD`).
  Difficulty is `G2114`, a three-way option (6936-6938), used by 8737 and 1677.
- Object list `+0x40264/+0x40268` = RENDER.R32 globals `DAT_10040264/68` (decompiled
  `FUN_10006446`; also gave the position floats at `+0xc/+0x10/+0x14`, `+0x58` radius,
  `+0x8c` camera distance²).
- Type 11 = int32 arrays (709), no type 22; 2510/2511 (not the first type-17 palette) equal
  key 6.
- Palettes: 186..215 per world, 216..245 per mission (computed over all 14 palettes).
- OB3D range records: every one of the 1136 in the data has restype 19 (script); the "restype
  7 = model" wording was dropped. No template uses record kinds 1 or 8.
- Props 97/94 vs 95/98 (armour/shields): still open, recorded as such.

### Folded into analysis.md
New section "Gameplay systems" with the verified facts from R2–R9 (player/boarding/camera,
bounds, movement props and tick, codex factor, controls, difficulty, FRME format, weapon table
and id→name list, mounts/damage, AI task system, scenery spawner), plus scale (0.125 m/unit,
marked as a hypothesis), the unit-catalogue and LOD facts, and the runtime object struct.
Spot checks beyond the R0 list: FRME sizes (331/332, anomaly 4733), 1-1 layout rows 1 and 7,
scenery variant = world + 5, `[6, 30, 1723]` on the 42 vehicle templates, weapon id→name
against all 24 loadouts.

### Viewer
`model_viewer.gd` and `mission_viewer.gd` now call `RwModel.apply_frames` (frame 0 of the
stacked textures), as the menu's `ModelStage` already did. How RENDER picks the damage /
hologram frames is still open (R16/R17).

## Still open (carried into the other specs)
- 0.125 m/unit and "prop35 in units/s": confirm with R2 telemetry.
- What the `a`/`w`/`s` texture sets of the LOD models are for (list `G1849`).
- `G2114` = difficulty is inferred from its use, not from a label.
- `G982` = multiplayer flag (set by 2565/5941, cleared by 6277/7275): inferred.

## Dependencies
- Done after R1. R3, R5 and R6 now start from correct categories and bounds.
