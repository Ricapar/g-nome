# G-Nome remake (Godot 4)

A modern remake of 7th Level's *G-Nome* (1997). Gameplay, missions, story, vehicles and
menus follow the original. The visuals are new: the goal is a current-generation
MechWarrior-style look that gives no hint the game started in the mid-90s.

Status: Phase 0 in progress. Nothing playable yet.

## Getting started
1. Create the venv: `python -m venv .venv` and
   `.venv\Scripts\pip install -r tools/requirements.txt` (repo root).
2. Export the original assets and data from your disc (gitignored; never commit them):
   `.venv\Scripts\python -I tools/export_models.py <disc>\G-NOME\G-NOME.BIN remake/game/_import`
   and `.venv\Scripts\python -I tools/export_gamedata.py <disc>\G-NOME\G-NOME.BIN remake/game/_import`.
   Sounds (all 592 waves; the menu uses the originals when present):
   `.venv\Scripts\python -I tools/export_audio.py <disc>\G-NOME\G-NOME.BIN remake/game/_import`.
   Script listing: `.venv\Scripts\python -I tools/script7l.py <disc>\G-NOME\G-NOME.BIN > scripts.txt`.
3. Open `remake/game` in Godot 4.7 and run it. The model viewer lists every MODL/MPRT.
   Arrow keys select, drag orbits, the wheel zooms, C toggles culling, X mirrors Z.
   Batch screenshots: `godot --path remake/game -- --shots <outdir> modl_02700,modl_02698`.

## Decisions (2026-10-12)

| Topic | Decision |
|---|---|
| Fidelity | **Gameplay is faithful, visuals are modern.** Mission layouts, objectives, scripting, vehicle stats, weapons, handling, AI, controls and menu flow match the original. Rendering, lighting, VFX, models, textures and HUD are new. |
| Assets | New art will be made over time. Until then, the original assets imported from the user's disc serve as **placeholders and scale references** (blockouts). |
| Engine | Godot 4 (MIT). |
| Repo | Lives in this repo under `remake/`, on branch `remake`. The RE notes and tools in the repo root stay the source of truth for formats. |
| UI (menus, HUD, briefing, Lab, options) | **Built from scratch, Godot-native**, and much sharper than the original: a project `Theme` and components laid out with containers and anchors, resolution-independent up to 4K and ultrawide. It mixes **vector elements** (StyleBoxes, SVG, `_draw`/shaders, MSDF fonts) with **high-res textures**. The original UI is reference only for flow, content and behaviour; its bitmaps are never used as UI placeholders. See backlog R10-R17. |

### What this means in practice
- **Data and art are kept apart.** Each vehicle, weapon or prop is a data definition
  (stats, hardpoints, collision size, behaviour) that points to a *visual slot*. A slot holds
  either the imported original model or new art, so art can be swapped without touching
  gameplay.
- **The original sets the scale.** Original models give each vehicle's real dimensions,
  hardpoint positions and silhouette, and `LABTEXT.DAT` gives height and weight. New art is
  modelled to match these, so gameplay feel (collision, line of sight, hit boxes) doesn't drift.
- **Gameplay numbers come from the original code.** Speeds, turn rates, weapon damage and
  ranges, and AI parameters are recovered from RENDER.R32 and the scripts, not tuned by feel.
  A telemetry hook in the original game provides reference runs to compare against.
- **Copyright:** original game data is never committed. The importer reads it from the
  user's disc or ISO at dev or first-run time. New art made for the remake can be committed.
  Mission data derived from the original scripts counts as game data until we decide
  otherwise.

## Roadmap

### Phase 0: Extraction and understanding (in the repo-root `tools/`)
1. Exporters for the 7L archive:
   - [x] models (MODL/MPRT) → glTF with part hierarchy, tags and materials (801 models)
   - [x] textures → PNG (923); RLE and LZW bitmap codecs; palettes located
   - [x] OB3D/OPRT object templates, type-11 arrays, strings, missions/objectives, world
         table → JSON (`tools/export_gamedata.py`)
   - [ ] FRME animations → glTF animations
   - [ ] sprites/UI → PNG with the correct palette; waves → WAV; SMK → modern video
2. [x] Model viewer and **mission viewer** (`remake/game/viewer/mission_viewer.tscn`,
   orientation verified against the original in R1; PgUp/PgDn mission, WASD/QE + right-drag
   fly, Home back to the player start's cockpit view):
   places a mission's layout with the original models, world ground, backdrop sky and fog.
3. [x] Terrain: mission 1-1 is a flat tiled plane plus a backdrop panorama plus placed
   objects (no heightfield). Other missions get checked once scripts can be read.
   Implication: the remake's terrain has to be authored new (a modern heightmap or
   landscape). The original only fixes the playable area, object layout and the flat
   collision plane.
4. [x] **Script VM:** disassembler for all 2342 scripts (`tools/script7l.py`).
   [x] Missions → main scripts → layout arrays; unit catalogue joined with the codex.
   [ ] Name the remaining property indices; decode weapon table 1281 and the AI scripts.
5. RENDER.R32 natives: movement and physics, AI behaviours, weapons and projectiles,
   damage, the eject/commandeer mechanic, camera and radar.
6. A telemetry hook in `ddraw.dll` (or a separate injected DLL) that logs entity state each
   tick, for comparison testing.

### Phase 1: Godot foundation (`remake/`)
- Project skeleton; importer that turns extracted data into Godot resources.
- Vehicle controller (bipedal HAWC, treaded, hover) driven by the original parameters.
- Placeholder rendering with the original models in a modern pipeline (PBR, lighting,
  post-processing) as a first look.

### Phase 2: Vertical slice, mission 1-1
Briefing → launch → cockpit → objectives → eject/commandeer → debrief. Compare it side by
side with the original (`tools/dev/drive.ps1`) and against telemetry.

### Phase 3: Breadth
All missions, the menus and the Lab (vehicle database, trivia), FMV, save/load, audio and
music, gamepad support, then multiplayer.

### Phase 4 (runs alongside from Phase 2): New art
Replace the vehicles first, since they're seen the most, then terrain, props, VFX, HUD and UI.

## Layout (planned)
```
remake/
  README.md        this plan
  game/            Godot project (project.godot lives here)
  import/          scripts that convert extracted original data to Godot resources
  art/             new source art (blend files etc.), committed
```
Extracted original data goes into `remake/game/_import/` (gitignored).
