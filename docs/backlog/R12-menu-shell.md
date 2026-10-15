# R12: Front-end menu shell in Godot

Status: **todo**

## Goal
The remake's main menu and all its submenus, built with the R11 kit and following the
original's flow from R10: GAME (New → Campaign/Training/Mission, Load, Save, Credits),
NETWORK, LAB, OPTIONS, EXIT, with status-line help text, sounds, the intro movie and
transitions. Screens that belong to other items (briefing R13, options pages R14, Lab R15)
are stubs that the router can open.

Done when you can boot the remake, skip the intro, and reach every menu entry the original
has with mouse, keyboard or gamepad, in the same structure, and CAMPAIGN → LAUNCH opens the R13
briefing stub (or the R5 sandbox once it exists).

## Background
- Original (R10): a bottom bar of five buttons; each opens a column of up to four entries on
  the left, and some entries open a second column on the right. Selecting another bar
  button closes the open columns. The bottom strip shows a help line per hovered entry
  ("Start a New Game"). Wave 8398 loops under the menu and 8403 plays on selection. The
  centre of the screen is a big empty viewport frame (used by the Lab, briefing, and credits).
- Decision (user, 2026-10-12): keep the original's layout and identity (pillars, centre
  screen, status strip, push-button bar; see `remake/UI-DESIGN.md`), rebuilt sharp. Menus are 2D;
  the centre screen may show a 3D scene (e.g. a rotating HAWC when idle). Flow and content
  are faithful. Proportions adapt to wide screens; the arrangement stays.

## What is already known
- Menu tree, positions, click/hover scripts and action ids: R10 (`ui_menus.json`, array 8611).
- Intro: DREAM.SMK via `script_7(2, 11)`; G-NOME.SMK / NEWS / WILKINS / CREDITS are played by
  other scripts (R8 "Smacker movies"). Credits = `script_7(3, 8390)`.
- Exit shows advert bitmap 2396 before quitting (R8 notes). The remake can drop or replace it.
- Sounds (R8, `UiSounds` ids, files in `_import/audio/`): `quit` (wave 131) when Escape on the
  main menu opens the exit confirm (user approved this sound), `denied` (74) for an action
  that isn't available (e.g. SAVE outside a mission), `toggle` (75) for option toggles,
  `ambience` (8398, already playing). Hover tick stays (user's choice).

## Plan
1. **Data**: load `ui_menus.json` (R10) into a menu model; keep labels as `tr()` keys. Define
   the menu in a small Godot resource (`menu_def.tres`) generated from the JSON, so the
   structure isn't hard-coded in scenes. Only copy structure and action ids from the
   original; the label text is ours.
2. **Screens**: `main_menu.tscn` (bar + side columns + status line + centre stage),
   `credits.tscn`, `exit_confirm` dialog. Stubs: `briefing` (R13), `load/save` (R13),
   `options/*` (R14), `lab/*` (R15), `network/*` (Phase 3: show "coming later").
3. **Behaviour**: same selection rules as the original (one bar entry open, right column
   replaces on change, back/escape closes one level), hover → status line, sounds, focus
   navigation that follows the columns (left/right moves between columns).
4. **Intro and video**: play the exported DREAM `.ogv` (R8) with skip on any key, then the
   menu. If R8 isn't done, show a title card instead.
5. **Centre stage**: a `SubViewportContainer` with a simple 3D scene (a slowly rotating
   vehicle from the imported models) as the menu background. Keep it optional (setting).
6. Make `main_menu.tscn` the project's main scene once it works; keep the viewers
   reachable from a debug menu or command-line flag.

## Verification
- A recorded click-through (screenshots at 1920x1080 and 3840x1600) reaches every node in R10's map.
- Keyboard-only and gamepad-only runs do the same (user check for gamepad).
- Side-by-side with the original's reference shots: same entries, same order, same
  nesting, same help texts (allowing for rewording decided with the user).

## Open questions
- Keep the original's exact help-line wording, or rewrite? (Default: keep it, as `tr()` source text.)
- Should the remake keep the 7th Level/exit advert screens? (Default: drop the advert, keep credits.)
- Training and MISSION select: do they need a mission picker screen (R13)?

## Available from R11 (2026-10-14)
- `UiRouter` autoload already exists: `push`/`pop`/`replace`, the shutter transition,
  `back()` (calls a screen's `ui_back()`), and `await confirm(...)` for the exit prompt.
  Use `StubScreen.make(title, note)` for the R13, R14 and R15 stubs.
- `UiSfx` autoload replaces the menu's own `UiSounds` node. `bind(button, id)` gives the
  standard sounds.
- The main menu still handles ui_cancel in its own `_input`. Move that to `ui_back()` so the
  router's dialogs get Escape first. The router already raises its layer when a dialog
  opens, but the menu's `_input` still runs.
- Pad A and B are now on ui_accept and ui_cancel. Before this, a pad couldn't press menu
  entries at all.
- The usage guide is in `remake/README.md`, "UI kit". The gallery shows every component.

## Dependencies
- R10 (menu map), R11 (kit). Uses R8 for video/sound if available.
- Blocks R13, R14, R15 entry points (they can be developed standalone and plugged in).
