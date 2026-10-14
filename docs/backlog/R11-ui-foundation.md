# R11: UI design system and Godot UI foundation

Status: **active**

## Decisions (user, 2026-10-12)
- Keep the **original visual direction** (modernised G-Nome). No modern game UI as reference
  besides *Star Wars: Squadrons* for inspiration.
- **2D menus**, with an optional 3D scene inside the centre "screen".
- **Diegetic 3D cockpits** (R17).
- Fonts: **Saira** (variable, OFL) + **Share Tech Mono** (OFL), chosen by comparison with the
  original's lettering.
- Design direction, palette, typography and references: `remake/UI-DESIGN.md`.

## Progress (2026-10-12)
- First style frame: `remake/game/ui/screens/main_menu.tscn` (main menu with the original's
  arrangement, menu tree from array 8611, hover/status line, LED bar, a 3D Prowler turntable in
  the centre screen, power-on sweep). Render it with
  `godot --path remake/game res://ui/screens/main_menu.tscn -- --shots <dir> --size 1920x1080 --select 2,0`.
  Checked at 1920x1080, 3840x1600 and 3840x2160: layout holds, and text and edges are sharp at 4K.
- Kit so far (`remake/game/ui/`): `shaders/machine.gdshader` (SDF machinery panels: paint, brushed
  steel, cast iron, bevels, hazard stripes, recesses/vents, rivets), `shaders/glass.gdshader`
  (glass slots/buttons), `shaders/screen.gdshader` (screen vignette, scanlines, power-on);
  components `MachinePanel`, `GlassButton`, `BarButton`, `CableCoil`, `ModelStage`, `Pillar`;
  `theme/main_theme.tres` (Saira variations, type variations GlassButton, BarButton,
  StatusLabel, ScreenTitle, DataLabel, DataValue, Readout); `theme/ui_palette.gd`.
- Project: base 1920x1080, `canvas_items` stretch with `expand` aspect, `hdr_2d` on (phosphor
  text and LEDs use HDR colours and bloom through a 2D WorldEnvironment glow), project theme set.
- Fonts render as normal dynamic fonts; Godot's automatic oversampling keeps them sharp, so
  MSDF is kept for 3D text (cockpit instruments, R17).
- **Target look set by the user** (`remake/art/ui/reference/target_briefing.png`): rebuilt the
  menu as a live 3D machinery frame (Blender script `remake/art/ui/frame/build_frame.py` →
  `game/ui/frame/menu_frame.glb`, `MenuFrame` with CC0 PBR materials from `tools/fetch_cc0.py`)
  with the 2D layer pinned to anchors (`GlassButton`, `KeyButton`, `StatusBar`, `PaneFrame`,
  `ModelStage`). The flat vector pillar kit (MachinePanel, Pillar, CableCoil, BarButton) was
  removed. Run `python -I tools/fetch_cc0.py` once before opening the project.
- Gotcha: HDR 2D viewport images are half-float linear (format RGBH); screenshots must be
  converted to RGBA8 + `linear_to_srgb()` or they look far too dark. Shader literal colours are
  linear in HDR 2D: author in sRGB and convert (`pow(col, 2.2)`), as `glass.gdshader` does.
- Second pass toward the target: the core now fills 16:9 (pillars at the screen edges, wider
  bezel/keys); sculpted armour (cut-corner layered plates, white chevrons, indicator lamps,
  vents, rams, hoses, grille, foot plates), drum collars, a thick sloped bezel with trim, bolts
  and clips, a header lamp housing, lamp pods and pipes under the screen, sloped steel keys.
  `build_frame.py` bakes edge-wear/grime masks into vertex colours; `frame_material.gdshader`
  (triplanar PBR) wears paint to bare steel on edges and darkens seams. Reflections come from
  a CC0 studio HDRI (Poly Haven, `fetch_cc0.py`). Added `TacticalMap` (briefing terrain from the
  mission layout: rocks as contoured ridges, waypoints, hostiles, player start) and
  `ScreenChrome` (corner brackets, title rules).
- Third/fourth pass: curved armour, emblem decal, stencils, cabling; painted-survey briefing map
  (invented fbm terrain + ridges on the mission rocks, clouds; placeholder until R13 finds the
  real map); deep hangar bay in `ModelStage`; model textures sampled as RW frames (frame 0 =
  normal paint, see analysis.md); brushed-steel keys with engraved labels; polished collars.
- User feedback (2026-10-13): green glow was far too strong on buttons and text. Toned down:
  green/yellow UI colours now stay at or below 1.0 (no HDR overdrive), 2D glow intensity 0.18
  with threshold 1.2, softer slot/key outlines, dimmer LEDs and slot spill lights. Keep new
  UI colours in that range; only lamps and LEDs may bloom.
- Interaction: keyboard/gamepad navigation in `main_menu.gd` (explicit focus neighbours; keys
  row, columns top to bottom, accept moves into the next column, ui_cancel steps back; focus
  shown only while keys/pad are in use), 3D key press travel (`MenuFrame.press_key`), UI
  sounds (`UiSounds`, synthesized by `remake/art/ui/sounds/make_sounds.py`, placeholders
  until R8). Verified by a scripted key run; not yet tried with a real pad.
- Audit pass against the target image (2026-10-13; comparison crops in `%TEMP%\ui_audit\`).
  Ranked gaps, biggest first, and what was done:
  1. Bezel/header: the bezel rendered black because fully metallic flat faces only mirror the
     dark sky behind the camera. Steel is now mostly diffuse (`base_metallic` 0.3-0.7) with
     new `steel_bezel`/`steel_drum` materials; the bezel is a narrow grey band with big top
     chamfers and a bright inner lip, and the 2D glass (`screen_glass.gdshader`) cuts the same
     corners. A dark header strip with small red LED modules fills the top band (the four big
     lamps are gone).
  2. Keys: dark weathered face plate over the whole key with a matte-black LED slot (`recess`
     material), white labels with a dark outline (theme `KeyButton`, label pushed down by the
     style box's top margin), selected outline on the plate edge, thin gap lamps. The LED is a
     saturated green bar at emission 1.1 (higher clipped to white under ACES).
  3. Armour: matte red (`base_roughness` 1.6) whose grey texture flecks become bare steel
     (`chip_amount` in `frame_material.gdshader`), steel rims behind the plates, bolt rows,
     panel seams, a white wedge, vertical orange lamp strips on the inner edge, rams and
     pistons in front of the plates, a small hazard patch, an orange indicator panel on the foot.
  4. Screen: dark teal glass with a faint circuit grid and a chamfered inner border; the
     chrome is a rule under the title plus readout dashes (corner brackets removed); panes
     without ticks; bigger objective text and title.
  5. Map: broad sandstone forms on olive-brown, fewer tan contours, a green screen tint.
  6. Hangar: lamp strips no longer blow out; the vehicle fills the pane.
  7. Collars in dark gunmetal; the empty slot is a deeper, less saturated blue; the under-screen
     strip is slimmer with small pods; the status housing has a light steel rim.
  Still off (needs new art or a model, not tuning): the vehicle is the original low-poly
  model (R13/R16 art); the pillars have fewer layered plates, rivets and cabling than the
  target; the map terrain is invented until R13 decodes the real map; the target's painterly
  grime/chipping variety needs authored masks rather than a tiled CC0 set.
- Screenshot mode gained `--focus <node>` (e.g. `--focus Key1`) to capture keyboard focus.
- Audit pass 2 (2026-10-14, user's pick from the "still off" list: armour and the key bank;
  mech and map terrain stay as they are, future revisions):
  - **Key bank in perspective** (`build_keys` in `build_frame.py`): the tray bows toward the
    viewer (`KEY_ARC_R`); each key sits on that arc under an empty `key_root_i`, turned with
    it, so the outer keys splay and show their outer sides. A key is a chunky block whose
    label face leans back with a lower chamfer, a chamfered `steel_bezel` frame around a
    worn face plate, a matte LED slot, and a steel ledge runs along the bank's bottom edge.
    `MenuFrame.anchor_quad()` projects the turned face as a trapezoid; `anchor_rect()` is
    its bounding box (hit area and label), and `KeyButton.face` draws the selected/focus
    outline along the trapezoid. The press tween is unchanged: the parts are children of the
    key's root, so `KEY_TRAVEL` is already in the key's own frame (`--press <key>` in the
    screenshot mode captures it mid-travel). A frontal fill light evens out the splayed
    faces, and `steel_face` is low-metallic/rough so the turned keys don't each reflect a
    different part of the HDRI.
  - **Armour**: `frame_material.gdshader` gained painterly wear from the seamless fbm noise
    (`patch_amount` blotches worn to bare metal, `speckle_amount` chips/dirt specks,
    `rust_amount`/`rust_tint` staining, dirt in the noise's hollows), sampled at three scales
    with offsets so no two plates repeat. `build_pillar` adds raised sub-plates with steel
    rims (panel under the top plate, the foot plate), bolt rows along every edge, panel
    seams, ram/piston socket plates with four rivets, hex nuts, hoses over the outer edge,
    thicker cable runs beside the bezel, and stronger plate curvature (drum-like shading).
  - Still off: the target's rams are larger with heavier chrome collars; the hoses in the
    target are braided with fittings; its paint has broader value variation (lighter
    worn areas) than one tint plus procedural wear gives. All tuning, no blockers.
- Sounds (2026-10-14, user signed off): the original menu waves are used (R8: 8403 key, 8404
  slot, 8398 menu loop; Escape replays the slot/key sound like the original). Hover keeps our
  synthesized tick on purpose: the original is silent there, but the user likes it. Selected
  key label is upright (italic looked wrong on the angled keys). Closed for now.
- Next: gallery scene; router/actions (R12); test with a real pad.
- Earlier next steps: user review of the style frame; authored hi-res material maps (replace the noise);
  keyboard/gamepad focus pass; gallery scene; UI sounds; router.

## Goal
A sharp, modern, resolution-independent UI kit for the remake, built from scratch the
Godot-native way. It mixes **vector elements** (crisp at any size) with **high-resolution
textures** (material and detail), and every later UI item (R12 menus, R13 briefing, R14
options, R15 Lab, R17 HUD) builds on it.

Done when:
- the user has approved a visual direction from 2-3 style frames;
- a project-wide `Theme` plus a component library exist, shown in a gallery scene;
- the gallery stays crisp and well laid out at 1280x720, 1920x1080, 2560x1440, 3840x2160 and
  the user's 3840x1600 (12:5), and works with mouse, keyboard and gamepad.

## Background
- Decision (2026-10-12, user): the UI should look **a lot sharper** than the original. Use the
  original as reference (flow, content, layout intent, mood), but build the new UI **from
  scratch**, following Godot best practice, mixing vector-based elements with high-res
  textures. The original 640x480 8-bit bitmaps are **not** placeholders for UI. Until the
  final art exists, screens use this kit in a greybox style.
- The original look, for the mood board (see the 1-1 cockpit and menu shots from R1/R10):
  heavy industrial frames with red hazard-striped metal and rivets, blue glass indicator
  panels, green phosphor monospace text, and the bottom bar of five chunky push-buttons.
- Target displays include ultrawide: the user's single monitor is 3840x1600.

## Approach (recommended; confirm the open decisions with the user)

### Structure (Godot best practice)
- `remake/game/ui/`:
  - `theme/main_theme.tres`: the single project theme (`gui/theme/custom`). Use theme
    **type variations** (e.g. `PrimaryButton`, `BarButton`, `StatusLabel`, `HudReadout`)
    instead of per-node overrides.
  - `components/`: reusable scenes with a script each: bar button, side-menu button, panel
    frame, status/tooltip line, list/slot picker, dialog, slider/toggle rows, key-binding row,
    loading/transition overlay.
  - `screens/`: one scene per screen (R12+), composed only of containers and components.
  - `ui_router.gd` (autoload): a screen stack (push/pop/replace), transitions, and the back action.
  - `ui_sfx.gd` (autoload) on a `UI` audio bus: hover/press/back sounds, sourced from the
    original waves (R8) until new sounds exist.
- Layout only through **containers and anchors** (`MarginContainer`, `HBox/VBox`,
  `GridContainer`, `AspectRatioContainer`), never absolute pixel positions, so 16:9, 16:10,
  4:3 and 12:5 all work.
- Project settings: `display/window/stretch/mode = canvas_items`, `aspect = expand`, a base
  size of 1920x1080. Add a user **UI scale** option (R14) through `content_scale_factor`.
  Keep important content inside a 16:9 safe area on ultrawide, and let decoration extend to the edges.

### Vector side
- Panels, buttons and frames: `StyleBoxFlat` (corner radius, bevel via border + shadow,
  anti-aliasing, skew for angled sci-fi edges) wherever it is enough.
- Icons and line art: **SVG** sources in `remake/art/ui/`. Check how Godot 4.7 keeps SVG
  sharp under scaling (import scale / oversampling, `DPITexture` if available in this version) and
  pick one rule for the project.
- Procedural elements (HUD rings, ticks, compass tape, radar sweep, brackets): `_draw()` with
  anti-aliased primitives, or `CanvasItem` shaders using SDF shapes. These stay sharp at any
  resolution and animate cheaply.
- Text: **MSDF fonts** (enable multichannel SDF in the font import) for display/HUD faces so
  text scales and glows cleanly. Use OFL-licensed fonts (licence file committed with the font). Candidates:
  a condensed industrial sans for labels and a monospace for readouts (green phosphor nod).

### High-res texture side
- Material layers for frames and panels (brushed/painted metal, hazard stripes, grime, glass
  tint), authored at 4K-ready density. Use them through `StyleBoxTexture` (nine-patch margins)
  or as a texture uniform in a panel shader (vector shape mask × tiled hi-res material ×
  edge highlight). Mipmaps and filtering on; keep source files in `remake/art/ui/`.
- Optional subtle effects: glow/bloom on emissive text (CanvasItem shader or a
  `SubViewport` with its own glow), scanline/noise overlays for "screens", and animated
  hover states with `Tween`.

### Input and accessibility
- Every component works with focus: set focus neighbours, a visible focus style, and the
  `ui_accept`/`ui_cancel`/`ui_*` actions mapped for keyboard and gamepad. Mouse hover moves the focus.
- Text through `tr()` keys from the start (English source = the original strings).
- UI scale, high-contrast and colour-blind-safe variants as theme variations.

## Plan
1. **Mood board and reference**: collect original screenshots (R10's reference run), the
   cockpit shots from R1, and 3-5 modern references the user likes (ask). Write down the
   design principles (palette, type, shapes, motion) in `remake/ui/README.md` or a short design doc.
2. **Style frames**: build 2-3 directions as Godot scenes rendering the main menu bar
   and one submenu (screenshot mode at 1920x1080 and 3840x1600). Show the user and get a pick.
3. **Theme and components**: implement the chosen direction as the theme plus the
   component scenes listed above. Fonts and SVGs in, the first hi-res material set in.
4. **Gallery scene** `ui/gallery.tscn` with every component and state (normal, hover,
   focus, pressed, disabled), plus a `--shots <dir> --size WxH` mode like the mission viewer.
5. **Router, SFX, input**: `ui_router.gd`, `ui_sfx.gd`, InputMap actions, gamepad focus navigation.
6. Document the kit (how to add a screen, naming of type variations, art export rules) in
   `remake/README.md`.

## Verification
- Gallery screenshots at the 5 resolutions: no blurry text or icons (zoom into crops at
  4K), and no clipping or overlap at 12:5 and 4:3.
- Keyboard-only and gamepad-only runs reach every gallery control (the user tests a pad).
- The user signs off on the style frames and on the gallery's look.

## Open questions
- Base resolution 1920x1080 vs 2560x1440 (working assumption: 1920x1080).
- SVG icons: `DPITexture` exists in Godot 4.7 (checked), so use it for SVG icons.

## Dependencies
- None blocking (design can start now). R10 provides the content inventory. R8 provides
  original sounds as placeholder UI SFX.
- Required by R12, R13, R14, R15, R17.

## Notes to fold into analysis.md / README
- The UI decision above goes into `remake/README.md` "Decisions" (done when this item was written).
