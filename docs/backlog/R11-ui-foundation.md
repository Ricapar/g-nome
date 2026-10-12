# R11: UI design system and Godot UI foundation

Status: **todo**

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

## Open questions (decisions for the user)
- Visual direction: a faithful "modernised G-Nome" (keep red hazard metal, blue glass, green
  phosphor) or a cleaner new identity? Recommendation: modernised G-Nome, so the remake still
  reads as G-Nome.
- Diegetic vs flat UI: should the menus sit inside a 3D scene (e.g. a hangar with the menu on
  a console), or a 2D layered UI over an animated background? Recommendation: 2D UI over a
  live 3D background, which is cheaper and still modern.
- Fonts and any licensed (non-OFL) assets.
- Base resolution 1920x1080 vs 2560x1440.

## Dependencies
- None blocking (design can start now). R10 provides the content inventory. R8 provides
  original sounds as placeholder UI SFX.
- Required by R12, R13, R14, R15, R17.

## Notes to fold into analysis.md / README
- The UI decision above goes into `remake/README.md` "Decisions" (done when this item was written).
