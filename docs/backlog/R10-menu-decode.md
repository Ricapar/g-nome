# R10: Decode the original menu system (flow, content, behaviour)

Status: **todo**

## Goal
A complete, machine-readable map of the original's front end: every screen, button, submenu,
hover text, sound and action, and how they connect. Output `remake/game/_import/data/ui_menus.json`
(gitignored, from a new `tools/export_ui.py`) plus a written screen map in `docs/analysis.md`.
This is the **reference** for the new UI (R11, R12). The original's bitmaps are not reused
as UI art (see `remake/README.md`, "UI"), so this item is about structure and behaviour, not pixels.

Done when the JSON lists every screen reachable from the main menu, each button's position,
label, hover/status text and action, and a reference screenshot exists for each screen.

## Background
- Decision (2026-10-12): the remake UI is new, built Godot-native from scratch. The original
  menu flow and content stay faithful (`remake/README.md`, "Decisions"), so we need to know
  exactly what the flow and content are.
- RTLIB32 is a sprite compositor: menus are sprites placed and switched by script.
  `SpriteSendMessage` is the 4th most common call (644 uses).

## What is already known (from this session's read-only research; verify)

### Entry chain (facts from `tools/script7l.py` listing)
- Boot: `script_7(2, 11)` plays DREAM.SMK, then script 11 → `script_6005` (no save) or
  `script_5998`. 5998: `MouseOnOff(0)`, `EnableJoystick(0, G977)`, `script_8394` (key setup:
  18 × `s6d n`), `SetPauseScript(8395)`, `script_6002` (palette `sb4 2510`, shows sprites
  8399 and 8539), `script_6010` (lays out the top bar), `script_8307` (lays out the open
  submenu), `script_8315` (`DSPlayWave(8398, …)`, the menu loop sound).

### The menu table (facts)
- **Array 8611** (5 x 7) = the bottom bar. Row layout:
  `[submenu array, button sprite, x - 320, y - 240, click script, hover script, action id]`.
  GAME is `[8613, 8405, -158, 215, 8344, 8334, 0]`, so its centre is (162, 455): the
  coordinate `CLAUDE.md` already uses to click GAME. The rows are GAME, NETWORK, LAB, OPTIONS, EXIT.
- Submenus have the same 7 columns: left column at x = -279 (41), right column at +279 (599),
  rows at y = -76, -33, 11, 52 (164, 207, 251, 292). This matches the NEW/CAMPAIGN clicks.
  The tree:
  - 8613 GAME: NEW (→ 8615: CAMPAIGN 8363, TRAINING 8364, MISSION 8365), LOAD 8367, SAVE 8366, CREDITS 8389
  - 8619 NETWORK: rows → 8620 / 8621 (4 options each), third row 8369
  - 8622 LAB: 4 rows, all → 8623 (4 options: 8376-8379)
  - 8624 OPTIONS: 4 rows 8380-8383 (no submenu)
  - EXIT: action 28, click script 8349 (`script_8341(4)` + `sc4 …`)
- Column 5 (8320-8338) is a short hover script (e.g. 8334 = `script_8333(0)`), which
  probably shows the status-line text ("Start a New Game" appears in the bottom strip of the GAME screenshot).
- `script_8341(n)` selects bar entry n: plays wave 8403, runs the pending close script
  `G2056`, hides the old submenu sprite (`SpriteSendMessage(sprite, 1, …)`), sets G2053 = n
  and re-lays out with `script_8307`. G2053/G2054/G2055 = selected bar / left / right entry.
- Action ids (column 6) run 0..40 and are compared in scripts at listing lines ~1461-2449
  and 24231-24277 (search `ArrayGet(L?, ?, 6)`). Not yet mapped to meaning.

### Sprites (strong hypothesis)
- **Type 20 = sprite definition** (74-94 bytes). Word 2/3 = frame count (1, 2, 5, 6), word 7 =
  a class (1000, 3000, 3001), words 9+ hold `bitmap_id << 16`: sprite 8405 (GAME button) has
  frames 8406, 8407, 8408, ... These are button states (normal/hover/pressed/disabled?).
- `SpriteSendMessage(sprite, msg, …)`: 12 = move to (x, y), 18 = show / set frame, 8 = hide?,
  1 = close/hide. Confirm in RTLIB32 (the message switch).
- Unnamed statements around sprites: `s75 id` (load a screen/scene? 6002 uses 8605, 7265
  uses 7370), `sb9 a b` (pair of ids, e.g. 8539/8543), `s6b`, `sd9`, `s3f`, `s10`, `s0e`,
  `s71`. Their handlers are in RTLIB's statement dispatcher `FUN_1001f1f7` (see analysis.md
  "Script VM").
- Type 21 (40-byte records, word 6 → script or bitmap) may be hot spots. Type 18 records
  (e.g. 8551 = `18`) are small and unknown.

## Plan
1. **RE the sprite layer** in RTLIB32 (REA: `open_binary` RTLIB32.DLL): `SpriteSendMessage`
   message codes, and the statement handlers for `s75 sb9 s6b sd9 s3f s10 s0e s71 s3c s3d`.
   Decode type 20 fully (and 21, 18 if they're involved). Name the opcodes in
   `tools/script7l.py` so listings become readable.
2. **Walk the menu table** (8611 and children) in `tools/export_ui.py` and emit
   `ui_menus.json`: per screen, the buttons with centre, size (from frame-0 bitmap), frame
   bitmaps, click/hover scripts, action id, submenu, plus the status text and the
   sounds each script plays.
3. **Labels and status texts**: find where the hover scripts get their text (string table
   vs. bitmap text). Button labels are probably baked into the bitmaps: record them by hand
   from screenshots if so.
4. **Map action ids** to what they do (new campaign, load slot, Lab page, option page...),
   following each click script one level down. Note which ones open non-table screens
   (briefing, Lab pages, options pages, credits FMV, exit advert 2396).
5. **Reference board**: drive the original windowed (`tools/dev/drive.ps1`, no need to ask)
   through every screen and save shots to `%TEMP%`. Optionally export the screen
   bitmaps with R8 for side-by-side study. Nothing goes into the repo.
6. Write the screen map (a tree with action ids) into `docs/analysis.md`.

## Verification
- Every button in `ui_menus.json` matches a screenshot position within a few pixels.
- Every reachable screen from the main menu appears in the map; no click in the reference
  run lands on an unmapped button.
- `script7l.py` output for 5998/6002/6010/8307 reads without raw `sXX` hex for the decoded opcodes.

## Open questions
- Exact meaning of the type-20 words and the frame states.
- Whether hover texts are strings or bitmaps.
- NETWORK screens need DirectPlay (multiplayer is Phase 3; map the screens but don't go deep).
- Keyboard/joystick navigation of menus (8394 sets up keys; `MouseOnOff(0)` at menu start?).

## Dependencies
- None blocking. R8 (sprite export) helps for reference images and shares the type-20/21 work;
  whichever runs first records the format in analysis.md.
- Feeds R12 (menu shell), R13, R14, R15.

## Notes to fold into analysis.md
- Array 8611 menu table layout and tree above; G2053/54/55 selection globals; script 8341/8307.
- Type 20 = sprite with frames `bitmap << 16` (once confirmed).
