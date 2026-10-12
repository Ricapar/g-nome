# Remake backlog (Goal 2, `remake/`, branch `remake`)

**This is the active backlog.** The patch backlog (`PATCH-BACKLOG.md`) is parked.

Each item has its own spec in `docs/backlog/`. A spec is meant to be enough to start the work
in a fresh session: background, what is already known (with file paths and addresses), the
steps, how to verify, and what is still open. Read `CLAUDE.md`, `remake/README.md` and the
item's spec first.

Status: `todo`, `active` or `done`. Update the status here and in the spec when it changes.

UI track (added 2026-10-12): R10 → R11 → R12 → R16 → R17, with R13, R14 and R15 after R12.
It runs alongside the gameplay track. R11 (design system) can start any time; R17 needs R5.

Recommended order (gameplay): R1 → R0 → R2 → R3 → R5 → R4 → R6 → R7. R8 and R9 can be slotted in
anywhere.
- R0 fixes data bugs that R3, R5 and R6 rely on, notably swapped vehicle categories in
  `units.json`.
- R4 comes after R5 if R3 confirms that movement is parameter-driven, as the R3 and R4
  research suggests. Otherwise it comes before R5.
- R2 can swap with R1: its telemetry gives exact numbers to confirm R1's fix. R1's
  screenshot check doesn't need it.

| ID | Item | Spec | Status |
|---|---|---|---|
| R0 | Fix exporter data bugs (category swap, bounds) and fold spec findings into analysis.md | [R0-data-fixes.md](backlog/R0-data-fixes.md) | todo |
| R1 | Fix mission viewer orientation against the original (heading/handedness) | [R1-orientation.md](backlog/R1-orientation.md) | done |
| R2 | Telemetry hook: log player/entity state per tick from the original game | [R2-telemetry.md](backlog/R2-telemetry.md) | todo |
| R3 | Decode HAWC and soldier movement in RENDER.R32 and the unit scripts | [R3-movement.md](backlog/R3-movement.md) | todo |
| R4 | Decode FRME animations and export them to glTF | [R4-frme-animations.md](backlog/R4-frme-animations.md) | todo |
| R5 | Mission 1-1 sandbox in Godot: walk as soldier, commandeer, drive a HAWC | [R5-sandbox-1-1.md](backlog/R5-sandbox-1-1.md) | todo |
| R6 | Weapons: decode weapon table (array 1281), projectiles and damage | [R6-weapons.md](backlog/R6-weapons.md) | todo |
| R7 | AI: decode the unit AI scripts and behaviours | [R7-ai.md](backlog/R7-ai.md) | todo |
| R8 | Remaining exporters: sprites/UI, waves, Smacker video | [R8-exporters.md](backlog/R8-exporters.md) | todo |
| R9 | Per-world colours for scenery other than rocks in the mission viewer | [R9-scenery-palettes.md](backlog/R9-scenery-palettes.md) | todo |
| R10 | UI: decode the original menu system (screens, buttons, actions, sprites) | [R10-menu-decode.md](backlog/R10-menu-decode.md) | todo |
| R11 | UI: design system and Godot UI foundation (theme, components, vector + hi-res) | [R11-ui-foundation.md](backlog/R11-ui-foundation.md) | todo |
| R12 | UI: front-end menu shell in Godot | [R12-menu-shell.md](backlog/R12-menu-shell.md) | todo |
| R13 | UI: briefing, debriefing, campaign progression, save/load | [R13-briefing-campaign.md](backlog/R13-briefing-campaign.md) | todo |
| R14 | UI: options, controls/rebinding, pause menu | [R14-options-pause.md](backlog/R14-options-pause.md) | todo |
| R15 | UI: the Lab (vehicle database, trivia, 3D turntable) | [R15-lab.md](backlog/R15-lab.md) | todo |
| R16 | HUD: decode the original cockpit HUD elements and views | [R16-hud-decode.md](backlog/R16-hud-decode.md) | todo |
| R17 | HUD: the remake HUD and cockpit views | [R17-hud.md](backlog/R17-hud.md) | todo |
