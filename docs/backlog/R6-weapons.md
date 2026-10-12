# R6: Weapons: weapon table (array 1281), projectiles, hit detection and damage

Status: **todo**

## Goal
Produce a data definition per weapon (id, name, class, damage, range, rate of fire / recharge,
projectile speed and gravity, ammo, guidance, splash, shield effects, projectile template,
impact effects, sounds) and the damage rules (shields, per-part health, splash, kill credit),
recovered from the original scripts and RENDER.R32. The remake uses them to implement weapons
faithfully, and the mission 1-1 sandbox (R5) can then shoot the Merc raid party. Deliverables:
a decoder (`tools/export_gamedata.py` → `weapons.json` in `remake/game/_import/data/`), notes in
`docs/analysis.md`, and enough rule detail that a Godot weapon/damage module can be written.

## Background
- The remake's rule is "gameplay numbers come from the original code" (`remake/README.md`,
  Decisions). Weapons are the core of combat, and R5 needs them for the 1-1 slice.
- Most weapon logic is **script bytecode**, not native code. RENDER.R32 natives move projectiles,
  test collisions and tick recharge timers, then call back into scripts through a callback table.
  So most of the work is reading the script listing. REA/Ghidra is needed only for the natives.
- Unit init scripts mount weapons with `script_1656(obj, weapon_id, ammo, hardpoint)`, which
  reads the weapon table, **type-11 array 1281** (`docs/analysis.md`, "Missions, units and layouts").

## What is already known

### Tools and commands (facts)
- Arrays: `res7l.read_array(bin_path, ent)` → `(dims, flat int list)` (`tools/res7l.py`; header
  0x3c bytes, RTLIB loader `FUN_1001218d`). Scripts read them with `ArrayGet(array, i, j)`, row-major.
- `tools/export_gamedata.py <G-NOME.BIN> remake/game/_import` already dumps every array
  (`arrays.json`), units + codex (`units.json`, LABTEXT.DAT parser `labtext()`), layouts and strings.
- Script listing: `.venv\Scripts\python -I tools/script7l.py ISO/G-NOME/G-NOME.BIN > %TEMP%\scripts.txt`
  (~32k lines). Native names (call id − 0xFA = index into key 11) come from `script7l.Names`.
- RENDER.R32 export addresses: `pefile` on `ISO/G-NOME/RENDER.R32` (image base 0x10000000).

### Array 1281 shape and column map (from the script listing, 2026-10-12)
32 rows × 25 int32 columns. Column 0 is the weapon id (1..32). `script_1660(id)` scans the 32
rows for the matching id and returns the row. Scripts store and pass the **row**, not the id.
"Fact" = read directly from a script. "Hyp." = an interpretation still to confirm.

| Col | Meaning | Evidence |
|---|---|---|
| 0 | weapon id 1..32 | fact: 1660, 1683 (projectile prop 58 = row → id) |
| 1 | class: 1 energy, 2 gun, 3 guided missile, 4 rocket | fact: picks HUD sprite set (1637/1642/1643 via array 1635). Class 1 has no ammo and charge-scaled shots (1682). Names are hyp., based on codex |
| 2 | ? (values 1..4) | not read by any script. Check the natives |
| 3, 14 | always 0 | unused? |
| 4 | guided flag | fact: 1679 sets projectile prop 45 = target when col 4 is set (via 1674) |
| 5 | projectile speed | fact: prop 35, `SetVelocityForward`, 2062 (1682) |
| 6 | damage | fact: prop 46. Get/set at runtime by 1672/1673 (upgrades?) |
| 7 | reload / recharge time | fact: mount timer col 5 = col 7 after a shot. Class-1 charge = (col7 − timer)/col7 |
| 8 | recharge modifier | fact: 1681 `dt' = (arg − col8*5) * dt / 300`, min 5. Meaning hyp. (power draw) |
| 9 | projectile factory script (1691..1707) | fact: `script_L9(x,y,z)` clones an OPRT template (1245/1260/1263/1266/1269/1272), `AddObject`, `SetRadius`, 2066/2067 |
| 10 | gravity | fact: `SetGravity` (guns strongly negative, missiles slightly, energy 0) |
| 11 | fire sound (wave id) | fact: `DSLoadWave`, `ObjectPlayWave` (volume 100 for the player, 10 otherwise) |
| 12 / 13 | min / max range | fact: 1667 range test (AI), laser-sight paint range (1648), HUD lock (1643) |
| 13 / (5/10) | lifetime | fact: prop 44 = col13 / (col5/10) * 100 (1682) |
| 15 | shield-resist factor → prop 50 | fact: formula in 1708, see Damage. Hyp.: "how much shields stop it" |
| 16 | shield drain → prop 52 | fact: `script_2058(target, -prop52)`. Hyp. supported by data: the "anti-shield" weapons (CETI, GRAY7) are among the highest |
| 17 | second-pool damage → prop 51 | fact: split in 1709. Hyp.: armour-piercing part |
| 18 | splash damage → prop 53 | fact: 1689 → `script_1690(proj, prop53, flag, prop54)` → `script_2300(victim, dmg, dmg, 0, team)` |
| 19 | splash radius → prop 54 | fact: 1690 compares `ObjectDistance` against it |
| 20 / 21 / 22 | impact effect templates | fact: 1881 picks 20 when hit category == 0; 21 when −1 or >240 (≠270), with 2534 replaced per world (`G1852` → 1858/1864/1861/1867); otherwise 22. Spawned by `script_1882`. Preloaded with 1655 (Clone → prop 3 wave → `DSLoadWave`) |
| 23 | ammo base | fact: default ammo = col23*1.5 (1659). Resupply cap = 2*col23 (1671). HUD ammo bar scale (1643) |
| 24 | network object type | fact: `NetDPSendCreDO(..., col24, 11)` (1679) |

### Weapon id → name (fact)
`script_1716` (HUD name) switches on the weapon id and draws a key-4 string by byte offset
(`0x8000 | offset`; `0x811e` = "????", `0x8123` = "FIL-30", ...; confirmed against the key-4 block).
1 FIL-30, 2 P2MEC, 3 FLECH, 4 SAG/5T, 5 3cROCK, 6 3cREAP, 7 VISOM, 8 GRAY7, 9 PUG, 10 CHUM,
11 DASY, 12 AIM-9, 13 HOMP11, 14 RUPP, 15 HSSO, 16 SREM, 17 LRIP, 18 CETI, 19 RAID, 20 zWASP,
21 UNKPA, 22 GAUS30, 23 GAUS20, 24 PRIF44, 25 EGGR, 26 GASHR, 27 ECMp, 28 POPPR, 29 ARC-M,
30 WaRT, 31 TAR-12, 32 LaserSite. The class column agrees: lasers and cannons are class 1, guns
class 2, missiles 3/4. The special cases agree too: 7 VISOM = fly-by-wire missile camera in 1682;
32 = laser sight (no projectile, 1648, "Paint lab with laser sight"); 25/26 = infantry EGGR/GASHR,
handled separately in 1709. `LABTEXT.DAT` also holds a weapon glossary (e.g. "CETI / Scorp Tau
Ceti Anti-Shield Med-Range Laser"), which gives each weapon's intended role.

### Mounts and firing (facts from scripts)
- Per-unit mount array: `Clone(1282)` (8×9) in `script_1653` → prop 66, count prop 67 (max 8).
  Row = `[weapon id, 1281 row, enabled, ammo, hardpoint, recharge timer, ?, ?, ?]`.
- `script_1656(obj, id, ammo, hardpoint)` adds a mount and rejects hardpoint > prop 102 (hardpoint
  count). It preloads the sounds and effects (cols 11, 20–22) and calls the col-9 factory once.
  1657/1658 swap a mount's weapon (pickups), 1666 disables a hardpoint, 1671 resupplies.
- Hardpoint table: prop 89 (e.g. array 2582, 3×6×5 for the Prowler): `[prop 92 state][hardpoint]
  [clump (1000 = none), ?, 3 OrientModels args]`. 1682 aims the projectile with `OrientModels`.
- Loadouts match the codex. E.g. Prowler (2631): FLECH 200 rounds at hardpoints 0 and 4, FIL-30
  at 1 and 5. Energy weapons get a dummy ammo of 2000 (600 in one case). Hyp.: hardpoints 4–7
  hold the second gun of a pair (the HUD only draws hardpoints < 4).
- Player input: `script_1974` maps actions 29..32 ("Fire Weapon 1-4") to `script_1675(player,
  N, G974 target, 1)`. That finds the weapon at hardpoint N and fires **every** mount with the same
  weapon id (1678 → 1679 → 1682). AI firing decision: `script_1677` (called from 2020–2027;
  belongs to R7, but it shows range, facing (`DotProduct` > 9200/9700) and `Random` gating).
- `script_1682` (fire): needs enabled and ammo > 0. Class 1 fires only above 30 % charge and
  scales damage, drain and lifetime by the charge. Ammo is decremented when class ≠ 1, or for
  ids 25/32. The projectile spawns at the shooter's position. Sets prop 42 = shooter, 58 = row,
  35/46/50/51/52/53/54/44, `SetGravity`, and turn limits `SetMaxAngularVelocity(4500,1100,4500)`
  / `SetMaxAngularAccel(2900,700,2900)` (homing). Registers the projectile in the 500-slot list
  `G1277` (1685).

### Projectile runtime and hits (facts unless marked)
- Callback table `G1861` (set in `script_2564`, passed to the natives): [0] 2228 hit, [1] 1689
  projectile end, [2] 1683 weapon id, [3] 1681 recharge tick, [4] 2055 stat-B change, [5] 2058
  stat-A change, [6] 430 sector lookup (array 427, 26×26 cells of 1200 units over ±15600).
- Natives (RENDER.R32 export addresses, not decompiled yet): `Projectile_Update` 0x10028170
  (script 1734 ← 1741), `Process_Sector_Collisions` 0x100289d0 (437 ← 1728),
  `Decrement_Recharge_Timers` 0x100286ab (1680 ← unit update 1723/1727), `StopProjectileObject`
  0x10023f7f, `CollisionClump` 0x10010dbc, `DeflectHotspot` 0x1002421e, `DeflectObject` 0x10023dac,
  `FastmovingHotspotCollide` 0x1002447f, `CollideHotSpot` 0x10023803, `DefaultClumpHealths`
  0x100089ca, `AmputateClump` 0x10007152, `ExplodeModel` 0x10012142, `OrientModels` 0x10007ccd,
  `SetGravity` 0x1001662f, `SetVelocityForward` 0x10017516, `DamageRect` 0x10011acb (unused by scripts).
- `script_2228(proj, target, hotspot)` ignores targets with category (prop 0) 260 or ≥ 300
  (projectiles are 301–304) and the shooter itself. Hotspot hits go to 2238 (switch on hotspot
  type). Otherwise `CollisionClump` → clump; `StopProjectileObject`; `script_1709(target, clump,
  proj)`; kill-credit 2323/2325 (arrays 2316/2317, 41×41); prop 62 = last attacker; then 1689.
- `script_1689`: on end with hit category −1, projectile categories 301–304 cause splash (1690).
  Splash only damages objects with category < 100 (infantry) in list `G1816`.

### Damage rules (facts from 1708/1709/2058/2291/2292/2300; meaning partly hyp.)
- Props 97/94 = stat A current/max (`script_2056`), 95/98 = stat B (`script_2057`). These are the
  codex's two numbers (e.g. Prowler 35 / 1600).
- `1708`: `r = prop50 * (97*100/94) / 100`; `d = dmg - dmg*r/100`, so a fuller stat A reduces damage more.
- `1709`: `2058(target, -prop52)` drains stat A. Then `a = d - prop51`, `b = prop51`, and if
  `a < 0` then `b += a; a = 0`. Ids 25 → `script_1711` and 26 → `script_1715` (special). Screen
  shake for the player on projectile types 301/302. Then `2291(target, clump, a, b, team)`.
- `2291`/`2292`: per-clump health array prop 85, seeded by `2286` from `DefaultClumpHealths(model,
  clump)` × percentages. Damage `b` hits col 1 and overflows into `a`; `a` hits col 3. Then `2294`
  (2182 bytes, not read yet), per-clump death scripts (prop 84 col 3; 2302–2304 special),
  `AmputateClump` (2298), `ExplodeModel` (2278/2297), `NetDPSendDamage`.
- `2300(obj, a, b, flag, team)` damages a random eligible clump (used by splash and scripted
  kills, e.g. script 8723).

### Mission 1-1 needs (from `layouts.json` 8743)
Player = Union infantry (2834 → 2842: PRIF44 + GASHR ×5). One Prowler (FLECH, FIL-30). Merc raid
party = 2 Ogre (3108 → 3119: RAID ×2, CHUM 25) and 3 Minotaur (3165 → 3177: RAID, DASY ×2, SAG/5T
×2). Weapons needed first: 24, 26, 3, 1, 19, 10, 11, 4.

## Plan
1. Re-derive the column map above from a fresh listing. For each column, note every script that
   reads it, so that each "hyp." can be closed.
2. Add a `weapons` export to `tools/export_gamedata.py`: rows of 1281 → named fields plus the
   name (the 1716 table, or key-4 strings 41..72 in id order), the factory script's OPRT template
   (parse the col-9 script for `Clone(n)`, `SetRadius`, 2066/2067 args) and that template's model.
   Also export per-unit loadouts by scanning each catalogue init script's setup script for
   `script_1656` calls. Join the loadouts with the codex weapon lines and report mismatches.
3. Read the remaining scripts: 2294, 2286 (and who calls it with which percentages), 1711/1715,
   1881/1882, 2238/2239 (hotspot types), 2323/2321 (kill credit). Name props 35–58, 84–89, 92, 102.
4. RENDER.R32 with REA (after the parallel agents release it): decompile `Projectile_Update`,
   `Process_Sector_Collisions`, `Decrement_Recharge_Timers`. Goals: the time units (ticks vs ms)
   for speed, lifetime and recharge; how guidance uses prop 45 and the turn limits; gravity
   integration; which callback fires on expiry or ground hit (the −1 category); the hit test
   (sphere radius from `SetRadius` vs clump boxes). Then `CollisionClump`, `DefaultClumpHealths`.
5. Write a units section: game units/100 = model units, 600 = one tile (`docs/analysis.md`). Turn
   speeds into m/s once R2/R3 fix the tick rate.
6. Write the rules up in `docs/analysis.md` and as a Godot-ready spec (data file + damage
   function pseudocode) for R5.

## Verification
- `weapons.json` has all 32 rows with names. Every column used by a script is named, and the
  remaining unknowns (cols 2, 3, 14 and anything still hypothetical) are listed.
- The loadout export agrees with the LABTEXT weapon lines for every vehicle, or each mismatch is
  explained.
- Telemetry (R2): in the original, fire each 1-1 weapon at a stationary target. Log the projectile
  position per tick (speed, gravity, lifetime) and the target's props 97/98 and clump health
  before and after. The remake formula must reproduce these numbers exactly (integer maths).
- Side-by-side screenshots (`tools/dev/drive.ps1`, windowed): rate of fire and HUD ammo/charge
  bars match over a 10 s burst. The user judges the sound and feel.

## Open questions / risks
- **Stat A vs B naming.** An earlier session called 97/94 "armour" and 95/98 "shields". The damage
  scripts make 97/94 behave like shields (scales the reduction, drained by col 16). Also,
  `script_1723` resets 98 to 95 on every update for non-player units. Settle with telemetry.
- Time base of speed (col 5), recharge (col 7) and the native tick. Integer fixed-point scaling.
- Col 2 is read by no script. It may be read by a native, or unused.
- The difficulty factor `G2114` in AI fire rate (1677), and upgrades via 1673 ("Shield Doubler"
  supply in 4-3).
- Multiplayer paths (`G982`, NetDP*) are skipped for now (P7).
- REA is shared with parallel agents: coordinate before opening RENDER.R32.

## Dependencies
- R2 (telemetry) for verification and time units. R3 (movement) for the tick rate and units.
- R5 consumes the output. R7 (AI) shares `script_1677` and target selection.
- R4/R8: impact effects, explosions and HUD sprites (arrays 1634/1635) need the FRME, sprite and
  wave exporters for the final look. They're not needed for the numbers.

## Notes to fold into analysis.md
- The array 1281 column map, the weapon id → name table (script 1716, key-4 offsets `0x8000|off`),
  the mount array layout (1282) and the callback table `G1861` (script 2564).
- **Catalogue categories 161 vs 181/182 look swapped.** In all four factions, the category-161
  rows (labelled hovercraft) mount the codex *armoured support* loadout and stats, and the
  181/182 rows mount the *hovercraft* ones. Examples: row 3 (2762 → 2775) sets 20/1900 and
  ARC-M + 3cREAP = Rapier; row 16 (3329 → 3342) = Legionnaire-like; row 15 (3291 → 3304) sets
  18/1400 = Razor. So `CATEGORY`/`CODEX_MATCH` in `export_gamedata.py` (and the analysis.md list)
  probably have 161 and 181/182 reversed, which mis-joins `units.json`. Check against the models.
- Script loadouts differ from the codex in a few places: Razor ammo 500/510 vs codex 100/110,
  Legionnaire zWASP vs codex FLECH, Scorpion has no HSSO, and some stat-B values differ
  (e.g. 2805: 1000 vs codex 800). Scripts are authoritative for gameplay.
- Sector grid for collisions: array 427 (26×26, 1200-unit cells, origin −15600), script 430.
