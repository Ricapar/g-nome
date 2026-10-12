# R17: The remake HUD and cockpit views

Status: **todo**

## Goal
A new, sharp HUD for on-foot and every vehicle class, built with the R11 kit (vector
instruments + hi-res materials), driven by live game state, and showing the same information
with the same behaviour as the original (R16). Includes the cockpit framing per vehicle class
and the camera view modes.

Done when the R5 sandbox shows the full HUD on foot and in a HAWC, every R16 element has a
counterpart bound to real data, and it holds up at 1920x1080, 3840x2160 and 3840x1600.

## Background
- Decision: visuals are new and MechWarrior-grade; information and behaviour are faithful.
  The original HUD lives on 640x480 sprites over a cropped 3D view. The remake should use the
  full screen for 3D and layer the HUD on top (or in 3D for a diegetic cockpit, see the open questions).
- Vector is the natural fit for instruments: compass tape, radar, reticles, lock brackets,
  bar gauges, ticks and numeric readouts all stay crisp at any resolution and animate cheaply.

## Approach (recommended)
- Scene `ui/hud/hud.tscn` (a `CanvasLayer`) with one component per R16 element type:
  `Reticle`, `TargetBrackets` (3D → screen with `Camera3D.unproject_position`), `Radar`
  (`_draw()` or a shader in a `SubViewport`; blips from a query of nearby entities),
  `CompassTape`, `WeaponList` (name, ammo pips, charge/recharge bar), `StatusPanel`
  (self/target health, armour, shields), `BarGauge` (speed/throttle/heat if they exist), readouts.
- **Data binding**: the HUD reads a small `HudModel` interface (player entity, target,
  weapons) and never the vehicle scripts directly, so it can be tested with fake data in the gallery.
- **Layout**: one HUD layout resource per vehicle class (from R16's `hud.json`, translated
  to anchors/safe areas, not 640x480 pixels). Elements keep their original *relative* placement
  where it matters (e.g. radar bottom centre), adjusted for wide screens.
- **Cockpit framing**: a 3D cockpit scene per vehicle class (diegetic, see the decision
  below), and a helmet visor on foot. Use R16's crops as a hint for sight lines.
- **Effects**: damage flicker/shake (`ScreenShake` from R16), lock-on tone, low-ammo
  blinks; emissive glow via the R11 shader approach.
- **View modes**: cockpit, chase (`AttachCamera` z = -20, height 10), zoom-out steps,
  per R16 step 4, with the HUD variant for each.
- HUD options from R14: scale, opacity, colour scheme (colour-blind safe), radar orientation if the original allowed it.

## Plan
1. Design pass with the R11 direction: HUD style frames on top of a sandbox screenshot (user review).
2. Build the components in the R11 gallery with fake data and animated test values.
3. Implement `HudModel` against the R5 sandbox entities; bind on-foot and HAWC layouts first.
4. Radar and target brackets with real entities; weapons once R6 exists (stub data before).
5. View modes and per-class layouts for the rest of the vehicles.
6. Screenshot mode (`--shots`) for the sandbox with HUD at the three resolutions.

## Verification
- Side-by-side with the original's reference shots (R16): same information present and
  behaving the same (e.g. ammo drops by one per shot, radar blip bearing matches, compass
  letter under the marker matches the heading).
- Crisp at 4K and 12:5 (zoomed crops), readable at 1280x720.
- Frame cost: HUD under ~0.5 ms at 4K (Godot profiler).

## Decision (user, 2026-10-12): diegetic 3D cockpits
- Instruments live on the cockpit model (screens, lamps, gauges, counters), in the spirit of
  *Star Wars: Squadrons* (`remake/UI-DESIGN.md`). Build each instrument as a 3D mesh whose
  display is a `SubViewport` texture or a shader driven by `HudModel`, so the same
  components also render as an optional 2D overlay ("HUD on" setting).
- Reticle: project onto a plane at the distance of the object behind it, scaled to a
  constant apparent size (the Squadrons approach).
- On foot: a helmet visor with projected elements. Vehicles: one cockpit scene per class, with
  readouts placed on the same side as their controls.
- Keep green phosphor as the default instrument colour.

## Open questions
- Cockpit art per vehicle class (new models): scope and order, starting with the Union HAWC
  the player commandeers in 1-1.

## Dependencies
- R16 (what to show), R11 (kit), R5 (sandbox with a player and a HAWC). R6 for weapons, R7 for
  target data, R14 for HUD options.
