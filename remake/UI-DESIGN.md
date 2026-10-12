# G-Nome remake: UI design direction

Status: agreed with the user on 2026-10-12 (backlog R11). The reference screenshots come from
the original, captured windowed with `tools/dev/drive.ps1` into `%TEMP%\ui_ref` (not in the repo).

## Decisions
| Topic | Decision |
|---|---|
| Direction | **Keep the original's visual identity**, rebuilt sharp and modern: red painted-metal machinery with hazard stripes, blue glass indicator panels, green phosphor text, light brushed-steel push-buttons. |
| Menus | **2D UI** (Godot `Control`s) laid out like the original: a pillar on each side, a centre "screen", a status strip and a bar of push-buttons at the bottom. The centre screen can host a **3D scene** (`SubViewport`), for example the Lab turntable, the briefing target, or an idle vehicle. |
| Cockpits | **Diegetic 3D**: instruments are part of each cockpit model (see R17). A 2D HUD overlay exists only as an option. |
| Fonts | **Saira** (OFL, variable: width 50-125, weight 100-900) for all UI text, plus **Share Tech Mono** (OFL) for phosphor readouts. Both live in `game/ui/fonts/` with their licences. |
| Technique | Vector shapes (SDF shaders, `StyleBoxFlat`, SVG via `DPITexture`, MSDF fonts) combined with high-res material textures. No original bitmaps are used as UI art. |
| Reference | The original game first. Second: *Star Wars: Squadrons* (Motive, 2020) for its cockpit and instrument thinking. |

## The original, screen by screen (what the remake must keep)
- **Frame** (all screens): left and right pillars of red machinery. Each pillar has four slots
  that are blue glass when empty and turn into green glass buttons when a menu fills them.
  In the centre is a large dark screen with a grey-blue bezel and clips on top. Below it, a
  status strip shows yellow help text, flanked by a yellow cable coil on the left and a blue
  one on the right. The bottom bar has five steel push-buttons (GAME, NETWORK, LAB, OPTIONS,
  EXIT), each with an LED that lights green when its menu is selected.
- **Submenus**: the selected bar button fills the left slots. A left entry can fill the right
  slots, and the active entry turns teal-filled. For example, GAME → NEW/LOAD/SAVE/CREDITS,
  and NEW → CAMPAIGN/TRAINING/MISSION.
- **Lab**: VEHICLES/STRUCTURES/PERSONNEL/WEAPONS on the left, DARKEN/HUMAN/MERC/SCORP on the
  right. The screen shows a title, a rotating model on the left, a stat list on the right
  ("Class:", "Nickname:", "Max Speed:", ...), a rule, the armament list, and prev/next arrows.
- **Options**: INTERFACE (load/save a configuration, a key-mapping grid with 3 mappings per
  function, joystick on/off), DIFFICULTY (Easy/Medium/Hard), SOUND (CD Music on/off,
  SFX/Dialogue on/off) and DETAIL (High/Medium/Low). Choices use triangle radio markers.
- **Briefing**: the mission title "1-1: Renegade Mercs"; a green-framed split screen with a
  terrain map and waypoints on the left and a rotating target model on the right; the
  objectives as clickable bullet points ("[Click on bulletpoint to review]"); and the Union
  Intelligence Agency logo card. LAUNCH sits in the right column.
- **Network**: HOST/JOIN/PROTOCOL.
- **Cockpit (on foot, 1-1)**: helmet visor frame, weapon list top centre, compass tape bottom
  left, green crosshair, numeric readout under the visor.

## Palette (sampled from the original, then cleaned up)
| Token | Hex | Use |
|---|---|---|
| phosphor | `#00ff00` | text on glass, LEDs, HUD (the remake softens it to `#39ff5a` with glow) |
| phosphor_mid / dim | `#00c500` / `#009800` | secondary text, inactive marks |
| glass_dark | `#06100a` | empty or unselected button glass |
| glass_active | `#196955` | selected button fill (teal) |
| red_hi / red / red_lo | `#ad5f5b` / `#912f2b` / `#6e2622` | painted machinery |
| blue_glass / hi / lo | `#272d90` / `#4a51a8` / `#12248f` | empty slots, indicator panels |
| bezel / bezel_hi | `#465855` / `#6e748c` | centre screen frame |
| steel / steel_hi / steel_lo | `#bbb8bb` / `#c5bfc0` / `#8d8b89` | bar push-buttons |
| iron / iron_hi | `#262522` / `#3c4238` | dark machinery, recesses |
| status | `#ffff00` | status strip text |
| hazard / rust | `#a5881a` / `#6d4739` | hazard stripes, wear |

## Typography (Saira variations; tags `wdth`, `wght`)
| Role | Variation | Notes |
|---|---|---|
| Bar button label | width 125, weight 800, caps | Matches the original's embossed extended caps. Engraved look: dark text with a 1px light lower edge. |
| Glass button label | width 75, weight 700, caps | Green with an outer glow. Uses the same squarish bowls as the original. |
| Screen title | width 100, weight 600 | e.g. "Darken Sentry HAWC", "1-1: Renegade Mercs". |
| Body / data | width 87, weight 500 | Stat lists. Labels at weight 700. |
| Status strip | width 100, weight 500 | Yellow. |
| Readouts / HUD | Share Tech Mono | Ammo, counters, coordinates. |

## Shapes, materials, motion
- **Shapes** are vector: chamfered or rounded rects drawn with SDF shaders, so bevels, edges
  and glows stay crisp at 4K and on 12:5 ultrawide.
- **Materials** are textures: painted metal, brushed steel, glass and grime. The first pass is
  procedural noise generated at high resolution; authored 4K maps replace it later through the
  same shader uniforms.
- **Motion** borrows the original's mechanical feel: buttons slide or light into slots, LEDs
  snap on, and the screen powers on with a short scanline sweep. Short tweens (80-200 ms) only.
- **Sound**: hover and press clicks plus the original's selection wave (8403) and menu loop
  (8398) as placeholders (R8).

## From Star Wars: Squadrons (inspiration, not copying)
Sources: EA Motive, "The making of VR, part 1"
(https://www.ea.com/studios/motive/news/the-making-of-vr-part-1); PC Gamer on HUD
customisation
(https://www.pcgamer.com/au/star-wars-squadrons-will-have-customizable-hud-controls-and-cosmetic-displays).
- **Instruments are physical cockpit parts**: radar, target info, threat warnings, damage,
  ammo and speed live on screens, lights, gauges and counters in the cockpit model. A flat
  HUD is an option for casual players, and an "instruments only" mode turns it off. → R17.
- **Designed like a 1970s physical prop**: ask how a real model-maker would build the
  readout (e.g. a laser charge meter as lamps), not just "add a light". This suits G-Nome's
  chunky machinery.
- **Readable without turning the head**: critical information sits in the view centre or
  near periphery. On flat screens it must fit the visible "safe area" of the cockpit view.
- **Reticle**: projected onto a plane that snaps to the distance of whatever is behind it
  and rescales to a constant apparent size. This avoids depth conflict (and eye strain in VR).
- **Controls mirror readouts**: primary and secondary weapon displays sit on the same sides
  as their controls.
- **Per-ship layouts**: each cockpit has its own projection layout for floating elements so
  nothing intersects the geometry.
- **Hangar and briefing room** are 3D story spaces in Squadrons. For G-Nome we keep the 2D
  frame and put 3D only inside the centre screen (decision above).
