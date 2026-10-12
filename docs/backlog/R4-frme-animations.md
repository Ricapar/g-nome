# R4: Decode FRME animations and export them to glTF

Status: **todo**

## Goal
Decode the 333 FRME resources (7L index type 4) and export them as glTF animations that play
on the existing model exports (`remake/game/_import/models/modl_*.gltf`). Also export each
unit's animation state machine (`addAnimation`/`addTrigger` data) as JSON so the remake's
vehicle controller (R5) can drive it. Done when a walking Prowler in the Godot viewer matches
the original game's walk cycle frame for frame.

## Background
- HAWCs (bipedal mechs) and infantry are animated by FRME data. Hovercraft use no FRME. The
  unit init scripts set up a per-object animation state machine over FRME resources.
- Models are already exported to glTF, one node per RenderWare clump, named `clump_<tag>`
  (`tools/export_models.py`, `tools/rwstream.py`; see `docs/analysis.md` "Model stream").
  `docs/analysis.md` says tags are "what FRME animations and `AmputateClump`/damage refer to".
  That claim is now confirmed (below).
- `remake/README.md` Phase 0 still has "[ ] FRME animations → glTF animations".

## What is already known

### File format (facts, verified 2026-10-12 by a read-only survey of all 333 entries)
- Index ids 2597..5380. One entry is size 0. Sizes run from 208 to 91024 bytes, 3.63 MB in
  total.
- Layout: `char[4] "FRME"; u32 nparts; u32 nframes; u32 zero` (16 bytes), then
  `nframes * nparts` records of 12 float32 each (48 bytes). Size = 16 + 48·P·F holds for 331 of
  332 non-empty entries. Word 3 is 0 in all of them.
- Each record is a 4x3 row-vector matrix: floats 0..8 are the 3x3 rotation/scale rows, 9..11 the
  translation. That is the RW `TransformCTM` 4x4 without its constant last column.
- **Order is frame-major**: frame f, part p is at record `f*P + p`. Frame-to-frame differences
  are about 20x smaller in this order than in part-major order.
- **Part p is the clump with tag p+1** in the matching model. Each LOD model has tags 1..N with
  no gaps. **Matrices are parent-relative** and use the same convention as the exported clump
  `matrix`. Proof: frame 0 of the 1-frame FRMEs 2597/2604/2611 equals the clump matrices of the
  Prowler LOD models 2583 (20 clumps), 2589 (18) and 2595 (15) exactly.
- Scale: 17,619 of 74,905 matrices have non-unit row lengths, e.g. a uniform 0.183 in FRME 2664
  part 1. The models' own clump CTMs carry the same scale, so this is real data, not noise.
  Shear has not been checked.
- Translation: 2,446 of 3,881 part tracks (multi-frame FRMEs) keep a constant translation, so
  they only rotate. In the Prowler walk loop 2599 (30 frames), the root-level clumps tag 19 and
  tag 20 (feet, y ≈ 0.002) slide about 0.28 model units along z, and tag 11 (pelvis, parent of
  9/10/16) bobs. Nothing seen so far moves the whole object, so there is probably no root
  motion (hypothesis).
- Part counts: 4..31. Frame counts: 1 (65 entries, rest poses), 2, 7..37, 71, 79, 80.
- **Anomaly: FRME 4733.** The header says 10 parts x 71 frames, but the data holds 700
  matrices, which is 70 frames. Only `AnimateFrame` uses it (scripts 4738/4741). Clamp to the
  data length.

### FRME ↔ model ↔ LOD (facts)
- An OB3D unit template, e.g. 2618 (Prowler), has props[1..7] = 2583..2595, step 2 (the odd ids
  in between are type-2 textures). Script 2146 clones **prop 1 → obj prop 79 (LOD0), prop 4 →
  80 (LOD1), prop 7 → 81 (LOD2)**. Props 2,3,5,6 go onto list `G1849`. For the Prowler,
  2583/2585/2587 are LOD0 (20 clumps) with texture sets `hbl1a*/hbl1w*/hbl1s*`, 2589/2591/2593
  are LOD1 (18 clumps) and 2595 is LOD2 (15 clumps). The paint variants share clump tags, so
  they also share FRMEs (verify).
- The OB3D LOD records `[2,min,max,19,script]` call scripts 2147/2148/2149/2150 by distance.
  These run `setLOD(obj, n)` + `LinkModel(obj, prop 79/80/81)`. Script 2138 cycles all three.
- `addAnimation` takes **three FRME ids, one per LOD** (part counts 20/18/15 for the Prowler).
  Infantry pass 0 for LOD1 because they have only LOD0 and LOD2.

### Script side (facts from `tools/script7l.py` output; meanings are hypotheses)
- 120 `addAnimation` and 124 `addTrigger` calls sit in 20 animation-setup scripts, one per
  animated catalogue row. Each is called from the unit's init script (array 5843 column 1):
  2631 Prowler, 2688 Rampage, 2737 Lion, 2775 Titan, 2842 Union infantry, 2899 Talon,
  2957 Stalker, 2995 Boulder, 3062 Darken infantry, 3119 Ogre, 3177 Minotaur, 3217 WidowMaker,
  3266 Venom, 3304 Legionnaire, 3379 Merc infantry, 3436 Jinx, 3494 Predator, 3542 Scorpion,
  3581 Stinger, 3648 Scorp infantry. 311 of the 333 FRMEs appear as literal ids in scripts.
- Example (script 2631, Prowler):
  `addAnimation(obj, index, type, frme_lod0, frme_lod1, frme_lod2, n, a, b, script)`, e.g.
  `addAnimation(L0, 0, 1, 2598, 2605, 2612, 21, 2599, 2600, 0)`, `(…, 6, 11, 2597, 2604, 2611, 8,
  0, 0, 0)`; `addTrigger(L0, 2599, 5, 2601, 0)`; then `installAnimationType(L0, 11)`.
  - type: 0,1,2,3,4,11 on HAWCs; infantry also use 5,7,9,10. 11 = rest pose (always 1 frame,
    n = 8, installed at spawn). Hypothesis: 1 = start walking, 2 = walk loop (a=0, b=itself),
    4 = stop (runs script 1721), 3/0 = other gait chains.
  - a/b: probably "next" and "alternative" FRME. -1 probably means hold the last frame.
  - n: 21/24/26/38/8… It does not match the frame counts (10/30/10/30/1). It could be a playback
    rate, a speed threshold or a stride length. **Open; important for R3.**
  - `addTrigger(obj, frme, event, target_frme, flag)`: event codes 1,2,3,4,5,8,9,10. Probably
    "on event X while playing frme, switch to target".
- `animationSetupProps(12, 33, 15)` runs once at 3D init (script 2564). This probably tells
  RENDER which object properties feed the animation system. **Prop 12 is the target speed**:
  `script_2064(obj, v)` clamps v to props 35/36 and stores it in prop 12. The player throttle
  sets it (script 1975, `RangeJoystickAxis`), and `script_2065` → `ApproachTargetSpeed`.
- Script 1721 (the callback of the type-4 "stop" animation) → `script_2062(obj, 0)`, which sets
  prop 34 and calls `SetVelocityForward(obj, 0)`. Scripts 1750/1752 install types 5/7, set
  velocity 10 if it is 0, and call `SetObjectFramerate(obj, 1500)`. Script 1748 maps current
  type 5→9 and 7→10. The key-4 strings include the control actions "Kneel" and "Prone", so
  5/7 are probably kneel/prone and 9/10 the matching get-up animations. AI script 2021 picks
  them by target distance (prop 108 < 320 / < 250).
- Other animation calls: `SetProperty(obj, 99, rest_frme)`, `SetProperty(obj, 101, k)` (2 for
  Prowler, 5 for infantry), `SetModelDimensions(prop79, rest_frme, obj, 55, 56, 57)` (bounds
  from the rest pose), `createAnimationList` (spawn, scripts 2041/2043), `removeAnimations`
  (destroy, 2276), `getCurrentAnimationType` (1956/1975 check the player for types 2/3/11).
  `AnimateFrame`/`AnimateModelFrame` play FRMEs directly: script 1742/1743 use props
  44 (FRME), 14 (frame counter) and 43 (frame count); 2153/2154 use props 13/14; 4395..4399 use
  FRME 4388; 4738/4741 use FRME 4733. `GetFrameRate(0..4)` is read in script 554.

### RENDER.R32 entry points (export VAs from `tools/peinfo.py`; not yet decompiled)
`addAnimation 0x1000ae57`, `addTrigger 0x1000b961`, `animationSetupProps 0x1000aac0`,
`createAnimationList 0x1000aadc`, `removeAnimations 0x1000ab87`, `findAnimationType 0x1000b0f7`,
`setLOD 0x1000b193`, `installAnimation 0x1000b338`, `installAnimationType 0x1000b573`,
`getCurrentAnimationType 0x1000b5c7`, `doAnimationUpdate 0x1000b75a`, `AnimateFrame 0x100105ec`,
`AnimateModelFrame 0x100106bb`, `GetFrameRate 0x1001234b`, `GetNumClumps 0x100123de`,
`GetNumFrames 0x10012431`, `SetAnimation 0x10016538`, `SetObjectMotion 0x10016b20`,
`SetObjectFramerate 0x10016b8f`, `UpdateFrameCycle 0x10017b20`, `UpdateFrameTerm 0x10017d88`,
`UpdateLOD 0x10029743`, `SetModelDimensions 0x100087ab`, `LinkModel 0x10012af7`.
The `FRME` magic appears twice in RENDER.R32, at file offsets 15407/16142 (VA 0x1000482f,
0x10004b0e), next to MODL/MPRT/OB3D/OPRT/GRND. That is almost certainly inside the resource
loader `FUN_100043f0` (`docs/analysis.md` "Object templates"). RTLIB32 has no FRME string.

## Plan
1. **Parser** `tools/frme7l.py`: `read_frme(bin_path, ent) -> (nparts, nframes, frames)`, with
   frames[f][p] = 12 floats. Clamp to the data length (4733). Self-check over all entries.
2. **Reverse the runtime (REA, RENDER.R32)**: the FRME branch of `FUN_100043f0` (any
   post-processing at load time?), `addAnimation`, `addTrigger`, `installAnimationType`,
   `doAnimationUpdate`, `UpdateFrameCycle`/`UpdateFrameTerm`, `SetObjectFramerate`,
   `animationSetupProps`. Answer these questions: frame timing (units of 1500, the tick
   length), whether frames are interpolated or stepped, what `n`, `a`, `b`, the trigger event
   codes and `flag` mean, how prop 12 (speed) selects or scales animations, and whether the
   animation feeds back into object velocity (see R3). Record the findings in
   `docs/analysis.md`.
3. **State-machine export**: parse the 20 setup scripts (from the `script7l` decoder, not text
   scraping) into `remake/game/_import/data/animations.json`: per unit row, the animation
   list (index, type, FRME per LOD, n, a, b, script) and the triggers. Join it to the template's
   LOD models (props 1/4/7 plus the variants 2,3,5,6).
4. **glTF export** (extend `tools/export_models.py` or add `tools/export_anims.py`). For each
   unit LOD model, add one glTF `animation` per FRME, named `<type>_<frme id>`. Each part gets
   `translation`/`rotation`/`scale` channels on the `clump_<tag>` node. glTF forbids animating
   a node that has `matrix`, so animated models must write TRS instead of `matrix`. Decompose
   each 4x3 matrix: if det < 0, flip one axis; get the scale from the row lengths; check that
   recomposing it stays within 1e-4 and report any shear. Use STEP or LINEAR interpolation
   and the frame time found in step 2 (until then, a placeholder rate marked in the file).
   Keyframe times are frame index · frame time. Skip constant tracks.
5. **Viewer**: add animation playback to `remake/game/viewer/model_viewer.gd`. Runtime
   `GLTFDocument.generate_scene` creates an `AnimationPlayer`. Add a key to cycle animations
   and step frames, and a `--shots` option that renders frame N of animation A.
6. Fix `docs/analysis.md` (see the notes below) and tick the README Phase 0 box.

## Verification
- Every FRME parses. For each animated unit and each LOD, the rest-pose FRME (type 11) frame 0
  equals the model's clump matrices (≤ 1e-4). Every FRME's part count equals the clump count of
  the LOD model it is paired with.
- Recomposed TRS matches the source matrices for every frame. The glTF validates
  (Khronos glTF-Validator, if available) and loads in Godot without warnings.
- Visual: the Prowler walk loop (2599) and start/stop (2598/2600) play in the viewer with feet
  planted and no popping at the loop point. Compare against the original in a windowed
  screenshot sequence (`tools/dev/drive.ps1`, `Display=1`, allowed without asking). Mission
  1-1 path in `CLAUDE.md`, then `shot:` every ~100 ms while a HAWC walks in view. The strings
  list "External Camera" / "Trailing Camera" actions, so the player's own unit can be filmed
  once their keys are found (Options → controls). The LAB vehicle viewer may also show the
  models (unverified). Match the pose at equal phase and the cycle duration. Ask the user to
  judge feel and speed.
- Infantry: kneel/prone/get-up (types 5/7/9/10) play correctly on the 2-LOD infantry models.

## Open questions / risks
- Meanings of `n`, `a`, `b`, trigger events and `flag` (step 2). The frame rate and
  interpolation are unknown.
- Root motion: is ground speed derived from the animation (foot slide 0.28 units per loop) or
  set independently through `SetVelocityForward`/prop 12, with the animation rate following
  speed? This is the main R3 coupling.
- Shear or mirrored matrices (det < 0) can't be expressed in TRS. If any exist, bake them or
  keep `matrix` on non-animated nodes.
- Handedness (R1, done): no axis flip is needed. Raw RW coordinates are used unmirrored, so
  animation tracks can be exported as-is too.
- 22 FRMEs are not referenced by a literal id. They may be reached through arrays or be
  unused. Check against `arrays.json`.
- `AnimateModelFrame` on props 79 and 81 (scripts 1742/1743, 4398/4399) animates scenery or
  structures, not units. Find which objects use it.

## Dependencies
- **R3 (movement)**: both items need step 2. If movement is animation-driven (speed tied to the
  stride or to `n`), R4 must land before R5. Current evidence (scripts set the speed through prop
  12 / `SetVelocityForward`, and stop animations zero the velocity through script 1721) points to
  **speed-driven animation with velocity set by scripts**, so R4 probably isn't a blocker for
  R5's movement. That is unconfirmed until `doAnimationUpdate` is read.
- R1 (orientation/handedness) affects the axis convention of the exported tracks.
- R2 telemetry can log the current animation type and frame per tick for comparison.
- Feeds R5 (sandbox: walk as soldier, drive a HAWC) and R7 (AI posture changes).

## Notes to fold into analysis.md
- The FRME format, frame-major order, part = tag−1, parent-relative matrices with scale, and
  the 4733 anomaly (above).
- **Correction:** the "Missions, units and layouts" section says "Template props[1..7] = the
  same model in 7 team colours". The scripts show props 1/4/7 = LOD0/1/2 (to obj props
  79/80/81, via script 2146) and props 2,3,5,6 = paint variants of LOD0/LOD1 (Prowler texture
  sets `a`/`w`/`s`).
- Object props: 12 target speed (clamped by 35/36), 34 velocity forward, 79/80/81 LOD models,
  92 current LOD, 39 linked model, 99 rest FRME, 55..57 model dimensions. Also
  `animationSetupProps(12, 33, 15)`.
- The RENDER.R32 animation export VAs and the FRME magic sites listed above.
