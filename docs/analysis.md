# G-Nome (7th Level, 1997) — Reverse-Engineering Notes

Source: retail CD contents extracted to `ISO/` (gitignored). All binaries built
Feb 1997 with MSVC 4.2. Addresses below are for RTLIB32.DLL
(sha256 `783a2967…95c2`) unless noted.

## Disc layout

| Path | What it is |
|---|---|
| `SETUP.EXE`, `_SETUP*.LIB`, `SETUP.INS` | **16-bit** InstallShield 3 installer (NE format) — cannot run on 64-bit Windows |
| `G-NOME/` | The game |
| `DIRECTX/` | DirectX 3.0a redistributable (irrelevant today) |
| `MPLAYER/` | Mplayer.com online client (service is dead) |
| `DOMINION/`, `KRONDOR/` | 7th Level demos (same engine; KRONSHOW.EXE is 16-bit) |
| `WIN95/LAUNCH.EXE` | Autorun launcher |

## Architecture

```
G-NOME.EXE (27 KB stub)  --imports RtStartup/RtService/RtFree-->  RTLIB32.DLL
RTLIB32.DLL  = 7th Level "RT" runtime: window, GDI sprite engine, audio (waveOut/MIDI/CD),
               resource manager, script interpreter. Loads G-NOME.BIN.
G-NOME.BIN   = "7L" archive: compiled game scripts + string tables + resource index.
G-NOME.0xx   = resource volumes referenced by the index.
*.R32        = native plugins loaded by the script (`%s.r32`, must export RtLibInit/RtLibFree):
   RENDER.R32  3D game: objects, collision, AI tasks/goals, projectiles, camera, radar,
               DirectSound, joystick; dynamically loads RWL20.DLL (RenderWare 2.0)
   NETGN.R32   multiplayer over DirectPlay (DPLAYX.dll, ordinal imports)
   SMACKER.R32 FMV playback via SMACKW32.DLL
RWL20.DLL    = Criterion RenderWare 2.0 (Nov 1996). RWDL8{A,B,C,D}20.DLL are its 8-bit
               display drivers — they use **GDI DIBSections only** (no DirectDraw).
```

### Startup (RtStartup @ 0x1001bc18)
1. `RtInit` → registers `VIEW_CLASS`, creates a `WS_POPUP|WS_MAXIMIZE|WS_CLIPCHILDREN` window,
   inits Utils/Audio/Sprite/Res libs, reads `7THLEVEL.INI` (`AltTab`, `Debug`,
   `MaxJoySticks`, `[Input] Timeout`).
2. Command line parsed (`FUN_1001bf33`): first non-switch token = .BIN path; switches
   `-w` wallpaper mode, `-s` screensaver (topmost), `-k` (third mode).
3. Color check (`FUN_1001bd03`): needs ≥256 colors (32bpp passes).
4. Memory probe (`FUN_1001b3a0`) via `GlobalMemoryStatus` — no overflow issue (2 GB cap).
5. Loads the .BIN (`FUN_1001dd15`).

### Display (FUN_100423b4, called from RtSetScreenRes)
DirectDraw is used **only to change the display mode**:
`DirectDrawCreate` → `SetCooperativeLevel(hwnd, FULLSCREEN|ALLOWREBOOT|EXCLUSIVE|ALLOWMODEX)`
→ `EnumDisplayModes` → `SetDisplayMode(640,480,8)` → `SetCooperativeLevel(…NORMAL…)`.
`RtEnableDirectDraw` is hard-wired to return 0, so **all rendering is GDI on an 8-bit
palettized screen** (CreateDIBSection, SetDIBColorTable, AnimatePalette, RealizePalette,
BitBlt/StretchDIBits). RenderWare renders to 8-bit DIBs too.

## Configuration
`%WINDIR%\7THLEVEL.INI` (bare filename → Windows dir; UAC virtualizes this to
`%LOCALAPPDATA%\VirtualStore\Windows\` since the EXE has no manifest).
Written by the installer:

```ini
[G-Nome Setup]
Dir=<install dir>
Name=G-Nome.exe
CmdLine=<install dir>\G-Nome\G-Nome.BIN
Source Directory=<CD>:\G-Nome\
[G-Nome]
MaxJoySticks=…
[audio]
MidiVolume=…
WaveVolume=…
```
Also read: `[G-Nome] AltTab, Debug, MaxJoySticks, Mode640, LoMem`, `[Input] Timeout`,
`[Render] …` (RENDER.R32), `LastSmackerFrame` (SMACKER.R32). Registry: `HKCU\Software\7th Level, Inc.`.

CD detection: `RtFileExistsOnCD` scans drives with `GetDriveTypeA == DRIVE_CDROM`.

## Resource archive format ("7L", see `tools/res7l.py`)
Index: 9440 entries of `{u8 type, u8 volume, u32 offset, u32 size}`.

| Type | Magic | Count | Notes |
|---|---|---|---|
| 1 | — | 1240 | 2D sprite bitmaps (bitmap record, see below) |
| 2 | — | 835 | Texture libraries: 1+ texture blocks each (2108 blocks, 923 unique names, path like `\7thlevel\gnome\src\data\bitmaps\mesoonbl.BMP`). A few entries hold other bitmaps or data; 211 are size 0 |
| 4 | `FRME` | 333 | 3D animation frames |
| 7 | `MODL` | 647 | 3D models: tokenized RenderWare script stream (see below) |
| 8 | `MPRT` | 154 | model parts, same stream format |
| 9 | `OB3D` | 426 | 3D object definitions |
| 10 | `OPRT` | 57 | object properties |
| 11 | — | 709 | sound/event records |
| 12 | — | 592 | waves, 22050 Hz (~24 MB, voice + SFX) |
| 13–22 | — | — | inline resources inside the BIN; offsets are relative to the key-5 block (`res7l.read_internal`) |
| 17 | — | 14 | palettes, 944 bytes = 236 x RGBx (entries 10..245); the first equals key 6 |

Key resources: 4 = string constants (movie names, faction names, weapon names),
5 = script bytecode (~1 MB, 11 chunks), 6 = default palette (236 x RGBx), 10 = plugin list,
11 = native import names.

### Model stream (MODL/MPRT), decoded by `tools/rwstream.py`
Header: magic + u32 (unknown), then u32 words. RENDER.R32 loads RWL20 exports by name
(`FUN_10025193`, globals 0x10041218..), copies them into an opcode table at **0x10037050**
(0x24-byte entries `{fn, argtype[8]}`, built by `FUN_100025e5`), and interprets the stream
with **`FUN_10003432`**. Opcode n (1-based) is a RWX script call in alphabetical order:
0x06 ClumpBegin, 0x07 ClumpEnd, 0x08 SetSurfaceColor, 0x1a/0x1b ModelBegin/End,
0x23 Quad, 0x2c SetSurface, 0x2d SetTag, 0x2e SetSurfaceTexture(name), 0x34 TransformCTM(4x4),
0x35/0x36 TransformBegin/End, 0x39 Triangle, 0x3b Vertex, 0x3c VertexExt, 0x3d/0x3e
embedded texture. The full table and argument kinds are in `rwstream.py`.
Structure: `TransformBegin; TransformCTM(M); ClumpBegin; SetTag t; vertices; surfaces;
triangles; [children]; ClumpEnd; TransformEnd`. Each clump is a part with a local matrix
(the CTM at ClumpBegin), clump-local vertices, 1-based vertex indices and a part tag. Tags
are what FRME animations and `AmputateClump`/damage refer to. RW matrices are row-vector
with translation in row 3, so the 16 floats map 1:1 onto glTF's column-major `matrix`.
All 801 MODL/MPRT decode cleanly. `tools/export_models.py` → glTF (one node per clump).

### Bitmaps and textures (`tools/bitmap7l.py`)
Bitmap record: `u32 w, h, flags; i32 hot_x, hot_y; u32 resource_id`, then data.
`RTLIB ResExpandBitmapRec` → `FUN_10044bd0`:
- flags & 0x80: RLE (`FUN_100480d0`). Skip `u16 row_offsets[h]`. Per row: `b<0x80` = run of b
  copies of the next byte, `b>=0x80` = literal of `b^0xff` bytes (0xff: count in the next
  byte), 0 = end of row; another 0 ends the image.
- otherwise: chunked LZW (`DecompressBitmapData`): u16 header, top 3 bits 0 = raw,
  0x4000/0x6000/0x8000 = LZW 10/11/12-bit, 0xe000 = end; low 13 bits = length. An LZW chunk is
  `[u16 len][stream]` sub-blocks, each with a fresh dictionary (`FUN_100356c0`, hand asm):
  fixed-width MSB-first codes, literals 0..255, no clear code, end = all ones.
  Rows are padded to a stride of 4.
- flags & 0x40: rows are top-down; otherwise bottom-up (RENDER flips them).
Texture block: `u32 0x3d|0x3e, u32 len (bytes from this word to the block end), u32
name_len, name, bitmap record`. Textures are 128 wide (RENDER checks this), 128..512 tall,
and often an atlas of faction colour variants (e.g. red/yellow halves). RENDER keeps a
500-entry texture table keyed by basename (`FUN_100039cf`; lookup `FUN_10003fcb`).
Pixel index i uses palette entry i-10 of a 236-entry palette (indices 0..9 = system colours).

FMV: `*.SMK` (Smacker) — G-NOME, DREAM, CREDITS, NEWS, WILKINS. Music: CD audio
tracks (not present in a data-only extraction) + `TRK_01B.WAV`.

## Live test on Windows 11 (2026-10-11)
Setup: `ISO/G-NOME/` copied to a scratch dir, `7THLEVEL.INI` written to
`%LOCALAPPDATA%\VirtualStore\Windows\` (UAC virtualization serves it to the
unelevated, manifest-less game), launched `G-NOME.EXE G-Nome.BIN`.

Observed:
- The game starts with no patching: it switches to 640x480x8, loads all plugins
  (render/netgn/smacker, RWL20, RWDL8D20, DSOUND, DPLAYX), and runs.
- **Main menu renders correctly** (GAME / NETWORK / LAB / OPTIONS / EXIT) with right colors.
- **Intro FMV is a black screen** for its full length (~67 s, `DREAM.SMK` frames advance at
  15 fps — verified by reading the Smacker struct). Space skips to the menu.

FMV root cause #1 (confirmed by API trace): SMACKW32 `SmackBufferBlit` computes
destination x/y as 16-bit words and pushes them zero-extended (`StretchDIBits(hdc,
65216, 65456, …)`). Win9x GDI truncated to 16 bits so these meant -320/-80 (window DC
viewport origin is 320,240). NT GDI is 32-bit, so frames land off-screen.
Fix: `tools/patch_gnome.py` sign-extends these loads in all three blit paths
(StretchDIBits / BitBlt / StretchBlt). With it, an in-process read of the screen DC
shows movie pixels.

**Confirmed on the physical monitor:** with the patch, the 7th Level logo and the
`DREAM.SMK` intro play correctly. External screen captures (CopyFromScreen from another
process) still show black during the FMV. That is an artifact of how other processes
capture Windows' per-process 8-bit emulation, not a display bug, so verify FMV by eye
or by in-process reads rather than by external screenshots.

### Rendering under 8-bit emulation (fixed by `patch/gnomefix.c` → `ddraw.dll`)
Windows 8+ emulates the 640x480x8 mode on a true-color desktop: GDI converts palette
indices to RGB *at draw time*. Two Win9x behaviours the game relies on break:

1. **Palette fades.** RTLIB fades with `AnimatePalette` (entries 10..245). On real 8-bit
   hardware that recolors pixels already on screen; under emulation they stay at their
   draw-time color. Static art drawn once while the palette is black (menu backgrounds,
   cockpit frame) stays dark navy/black; only later dirty-rect updates appear.
   RTLIB composes every frame in one persistent 640x480 8-bit buffer and blits dirty rects
   from it with `SetDIBitsToDevice(DIB_PAL_COLORS)` (verified by trace: same bits pointer
   for full and partial blits). Fix: record the last full-screen blit and replay it after
   each `AnimatePalette`.
2. **Text sprites** (`FUN_10020c60` → `FUN_10020d8f` → `FUN_10016500`). With the palette-device
   flag (`*(DAT_10054788)+0x94cc`) set, text is drawn with `DrawTextA` in `PALETTEINDEX(c)`
   into a screen-compatible 8-bit bitmap, then read back via `GetDIBits(DIB_PAL_COLORS)`.
   Both steps now go through RGB using the current, possibly faded-to-black, palette.
   Trace at mission start: text palette entry `000000`, 0 lit pixels → HUD weapon names
   invisible (ammo counts, redrawn later, were fine). Fix: render the same string into a
   private 32bpp mask (non-antialiased) and, when RTLIB reads the bitmap back, write
   index `c` for text and 0 elsewhere — what Win9x produced.

Delivery: RTLIB32 statically imports only `DirectDrawCreate` from ddraw, so a proxy
`ddraw.dll` in the game directory loads first, forwards DirectDraw to the system DLL and
patches RTLIB32's IAT (`SetDIBitsToDevice`, `AnimatePalette`, `GetDIBits`, `DrawTextA`).
Build with `patch\build.cmd`. Logs one line to `%TEMP%\gnomefix.log`.

Verified on the physical monitor (2026-10-11): intro FMV, menu backgrounds, GAME screen,
mission 1-1 cockpit frame and HUD weapon names all render like the original.

### Options (`[gnomefix]` in `7THLEVEL.INI`)
| Key | Default | Meaning |
|---|---|---|
| `DrawDistance` | 100 | Percent. Scales the far clip and fog distance missions set via the `SetCameraClipping` / `SetFogDepthColor` natives (hooked through RTLIB's `GetProcAddress` native binding). Mission 1-1 sets far 3000/5000, fog 2000. |
| `Display` | 0 | 0 = original full-screen 640x480x8; 1 = window; 2 = borderless full screen |
| `Scale` | 0 | Integer zoom for Display=1/2; 0 = largest that fits |
| `Stretch` | 0 | Display=2: fill the screen at 4:3 (non-integer zoom) |
| `Smooth` | 0 | HALFTONE filtering instead of sharp pixels |
| `IdleSleep` | 1 | When G-NOME.EXE's PeekMessage loop finds no message, wait up to 1 ms (`MsgWaitForMultipleObjects`, `timeBeginPeriod(1)`). CPU: 100% of a core → ~1% in menus, ~4% in a mission. |

### Windowed mode (verified 2026-10-11: menus, briefing, mission 3D view, HUD, mouse, keyboard)
- The game gets a 640x480 32bpp memory DC ("virtual screen") from `GetDC`/`BeginPaint` on its
  window; a presenter thread scales it into the window ~60 times a second.
- RTLIB centres its coordinate system on `GetSystemMetrics(SM_CX/CYSCREEN)/2`, so those (and the
  `SM_CX/CYFULLSCREEN` metrics RenderWare's driver sizes buffers from) report 640x480.
- RTLIB and RWDL8?20 are shown a 640x480x8 palette device (`GetDeviceCaps` + a
  `GetSystemPaletteEntries` built from RTLIB's target palette, sprite object `+0x1424`
  LOGPALETTE). Needed because (a) RenderWare's 8-bit drivers refuse other devices (texture
  rasters are never created → crash in RENDER.R32's texture loader) and (b) RTLIB's true-colour
  path copies dirty rects through a temporary RGB buffer and never shows RENDER.R32's
  "external draw" 3D region (`SpriteSetExternalDraw` flag `0x80`) — the 3D view stays black.
- DirectDraw is replaced by a stub object (SetCooperativeLevel/SetDisplayMode succeed).
- Mouse messages are rescaled in `PeekMessageA`; `GetCursorPos`/`SetCursorPos`/
  `ScreenToClient`/`ClientToScreen`/`GetClientRect`/`InvalidateRect` are translated.

RENDER.R32 notes from this work: `Init3D` points a RenderWare user raster at RTLIB's 640x480
compose buffer (`SpriteSetComposeFlags`) — the 3D view is rendered straight into the 2D
compositor's buffer. Per-frame render: `FUN_1002a09f` → `FUN_10006446` (object list at
`+0x40264`, count `+0x40268`; object `+0x98` model, `+0x54` flags). RenderWare picks its driver
by scanning the game folder for `*.dll`; driver D (`RWDL8D20`) is used.

Crash on exit (seen twice, not reproduced in the last three runs): access violation in
the CRT's `flsall` (RTLIB32 `0x1002a240`) reading the stream table `__piob` (`0x10060ab8`).
One occurrence was without user input near the end of the intro. Unresolved.

## Modern-Windows blockers (hypotheses, to verify by running)
1. **Installer is 16-bit** → cannot run on x64. Need a replacement installer
   (copy files + write 7THLEVEL.INI).
2. ~~8-bit palettized GDI rendering~~ → works on Win11 as-is (menu and FMV both display
   correctly via Windows' 8-bit emulation). The FMV black screen was the SMACKW32
   16-bit coordinate bug above, now patched.
3. CD check / `Source Directory` → needs drive letter of type CDROM (a mounted ISO works) or a patch.
4. DirectPlay (NETGN.R32) → requires the "DirectPlay" Windows optional feature; protocols
   (IPX/modem/serial) mostly dead — TCP/IP only.
5. Possible timing issues on fast CPUs (`timeSetEvent`-driven; "Out of timers" error string).
6. CD audio music → needs CD-audio emulation if tracks are available.

## Script VM (RTLIB32), disassembler `tools/script7l.py`
Scripts are 7L **type 19** resources (2342 of them). Each one is a function, called by
resource id. `RtRun` → `FUN_1001f12d` (copies args onto the frame stack at instance+0x35cf)
→ `FUN_1001fcfe` (max nesting 30) → `FUN_1001fdc6`, which loops over **`FUN_1001f1f7`**.
That is the statement dispatcher: u16 opcode, and each handler returns the byte distance to
the next statement, so jumps are relative to the statement start and statements are padded
to even lengths.
- Most statements are fixed-length records (lengths in `script7l.FIXED`). Key variable ones:
  `0xAF len expr` (expression statement), `0xA1 len expr` (return value), `0xA2` (end),
  `0x5B/0xE3 f t expr` (if: f = rel target when false, t = length), `0x68 rel` (goto),
  `0x5A rel a b cmp fa fb` (compare typed operands), `0x59` (compare, then run script A or B),
  `0xDA/0xDB` (switch on an operand / expression, with case table entries `0xDC value
  target flag` embedded in the code), `0x01` (variable length, byte 9 * 4 + 10).
- Typed operands `(u32 value, u8 is_var)`: `FUN_10014e00`.
- **Expression VM `FUN_10003330`**: byte opcodes on an int32 stack (`DAT_10053eb0`, sp at
  instance+0x3d33). 01 push imm, 02 load var, 04 address of var, 03 index, 05 deref,
  06 element address, 08 assign, 0D call (u32, u32 nargs; the callee id sits below the args),
  0E call script (u32 nlocals, u32 nargs), 0F..2A neg/not/~/+ - * / %/comparisons/&& ||/
  & | ^/inc/dec/short-circuit jumps/shifts, 00 end. Integers only: scripts use fixed-point
  or scaled values (positions are in game units; 600 = one ground tile).
- Variables: id < 0x13FE → global (instance+0x3e2f+4*id); otherwise frame local L(id-0x13FE).
- Call ids < 0xFA → RTLIB builtins (`FUN_10003fad`, a 181-case switch; names in
  `script7l.BUILTINS`). Ids ≥ 0xFA → plugin natives through `ExternalCall`. Index id-0xFA
  follows the key-11 name order (verified by arity: AddObject 5 args, SetPosition 4, …).
- Validation: all 2342 scripts decode exactly to their end, and all 6979 jump and case
  targets land on statement boundaries.
- Usage: GetProperty/SetProperty (≈3300 calls) dominate. Then ArrayGet (1879),
  SpriteSendMessage, ArraySet, Clone (= instantiate a template resource), List*,
  SetUpdateScript, LinkModel, DSPlayWave, the DirectPlay natives, …

### Data tables (type 11 = arrays, `res7l.read_array`)
709 int32 arrays with 1–3 dimensions (header 0x3c bytes: byte size, id, ndims, strides[5],
dims[5]). Read with `ArrayGet(array, i, j, …)`. Example: **array 2512 = per-mission world
setup**, 16 rows (4 worlds × 4 missions):
`[backdrop bitmap (type 1, 1328x383 panorama), palette (type 17), fog depth, fog R, G, B,
world 0-3, wave resource]`. It's used by script 2514: SetCameraBackdrop, SetFogDepthColor,
SetBackgroundColor. So **the palette is chosen per mission**. Worlds: 0 = desert (fog 2000),
1 = (pale blue fog), 2 = (fog 3000, dark), 3 = red dusk (fog depth 5).
Ground: per-world scripts (e.g. 2418 = desert, called from 2514) place tile objects (OPRT 2478/2480, ...) every 600 units with
`script_2039(1, tile, x, z, 0, 0, 260)` and `SetLevel(obj, -100)`.

### Missions, units and layouts (2026-10-12)
- **Mission table = array 6984** (34 x 6): `[index, array, type16, main script, array, n]`.
  Rows 1..22 are the campaign missions 1-1..4-6 in order. Rows 23..32 have only a main script
  (training and multiplayer maps). Mission 1-1's main script is **8744**:
  `script_2515(bounds…)` → setup `script_8736(1, 8743)` (sets world row via
  `script_2513(row)`, camera/LOD) → `script_2523(1, 8743, 0)` = **spawn the layout** →
  `script_8737` (mission start: player, objectives, …).
- **Layout arrays** (e.g. 8743, 76 x 7): `[unit_row, runtime_id, x, z, y, heading*100, flag]`
  in game units. `script_2523` fills column 1 with the spawned object id, so later scripts find
  units by layout row. Row 1 of 1-1 is the player: Union infantry, on foot.
- **Unit catalogue = array 5843** (197 x 5): `[template, init script, class, category,
  variant]`. Categories: 141 Sentry, 142 Tactical Defense, 143 Cruiser, 144 Heavy Assault
  HAWC, 161 hovercraft, 181/182 armoured support, 22-24 infantry, 2xx structures,
  250 rock formations, 251-255 scenery, 500 waypoint, 550-553 nav/supply, 570 ?.
  Rows 0-23 = Union / Darken / Merc / Scorp vehicles + infantry. They match LABTEXT.DAT
  (`tools/export_gamedata.py` joins them). Template props[1..7] = the same model in 7 team
  colours. `script_2039(class, template, x, z, heading, y, category)` instantiates a unit.
- **Unit init scripts** (catalogue column 1, e.g. 2619 → 2631 for the Union Prowler) set:
  codex stat A (`script_2056` → props 97/94/134) and stat B (`script_2057` → 95/98/135);
  turn/accel limits (SetMaxAngularVelocity/Accel, SetMaxAccel); weapons
  (`script_1656(obj, weapon, ammo, hardpoint)` using **weapon table array 1281**);
  the animation state machine (`addAnimation`/`addTrigger` over FRME resources); AI/update
  scripts (props 72/75/93/130).
- **Scale**: game units / 100 = model units (ground tile = 6 model units = 600 game units).
  Headings are hundredths of a degree.
- **Palettes**: entries 10..185 are identical in all 12 mission palettes. Entries 186..245 change
  per mission (terrain colours). So vehicle textures are palette-independent, while 104
  terrain/scenery textures need the world palette (`export_models` writes `__w1..3` variants).
- **Rock formations** (category 250) have no texture in the model. The spawner applies
  `SetModelTexture(model, 2482 + world)` (type-1 128x128 bitmaps).
- **RWX vertex rule**: vertices are transformed by the CTM in effect when they are emitted.
  `ClumpBegin` makes the CTM the child's local transform and resets it to identity inside.
  Rock models rely on the first rule.

## Remake-relevant (Goal 2)
- All gameplay logic is in script bytecode (key 5) + RENDER.R32 natives (AI tasks/goals,
  movement behaviours: pursue/evade/flock/follow, collision, projectiles, damage/health).
- Unit stats in `LABTEXT.DAT` (vehicle database text), trivia in `TRIVIA.DAT/.IDX`.
- Assets (models, textures, sprites, audio, FMV) are all extractable from the 7L archive.
  Models and textures: done (`tools/export_models.py` → `remake/game/_import/`, viewed with
  the Godot model viewer). Not yet decoded: FRME animations, OB3D/OPRT object definitions,
  which of the 14 palettes applies where, model units vs metres, and handedness (needs a
  mirrored-text check).
- **Terrain** (2026-10-12). Mission 1-1 has **no heightfield**: RENDER's ground pointer
  `DAT_10037ae4` is NULL in the cockpit (read with `tools/dev/peek.exe`). The playfield is a
  flat plane of ground tiles: MPRT quads textured `<world>grd<bits>.bmp`, e.g. `dgrd1000` /
  `dgrd1101` for desert and `igrd*` for another world set. The 4-digit suffix looks like a
  neighbour/transition mask. The scenery is placed as 3D objects, and the mountains and sky
  are a backdrop bitmap (`SetCameraBackdrop`). RENDER *does* support a heightfield:
  `AddGround(obj, res, x, y, z)` (0x100193a0) reads `int nx, nz, cell`, an optional texture
  block (0x3d), an optional texture name (0x2e + len + name), then nx*nz sectors of
  `{int n; n * float xyz; 0x23 → polygon data (FUN_10019542) | other word}`. The sector grid
  spans ±n*cell with a step of 2*cell, and the height is bilinear inside a quad
  (`FUN_1001a012`, used by `UpdateGroundHeight`). The script imports it, but no resource with
  that layout was found statically. Check other missions once the script disassembler exists.
- **No heightfield anywhere**: `FUN_100043f0` (RENDER's resource load proc) accepts a `GRND`
  magic for `AddGround`, but no resource on the disc has it. Every mission is a flat plane.
- **Object templates (OB3D type 9, OPRT type 10)**, loader `FUN_100043f0`, decoder
  `res7l.read_object`. Layout: `u32 slots`, then records: `[1,a,b]`, `[2,min,max,restype,res]`
  (restype 7 = model LOD for distance min..max, otherwise a script active in that range),
  `[6,interval,script]` update script, `[8,model]`, and finally `[7,size,n,props[n]]`, the
  property array that GetProperty/SetProperty index (runtime object +0xe4 = record count,
  properties at +0xec+16*count). `size` is usually 144. Templates seed only a few properties.
  Scripts set the rest (unit stats come from arrays via SetProperty). All 483 decode.
- **String constants (key 4)**, 541 strings: FMV names, AI team names (Union/Darken/Merc/Scorp),
  characters (Thane, Kylie, Sheridan, Wilkins), weapon names, the **full control-action list**
  and key names, keyboard presets ("G-NOME Flight Sim/Arcade", "MechWarrior2", "EarthSiege2",
  "Shattered Steel"), **all 22 campaign mission titles and objective lines**, 7 multiplayer
  maps with descriptions, and the menu tooltips. `tools/export_gamedata.py` groups them into
  `missions.json` (22 missions ↔ 22 objective groups).
- **Key 3** = initial values of script globals: `(var, value)` pairs.
- Script disassembler: done (see "Script VM"). Next: name the object property indices
  (GetProperty/SetProperty, ≈3300 uses) and the type-11 arrays (unit stats, weapons), find
  each mission's entry script and its object placement, and decode FRME animations.
