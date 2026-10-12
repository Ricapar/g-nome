# Remake backlog (Goal 2, `remake/`, branch `remake`)

**This is the active backlog.** The patch backlog (`PATCH-BACKLOG.md`) is parked.

Each item has its own spec in `docs/backlog/`. A spec is meant to be enough to start the work
in a fresh session: background, what is already known (with file paths and addresses), the
steps, how to verify, and what is still open. Read `CLAUDE.md`, `remake/README.md` and the
item's spec first.

Status: `todo`, `active` or `done`. Update the status here and in the spec when it changes.

Recommended order: R1 → R0 → R2 → R3 → R5 → R4 → R6 → R7. R8 and R9 can be slotted in
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
| R1 | Fix mission viewer orientation against the original (heading/handedness) | [R1-orientation.md](backlog/R1-orientation.md) | todo |
| R2 | Telemetry hook: log player/entity state per tick from the original game | [R2-telemetry.md](backlog/R2-telemetry.md) | todo |
| R3 | Decode HAWC and soldier movement in RENDER.R32 and the unit scripts | [R3-movement.md](backlog/R3-movement.md) | todo |
| R4 | Decode FRME animations and export them to glTF | [R4-frme-animations.md](backlog/R4-frme-animations.md) | todo |
| R5 | Mission 1-1 sandbox in Godot: walk as soldier, commandeer, drive a HAWC | [R5-sandbox-1-1.md](backlog/R5-sandbox-1-1.md) | todo |
| R6 | Weapons: decode weapon table (array 1281), projectiles and damage | [R6-weapons.md](backlog/R6-weapons.md) | todo |
| R7 | AI: decode the unit AI scripts and behaviours | [R7-ai.md](backlog/R7-ai.md) | todo |
| R8 | Remaining exporters: sprites/UI, waves, Smacker video | [R8-exporters.md](backlog/R8-exporters.md) | todo |
| R9 | Per-world colours for scenery other than rocks in the mission viewer | [R9-scenery-palettes.md](backlog/R9-scenery-palettes.md) | todo |
