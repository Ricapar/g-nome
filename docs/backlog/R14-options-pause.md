# R14: Options, controls and the in-mission pause menu

Status: **todo**

## Goal
Decode what the original lets the player configure (the OPTIONS submenu, key mapping,
joystick, detail level, sound) and the in-mission pause screen, then build the remake's
settings and pause menu with the R11 kit. Keep every original option that still makes sense,
and add the modern ones a PC game needs.

Done when the remake has an options screen (from the main menu and from pause) whose settings
apply live, persist across restarts, and cover the original's options plus the modern
set below; and pausing a mission opens a pause menu with the original's choices.

## What is already known (leads; verify)
- OPTIONS = array **8624**: four entries with click scripts **8380-8383** (action ids 20-23).
  8380 = `script_8353(0, 1, 0)` + `script_6324()`; the others are not read yet.
- Key setup: `script_8394` runs 18 × `s6d n` (n = 0..19), presumably resetting or defining
  action keys. RENDER.R32 natives: `MapActionKeys`, `CaptureKey` (rebinding?),
  `CheckActionState` (33 uses, the gameplay input query), `EnableJoystick`,
  `RangeJoystickAxis`. `[Input] Timeout` and `MaxJoySticks` come from `7THLEVEL.INI`.
- Pause: `SetPauseScript(8395)` (444 bytes) is installed at menu start; `Pause3D`/`Resume3D`,
  `PauseTimers`, `DSPauseAudio`.
- Detail: `G2117` picks the far clip 3000/5000/7000 (`script_2529`); fog and LOD
  (`UpdateLOD`) probably follow it too.
- Volume and music: CD audio via MCI (no music on the disc image; patch backlog P5).

## Plan
1. Disassemble 8380-8383 and their pages: list every option, its range, its global and how it
   is saved (INI? save file?). Screenshot each page in the original (windowed).
2. Disassemble 8395 (pause): which choices (resume, options, abort mission, quit?) and what
   each does.
3. Disassemble the `s6d` table and `MapActionKeys` / `CaptureKey` use: produce the full
   **action list** with default keys (this also feeds R5's InputMap).
4. Godot:
   - `settings.gd` autoload backed by `ConfigFile` in `user://settings.cfg`; apply on change.
   - InputMap actions named after the original actions, default bindings from step 3;
     a rebinding UI (keyboard + gamepad) with conflict detection.
   - Video: window mode, resolution, VSync, frame cap, render scale/FSR, FOV, UI scale
     (`content_scale_factor`), detail presets mapping G2117's three levels onto modern ones.
   - Audio: master/music/SFX/voice buses.
   - Gameplay: the original's options (from step 1), mouse sensitivity/invert, subtitles.
   - `pause_menu.tscn` over the mission (`get_tree().paused`, `process_mode` set for UI).
5. Document the options and action list in analysis.md.

## Verification
- Every original option has a counterpart (or a written reason why not) in a table in this spec.
- Settings persist and apply live (screenshots before/after at two resolutions; UI scale works at 12:5).
- Rebinding works for keyboard and gamepad (user check).
- Pause stops gameplay, audio and timers, and resume continues exactly.

## Open questions
- Where did the original store options: `7THLEVEL.INI`, the save file or nowhere?
- Are there difficulty settings? (Look in the options pages and the mission scripts.)

## Dependencies
- R11 (kit), R12 (entry from the main menu). Pause menu needs R5 (a mission to pause).
- Feeds R5 (input action list) and R17 (HUD options, e.g. colour/scale).
