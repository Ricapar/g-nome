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
- Decision: flow and content are faithful, the look is new (R11). The original layout is a
  guide, not a constraint. For example, the empty centre frame could host a live 3D scene
  (a rotating HAWC, a hangar), which suits a modern menu.

## What is already known
- Menu tree, positions, click/hover scripts and action ids: R10 (`ui_menus.json`, array 8611).
- Intro: DREAM.SMK via `script_7(2, 11)`; G-NOME.SMK / NEWS / WILKINS / CREDITS are played by
  other scripts (R8 "Smacker movies"). Credits = `script_7(3, 8390)`.
- Exit shows advert bitmap 2396 before quitting (R8 notes). The remake can drop or replace it.

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

## Dependencies
- R10 (menu map), R11 (kit). Uses R8 for video/sound if available.
- Blocks R13, R14, R15 entry points (they can be developed standalone and plugged in).
