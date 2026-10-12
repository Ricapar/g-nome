# R2 — Telemetry hook: log player/entity state per tick from the original game

Status: **todo**

## Goal
Add a switchable telemetry logger to the running original game. Each game tick it writes the
player's state (and, as a second stage, every active entity's state) to a file: position,
heading, speed, state and the current inputs. The remake (Godot) produces the same format, so
runs can be compared numerically. R1 (orientation) and R3 (movement) are checked against it.

## Background
- `remake/README.md` ("Decisions"): gameplay numbers must come from the original code, and
  "a telemetry hook in the original game provides reference runs to compare against". Roadmap
  Phase 0 item 6 and Phase 2 (vertical slice compared side by side and against telemetry).
- Earlier session plan: log positions, health and AI state each tick, then feed the same
  inputs to the remake and compare, so "feels like the original" becomes a measurable diff.
- Game logic runs in script bytecode (RTLIB VM) plus RENDER.R32 natives. There is no single C
  "update loop" to hook. The useful hook points are the natives the scripts call.

## What is already known (facts, with sources)

### How gnomefix hooks things (`patch/gnomefix.c`)
- `ddraw.dll` proxy. `DllMain` → `patch_game_modules()` patches the IATs of the modules in
  `game_modules[]`, and `hLoadLibraryA`/`DirectDrawCreate` re-run it for later plugins.
  `hooks[]` entries carry a `where` mask: `ALL`, `RT` (rtlib32 only), `RW` (RenderWare DLLs),
  `WIN` (windowed only). **render.r32 is passed kind 0, so it only gets `ALL` hooks**; a new
  kind is needed to hook RENDER's own imports.
- **Native interception (the model to follow):** RTLIB resolves script natives with
  `GetProcAddress` on the `.r32` plugins. `hGetProcAddress` (RT only) swaps in
  `hSetCameraClipping`/`hSetFogDepthColor`. Natives are **`__cdecl`, first arg = a context
  pointer, then the script args as ints** (`int __cdecl f(void *ctx, int a, int b)`).
  Caveat: `hGetProcAddress` returns early when `cfg.drawdist == 100`. Telemetry must
  restructure that test.
- Resolution happens when the plugin loads (boot). A DLL injected later with
  `tools/dev/inject.exe` misses it. It would have to patch RTLIB's native table instead (see
  below) or inline-hook RENDER exports. **So build telemetry into gnomefix**, not a separate
  DLL.
- Config: `load_config()` reads `[gnomefix]` keys from `7THLEVEL.INI` with
  `GetPrivateProfileIntA`. `logf()` appends to `%TEMP%\gnomefix.log` but opens and closes the
  file on **every call**, which is too slow per entity per tick. Telemetry needs its own
  buffered writer.
- An earlier diagnostic build (session transcript, code since removed) wrapped RENDER's
  `GetProcAddress` lookups of RWL20 functions in counting thunks. It found the RENDER globals
  `RENDER+0x4125c` = `RwBeginCameraUpdate` and `+0x41354` = `RwEndCameraUpdate`
  (also `+0x412ec` RwDamageCameraViewport, `+0x41274` RwClearCameraViewport). That proves a
  RENDER-side `GetProcAddress` hook works and gives a once-per-rendered-frame hook.

### RTLIB native dispatch (from an earlier Ghidra session, RTLIB32 base 0x10000000)
- `FUN_10009b6c(id, nargs)` calls
  `ExternalCall(fn = *(inst+0x3157)[+4 + (id-0xfa)*8], ctx = *(*(inst+0x315b) + idx*0x3c + 4),
  args = &DAT_10053eb0[sp], nargs)`, with `inst = *(int*)DAT_10054788` and sp at
  `inst+0x3d33`. The second ExternalCall argument is probably the `ctx` the native receives
  (hypothesis). `ExternalCall` is exported at `0x1002af65`.
- Script globals: `inst + 0x3e2f + 4*id` (docs/analysis.md "Script VM"). So the hook can read
  any global `Gn` directly.

### Script-level facts (from `tools/script7l.py` listings; regenerate with
`python -I tools/script7l.py ISO/G-NOME/G-NOME.BIN > scripts.txt`)
- **G973 = the player-controlled object** (strong hypothesis). Mission start script 8737 sets
  `G973 = ArrayGet(layout, 1, 1)` (layout row 1 = player, column 1 = runtime id). Script 2243
  (commandeer) sets `G1826 = G973` (old body) and then `G973 = <nearest vehicle>`. Script 2199
  tests `L0 == G973` before it moves the camera (`AttachCamera(G973, GetProperty(G973,10),…)`).
- **Script 1728 = generic per-object update step**:
  `L2 = UpdateTimeStep(obj, L1, 41)`, then `UpdateCollideCheck`, `script_437`
  (`Process_Sector_Collisions`), `script_2077`. It's called from update scripts 1723, 1727,
  1730 and 2199. L1 is probably the elapsed time handed to update scripts, and 41 might be a
  max step in ms (hypothesis).
- `UpdatePosOrient(obj, x)` is called directly by ~26 sites (scripts 1726, 1731–1739, 1755,
  1946, 2040–2043, 2174, 2199, 5968–5970, …). These are update paths that bypass 1728.
- Signatures seen: `GetObjectPosition(obj, &x, &y, &z)`, `SetPosition(obj, x, y, z)` (y is
  up: script 2199 does `SetPosition(obj, x, 120, z)`), `L = GetObjectHeading(obj)`,
  `SetVelocityForward(obj, v)` (the player's is set from `GetProperty(G973, 33)`),
  `ApproachTargetSpeed(obj, v)`, `CheckActionState(...)` (33 call sites = input polling),
  `AddObject` (5 args), `GetFrameRate`, `GetCameraPos(&x,&y,&z)`, `GetCameraYaw()`.
- Units (analysis.md "Missions, units and layouts"): game units, 600 = one ground tile,
  model units = game units / 100. Layout headings are hundredths of a degree. Layout rows are
  `[unit_row, runtime_id, x, z, y, heading*100, flag]`; the exported copy is
  `remake/game/_import/data/layouts.json` (mission 1-1 = array 8743, 76 rows).

### RENDER.R32 (base 0x10000000; `.data` 0x10037000–0x10042db0)
- Export addresses (PE export table): `GetObjectPosition 0x10012484`,
  `GetObjectHeading 0x1001252c`, `GetVelocityForward 0x1001284e`, `GetProperty 0x1001271e`,
  `SetProperty 0x10016c09`, `SetPosition 0x10016c76`, `UpdateTimeStep 0x10011ec1`,
  `UpdatePos 0x1001817e`, `UpdatePosOrient 0x1001821f`, `UpdateOrient 0x100180fe`,
  `AddObject 0x100100f0`, `AllocObjects 0x10010762`, `FreeAllObjects 0x100121fc`,
  `SetVelocityForward 0x10017516`, `SetVelocityXZ 0x100175dc`, `CheckActionState 0x1000c631`,
  `GetFrameRate 0x1001234b`, `GetCameraPos 0x1001229c`, `GetCameraYaw 0x10012316`,
  `Projectile_Update 0x10028170`, `SetBackProcess 0x1002970f`.
- Object list (analysis.md, RENDER notes; offsets are **module-relative**):
  `*(DWORD**)(RENDER+0x40264)` = array of object pointers, `*(int*)(RENDER+0x40268)` = count.
  Per object: `+0x54` flags (byte `+0x55 & 5` = hidden), `+0x88` sort key, `+0x98` model,
  `+0xe4` property-record count, properties at `+0xec + 16*count` (analysis.md "Object
  templates"). In the mission 1-1 cockpit an earlier probe logged count=2500, live=823,
  with-model=94, drawable=38 (2500 = allocated capacity).
- Per-frame render: `FUN_1002a09f` → `FUN_10006446` (object loop), timed into `DAT_1003a7e4`.
  The render context is `DAT_1003d618`.
- RENDER imports `GetAsyncKeyState`, `GetKeyState` (USER32) and `joyGetPosEx` (WINMM), so raw
  input is also hookable.
- Frame rate: about 35 fps in a mission. `RtService` (G-NOME.EXE's idle tick) runs up to
  ~1000/s with `IdleSleep=1`, so it is **not** a frame tick.

### Tools
- `tools/dev/peek.exe <pid> render.r32 40264 <n> [deref…]` reads game memory. It was used to
  read `DAT_10037ae4` (ground pointer, NULL in 1-1).
- `tools/dev/stacksample.exe <pid> [n] [ms]` gives EBP-chain samples, which helps find who
  calls a native each frame.
- `tools/dev/drive.ps1` launches the windowed game and runs `hold:UP:3000`-style steps
  (route to the 1-1 cockpit is in CLAUDE.md).
- Don't combine `gtrace.dll` with gnomefix: both patch the same IAT entries.

## Still to find by RE
1. What a script "object" value is: a pointer, or an index into the RENDER+0x40264 array?
   Decompile `GetObjectPosition`/`GetProperty`.
2. Field offsets for position (float or int? which order?), heading/yaw, pitch/roll,
   forward velocity, state: decompile `GetObjectPosition`, `GetObjectHeading`,
   `GetVelocityForward`, `SetVelocityForward`, `ObjectSetState`, `UpdatePosOrient`.
3. What `ctx` is, and whether calling the original native from the hook with a captured ctx
   is safe. Check `ExternalCall` at RTLIB `0x1002af65`.
4. The meaning of `UpdateTimeStep`'s args (`L1`, `41`) and return value, and what drives
   update-script timing (OB3D `[6,interval,script]`).
5. Property indices worth logging (33/34 speed-like, 43/44 jump/state in 2199, 0 =
   class/type <200?, health/armour). Coordinate with R3/R6.
6. Template or unit type per object: hook `AddObject` and record (args → returned id), or
   find the template field in the struct.

## Plan
1. **RE pass (Ghidra/REA, short):** decompile the getters above in RENDER.R32 and
   `ExternalCall` in RTLIB. Record offsets and signatures in `docs/analysis.md`.
2. **INI switches** in `load_config()`: `Telemetry=0` (0 off, 1 player only, 2 all updated
   entities), `TelemetryFile=` (default `%TEMP%\gnome-telemetry-<yyyymmdd-hhmmss>.csv`),
   `TelemetryEvery=1` (log every Nth frame). Document them in README.md and analysis.md
   "Options".
3. **Hook plumbing:** in `hGetProcAddress`, drop the `drawdist == 100` early return and gate
   each hook on its own option. Wrap `UpdateTimeStep`, `UpdatePosOrient`, `UpdatePos`,
   `AddObject`, `CheckActionState`, `SetPosition` with pass-through hooks that also record the
   ctx and object id. Add a RENDER kind to `hooks[]` and hook RENDER's `GetProcAddress` to
   wrap `RwEndCameraUpdate` as the **frame boundary** (frame counter, flush point).
4. **Sampling:** at each frame boundary, write one row for the player (`G973` read from RTLIB
   globals). Read the struct directly, or call the original `GetObjectPosition`/
   `GetObjectHeading`/`GetVelocityForward` with the captured ctx. For mode 2, write a row for
   each object seen in an update hook since the last frame (dedupe by id), or walk the
   RENDER+0x40264 list and skip hidden entries or those without a model.
5. **Writer:** a 256 KB in-memory buffer, `WriteFile` at frame boundaries when it's over
   half full, flushed on `DLL_PROCESS_DETACH`/`RtFree`. Never open the file per row.
6. **Events:** spawn (`AddObject` args + id), player change (G973 differs from the last
   frame, i.e. commandeer/eject), and mission start (first `SetCameraClipping` or the
   main-script id, if it can be read).
7. **Driving script:** a `tools/dev/telemetry-run.ps1` (or drive.ps1 steps) that enters 1-1
   and runs a fixed input sequence (idle 3 s, `hold:UP:3000`, `hold:LEFT:1500`, …). Add a
   small Python reader (`tools/telemetry.py`) that summarizes speed, turn rate and
   acceleration and compares two CSVs.

## Proposed output format (CSV, one file per run)
```
# gnome-telemetry v1, gnomefix <build>, mission <main script id or ?>, units: game units, 1/100 deg
rec,frame,t_ms,obj,tmpl,x,y,z,heading,pitch,roll,vfwd,state,flags,actions
F,1203,40115,,,,,,,,,,,,0x0005          # frame boundary + active input actions bitmask
P,1203,40115,0x0123abcd,2631,3600,0,-1800,9000,0,0,45,1,0x108,
U,1203,40115,0x0124...,2619,...
E,1203,40115,0x0124...,,,,,,,,,,,player=0x0124... prev=0x0123abcd
```
- `rec`: F frame, P player, U other entity, E event, S spawn. `t_ms` = `timeGetTime()`
  relative to the first row. Positions stay raw (no unit conversion in the hook), and the
  reader converts. If heading turns out to be a float/matrix, log yaw in 1/100 degree to match
  layout arrays, plus the raw value in an extra column during bring-up.
- The remake writes the same columns from Godot, so `tools/telemetry.py a.csv b.csv` can
  diff them.

## Verification
- `Telemetry=0`: no file, no behaviour change; the existing gnomefix log line still appears.
- Windowed 1-1 run (drive.ps1, short): the first P row's x/z/heading equals layout 8743 row 1
  (`layouts.json`; note the layout column order x, z, y). Holding UP makes the position
  advance along the logged heading, and LEFT changes the heading monotonically. Speed
  plateaus at a stable max.
- S rows at mission start ≈ the 76 layout rows (plus the ground tiles and other
  script-spawned objects).
- Cross-check one frame's player position with `peek.exe` at the struct offsets.
- Overhead: frame rate (`GetFrameRate`, or drive.ps1's CPU and elapsed time) is the same
  with Telemetry=1/2 and with 0. File size is reasonable (about 1 MB/min in player mode).
- Commandeer in 1-1 produces an E row and P rows switch to the vehicle.

## Open questions / risks
- The ctx argument: calling natives with a stale ctx may be unsafe. Reading the struct is the
  safer fallback.
- Logic and render ticks may differ (update scripts have intervals). Log `t_ms` and the
  `UpdateTimeStep` dt so the remake can replay the same timestep.
- `UpdateTimeStep`/`UpdatePosOrient` might not run for every moving thing (projectiles use
  `Projectile_Update`; AI may move via `MoveTo*`). Mode 2 via the list walk covers that.
- Full-screen runs (`Display=0/2`) need the user's go-ahead (CLAUDE.md launch rules), but
  telemetry doesn't need full screen.
- Determinism: inputs from drive.ps1 are wall-clock timed, so two runs differ slightly. Log
  the action bitmask so the remake replays inputs per frame, not per second.

## Dependencies
- None blocking. It feeds **R1** (orientation and handedness check against real headings),
  **R3** (speeds, turn rates, accel), **R5** (sandbox comparison) and **R7** (AI state,
  later). The struct offsets found here are shared with R3.

## Notes to fold into analysis.md
- RTLIB native call path `FUN_10009b6c` → `ExternalCall(fn, ctx, args, nargs)` (table offsets
  above). Natives are cdecl with ctx first.
- G973 = player object; script 2243 = commandeer (G1826 = previous body); script 1728 =
  per-object update step (`UpdateTimeStep(obj, dt?, 41)`).
- The object-list offsets `+0x40264/+0x40268` are RENDER.R32 **module-relative** globals
  (`DAT_10040264`), with capacity 2500 and ~823 live objects in the 1-1 cockpit.
- RENDER's RWL20 function pointers: `+0x4125c` RwBeginCameraUpdate, `+0x41354`
  RwEndCameraUpdate, `+0x412ec` RwDamageCameraViewport, `+0x41274` RwClearCameraViewport.
