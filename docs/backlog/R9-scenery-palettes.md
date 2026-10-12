# R9: Per-world colours for scenery other than rocks in the mission viewer

Status: **todo**

## Goal
In the Godot mission viewer (`remake/game/viewer/mission_viewer.gd`), every placed object in
every campaign mission shows the colours the original shows: trees, river pieces, buildings,
ground tiles and rocks. It's done when viewer renders of missions from worlds 1, 2 and 3 match
windowed screenshots of the original, with no desert-palette colours on world-1..3 scenery.

## Background
- The original draws everything through **one global 8-bit screen palette** that is chosen per
  mission (array 2512, script 2514). A texture pixel with index i shows palette entry i of the
  current mission. So the "right" colour of any texture is its indices pushed through the
  mission's palette.
- The exporter bakes every texture to PNG with the world-0 (desert) palette 2487 and also writes
  `__w1..3` variants for the 104 textures that use the world-dependent entries. The glTF files
  always point at the world-0 PNG. The viewer swaps in world variants only for the ground plane
  and for rocks. All other world-dependent scenery in worlds 1-3 therefore shows desert colours.
- This matters for the blockout and scale-reference role of the original assets (see
  `remake/README.md`, "Decisions") and for side-by-side comparisons with the original in later
  items.

## What is already known

### Palettes (facts; checked this session from `ISO/G-NOME/G-NOME.BIN` with `res7l`)
- Type-17 palettes 2487, 2489, ..., 2507 (odd ids, 11 of them) are the mission palettes. Each
  is paired with the type-1 backdrop one id below it (2486, 2488, ...). 2509, 2510 and 2511 are
  also type 17. 2509 only appears in world-table row 14, which no campaign mission uses. 2510
  and 2511 aren't in the world table at all.
- Entries 10..185 are identical in all palettes (`docs/analysis.md`, "Missions, units and
  layouts").
- **New: entries 186..215 change per world**: they're identical for all palettes of one world.
  **Entries 216..245 change per mission** inside a world. Palettes of the same world differ in
  exactly those 30 entries, and palettes of different worlds differ in all 60.
- World groups: world 0 = 2487/2489/2491, world 1 = 2493/2495/2497, world 2 =
  2499/2501/2503, world 3 = 2505/2507 (+2509). Backdrops use mostly 216..245 (sky).
- So `tools/export_models.py` `WORLD_PALETTES = [2487, 2493, 2499, 2505]` (the first palette
  of each world) is **exact for any texture that uses only indices up to 215**.

### Textures (facts)
- `export_models.export_textures` writes `<name>.png` (palette 2487) and, when
  `max(px) >= 186` (`WORLD_RANGE`), `<name>__w1.png..__w3.png` into
  `remake/game/_import/textures/`. 104 of the 923 unique textures qualify.
- All 104 have a world-prefixed name: `d*` = world 0, `i*` = world 1, `g*` = world 2, `m*` =
  world 3. These match the viewer's `GROUND_PREFIX = ["dgrd1000", "igrd1000", "ggrd1000",
  "mgrd2000"]`. Families per world: `?grd*` ground tiles, `?tre*` trees, `?roc0100`,
  `?re1/2`, `?rt1/2`, `?rv1/2`, `?ry1/2` (river/edge pieces, hypothesis), `?cit*`, `?cot*`,
  `?cvh*` (buildings, hypothesis), `dmount__`, `dsrtrivr`, `mv01*`, `mv02*`, `gaus2011`,
  `gaus2012`.
- **No cross-world use:** in all 22 campaign layouts, every placed model that uses one of the
  104 textures uses only textures of its mission's world prefix. That covers scenery and
  structure templates, all `template_props` models. So for world 0 the default PNGs are already
  correct, and in world w the correct file is always `<name>__w<w>.png`.
- Only `gaus2011` and `gaus2012` use entries 216..245, so they would need per-mission palettes.
  Their only model is `modl_05925`. No OB3D/OPRT record and no script references 5925, so it's
  probably unused (hypothesis). It can be ignored for the campaign.
- Some trees (`dtre04..08`) use the world range for under 1% of their pixels, so a missing swap
  there is hard to see in screenshots. Compare pixels, not just your impression.

### Scenery in the unit catalogue (facts, array 5843 via `data/units.json`)
- Columns are `[template, init script, class, category, variant]`. Scenery template props are
  `[category, model]`, with no third prop.
- **New: for scenery categories 251/252/253/255 the variant column is the world + 5.** Variant
  5 = world 0, 6 = world 1, 7 = world 2, 8 = world 3. Each world has its own scenery models,
  and they reference that world's textures. Every mission's layout uses only its own world's
  variant.
- Structures (categories 211..237) use variant 1 or 88..99 and props `[cat, m1..m5]` (several
  models, probably damage or LOD states).
- Category 250 = rocks (variant 0, shared models, texture applied at spawn). 570 = ? (SetLevel
  -25). 500 = waypoint. 550-553 = nav/supply.

### How the rock override was found (to repeat for other scenery)
- Script listing: `.venv\Scripts\python -I tools/script7l.py ISO\G-NOME\G-NOME.BIN >
  %TEMP%\scripts.txt`. A copy from the last session is at `%TEMP%\gx\scripts.txt`, but it may
  be stale.
- Layout spawner **script 2523** `(L0 = mission id, L1 = layout array, L2 = world)`. Mission
  main scripts call it, e.g. `script_2523(1, 8743, 0)` for 1-1 and `script_2523(19, 9202, 3)`.
  For each layout row it reads the catalogue, then calls `script_2039(class, template, x, z,
  heading, y, category)`, the init script and `script_428(obj, category)`. Then it runs
  `switch category`:
  - 251 → `SetLevel(obj, -50)`; 570 → `SetLevel(obj, -25)`;
  - 250 → `L19 = GetProperty(obj, 39)` (the model), then `switch L2` →
    `SetModelTexture(L19, 2482..2485)`.
  - Before spawning, category 252 goes through `script_2524(&x, &z, y)` (a position tweak).
- **No other category gets a texture call in script 2523.** Scenery init scripts (e.g. 3967,
  4095, 4187, 4299) only build hotspots (`script_438`/`script_439` → `AddHotSpot`) and set
  property 16.
- `SetModelTexture` occurs only 6 times in all scripts: 4 in script 2523 (rocks) and once each
  in **script 2090 and script 2092**. Those clone `GetProperty(obj, 1)` or `GetProperty(obj, 2)`
  (models, probably LOD) and apply `SetModelTexture(clone, GetProperty(obj, 3))` when property
  3 is set. No script writes a literal `SetProperty(x, 3, …)`. Who sets property 3 (through a
  variable or the template) is still open.
- Other texture natives: `SetAnimatedTexture`/`SetTextureFrame` (scripts 1696, 1882, 2139,
  2279) and `ReplaceClump` (2299). These are probably effects or damage. Check that none of
  them touches scenery.

### Viewer today (`remake/game/viewer/mission_viewer.gd`)
- `_load_mission` reads `worlds[m.world_row]` and builds the world from `int(w.world) % 4`.
  It loads `rock_w<world>.png` (written by `tools/export_gamedata.py` from bitmaps 2482+w with
  the world's first palette) and `_retexture()`s category-250 nodes with a fresh
  `StandardMaterial3D`.
- `_setup_world` picks the ground texture `GROUND_PREFIX[wi] + "__w<wi>"` (none for world 0).
- `_model(id)` loads `modl_/mprt_%05d.gltf` through `GLTFDocument` at runtime and caches the
  generated scene per id. It then duplicates the cached scene for each placement.
- glTF materials are named after their texture (`export_models.Gltf.material`:
  `"name": tex`, e.g. `itre0100.bmp`), and their images point at `../textures/<stem>.png`.

### Missions by world (from `missions.json` + `worlds.json`)
- World 0: 1-1..1-5 (palettes 2487/2489/2491). World 1: 2-1..2-6. World 2: 3-1..3-5, 4-1, 4-2.
  World 3: 4-3..4-6.
- Good test missions: **2-2, 2-4** (world 1, 19 world textures each), **3-4** (world 2, 17),
  **4-3/4-4** (world 3, 12/11). 1-5 is a world-0 control.

## Plan
1. **Inventory (script, no game).** Regenerate `scripts.txt` and the `_import` data. For each
   campaign mission, list the placed categories, models and textures, and mark which textures
   have `__w` variants. The quick Python checks from this session are easy to redo from
   `units.json`, `layouts.json` and the glTF `images[].uri`. Optionally have
   `export_models.py` write `data/world_textures.json` (names plus a flag for "uses 216+") so
   the viewer doesn't need file-exists probes.
2. **Confirm no further overrides.** Trace `script_2039` → 2040/2041/2043 (per class) down to
   scripts 2090/2092. Find where property 3 comes from: template `[7,size,n,props]` records in
   `objects.json`, or `SetProperty(obj, L, …)` with a variable index. Also check the mission
   main and start scripts (e.g. 8737) and the world scripts (2514, 2418 and siblings) for
   `SetModelTexture` or palette changes after spawn. Use the script listing only. Use REA on
   RENDER.R32 `SetModelTexture` only if the semantics are unclear, and only when no other agent
   is using the backend.
3. **Viewer change.** After instancing a model for a world-w mission (w > 0), walk its
   `MeshInstance3D` surfaces. For each material whose `resource_name` has a
   `<stem>__w<w>.png`, assign a duplicated material with that texture. Cache materials per
   (texture, world) and the patched scene per (model id, world). Keep the rock path. Make sure
   the rock override still wins for category 250.
4. **Ground.** The viewer tiles only `?grd1000`/`mgrd2000`. Leave the tile-mask layout to
   future work (world scripts place tile objects OPRT 2478/2480 every 600 units, see
   `docs/analysis.md` "Data tables"), but make sure any tiles that get placed use the same swap.
5. **Verify against the original** (windowed, `Display=1`; no need to ask). Get a screenshot
   of one mission per world 1-3 (see Open questions for how to reach them). Take a viewer shot
   with `godot --path remake/game res://viewer/mission_viewer.tscn -- --shots <dir> 2-2,3-4,4-3`
   near the same spot, and compare tree, river and building colours.
6. Update `docs/analysis.md` (see the notes below) and set the status in `docs/REMAKE-BACKLOG.md`.

## Verification
- Static: for every campaign mission, every placed mesh whose texture has a `__w<w>` variant
  shows that variant (a debug print or assert in the viewer: count swapped surfaces per
  mission; for world 0 the count must be 0).
- Pixel check: sample a few known texels. For example, a world-1 tree texel with index 186..215
  must equal palette 2493's entry, not 2487's.
- Visual: side-by-side screenshots of original and viewer for at least one mission per world
  1-3, with the user's judgement where screenshots aren't conclusive.

## Open questions / risks
- **Reaching world 1-3 missions in the original.** The shipped `SGNOME*.SAV` files are 0-byte
  placeholders, so there are no ready saves. Options: play through; check whether the campaign
  menu allows mission select; temporarily patch a *copy* of `G-NOME.BIN` in `test-install` (never
  committed) so the 1-1 slot of mission table array 6984 runs another mission's main script.
  That's a hypothesis, since scripts may depend on campaign state. Another option is a peek or
  inject poke of the mission-index global. "Play Training Missions" (string 508) and the
  multiplayer maps (`script_2523` ids 41-47, worlds 0-3) may also reach other worlds.
- **RenderWare texture loading (hypothesis).** The plan assumes RWDL8D20 uses 7L indices
  directly with the screen palette. If RENDER/RW instead colour-matches textures when it loads
  them, the screenshot comparison will show this. If so, look at RENDER's texture loader
  (`FUN_100039cf`, `docs/analysis.md` "Bitmaps and textures").
- Property 3 / scripts 2090-2092 may apply texture overrides to some LOD scenery. Step 2
  settles this.
- `script_2523(0, 8731, 3)` is a mission id 0 with world 3 (attract/demo?). It's not part of
  the campaign and is unexplored.
- Rocks are "exact" only in the sense that texture 2482+w uses indices up to 214. That holds,
  so the per-world palette is enough there too.

## Dependencies
- **R1** (orientation): needed to put the viewer camera where the original's screenshot was
  taken. It doesn't block steps 1-4.
- **P4** (test matrix, later missions): shares the problem of reaching later missions in the
  original.
- **R8** (sprite exporter): reuses the palette rules found here (shared/world/mission entry
  ranges).

## Notes to fold into analysis.md
- Palette entry ranges: 10..185 shared; **186..215 per world; 216..245 per mission** (mostly
  backdrop sky). 2509 is world-table row 14 only, and 2510/2511 aren't in the world table.
- The 104 world textures carry a world prefix (`d`/`i`/`g`/`m` = worlds 0..3) and are never used
  outside their world in campaign layouts. Only `gaus2011/2012` (model 5925, unreferenced) use
  the per-mission range.
- Unit catalogue variant column: scenery 251/252/253/255 variant = world + 5.
- Script 2523 signature `(mission id, layout array, world)`. Category handling: 251
  SetLevel -50, 570 SetLevel -25, 252 position tweak via `script_2524`, 250 SetModelTexture.
- Scripts 2090/2092: clone model prop 1 or 2 and apply `SetModelTexture(prop 3)` if set.
