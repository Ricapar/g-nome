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
| 4 | `FRME` | 333 | 3D animation frames (one is empty; format under "Animations" below) |
| 7 | `MODL` | 647 | 3D models: tokenized RenderWare script stream (see below) |
| 8 | `MPRT` | 154 | model parts, same stream format |
| 9 | `OB3D` | 426 | 3D object definitions |
| 10 | `OPRT` | 57 | object properties |
| 11 | — | 709 | int32 arrays (script data tables, `res7l.read_array`; see "Data tables") |
| 12 | — | 592 | waves: IMA ADPCM or PCM, 11/22/44 kHz (~24 MB packed, 44.6 min; voice + SFX). See "Waves" below |
| 13–21 | — | — | inline resources inside the BIN; offsets are relative to the key-5 block (`res7l.read_internal`). 19 = scripts (2342), 20 = sprite definitions (913, mostly 74-byte records with a bitmap id at +0x26) |
| 17 | — | 14 | palettes, 944 bytes = 236 x RGBx (entries 10..245). 2487..2509 (odd ids) are the 12 mission palettes of array 2512; 2510 and 2511 equal key 6 and are not in the world table |

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
and often an atlas of faction colour variants (e.g. red/yellow halves). These behave as
stacks of 128x128 frames (RenderWare 2.0 texture frames): model UVs address one frame and
wrap inside it (V runs past 1.0 on some parts). Sampling `(u, (fract(v) + frame) / frames)`
with frame 0 gives the red/grey Union Prowler (2583) that the original 1-1 briefing shows;
using V as-is gives green legs. Implemented in `remake/game/viewer/rw_frame.gdshader` +
`rw_model.gd` (used by the menu's ModelStage). Per the user (who knows the original): the
frames are display states, not team colours. The green frame is the cockpit HUD hologram of
the vehicle, and parts turn orange then red as they take damage (likely further frames in
taller textures). Unverified: which frame index is which state, and how RENDER switches them. RENDER keeps a
500-entry texture table keyed by basename (`FUN_100039cf`; lookup `FUN_10003fcb`).
Pixel index i uses palette entry i-10 of a 236-entry palette (indices 0..9 = system colours).

### Waves (type 12; `tools/wave7l.py`, exporter `tools/export_audio.py`)
32-byte header, then `data_len` bytes:
`u32 data_len; u8 f0, f1, f2, f3; u32 0; u32 resource_id; PCMWAVEFORMAT {u16 tag=1, u16 ch,
u32 rate, u32 bytes/s, u16 align, u16 bits}`. The format is that of the *decoded* audio.
`ResCreateWaveEvent` @ 0x10047451 reads the header and passes it to `AudioCreateWave` @
0x1002f033 → `FUN_1002f168`, which copies the flags into the wave object:
- f0 → obj +0x86: load the whole wave into memory (otherwise it may stream through a ring
  buffer of `DAT_1005e5b0 << 13` bytes; short waves are always loaded whole);
- f1 → obj +0x89: meaning not confirmed;
- f2 → obj +0x8d: **compressed** (IMA ADPCM). Only id 284 (8-bit 11 kHz) has f2 = 0 and is raw PCM;
- the u32 at +8 (always 0) → obj +0x80 (u16).

Codec: `ima2pcm` @ 0x100342f0 (export #315), called by the in-memory loader `FUN_1002fba8`
and the streamer `FUN_100327d0`. It is plain **IMA/DVI ADPCM with no block headers**: one
continuous stream, predictor and step index start at 0 (`DAT_1005e970..78` zeroed), low
nibble first. Mono: 2 samples per byte. Stereo: one frame per byte, low nibble = left, high
nibble = right, separate state per channel. Output is always 16-bit, so decoded size =
`data_len * 4`. RTLIB stores the tables premultiplied: `DAT_100529e0` = 89x8 difference
table (`step>>3 + (c&4?step) + (c&2?step>>1) + (c&1?step>>2)`, standard IMA steps 7..32767)
and `DAT_10052f70` = the index adjust table x8 (`-1,-1,-1,-1,2,4,6,8`); the index is kept
x8 and clamped to 0..0x2c0. `tools/wave7l.py` regenerates both tables and they match the DLL
bytes exactly. RIFF files with a compressed flag (`FUN_1002fa4c`) skip a 10-byte header
first; the `DecompressWave*` exports (stream API with a 10-byte header, `u16 == 1` check)
are not used by the game's own resource path.

Measured on the export (2026-10-13): 592 waves, 0 failures, 44.6 min. Formats: 383 x 22050
mono, 205 x 11025 mono, 2 x 22050 stereo (308, 309: ambient), 1 x 44100 mono (8398), 1 x
11025 8-bit raw (284). Speech (e.g. 9267, 7011) shows clean formant harmonics; many voice
lines touch full scale (hot mastering: the raw PCM wave 284 clips too), so clipping in the
decoded output is from the source. Durations 0.14..31.9 s, median 2.7 s.

Playback from scripts: the RENDER.R32 natives `DSPlayWave(id, volume 10000|15000, 0, loop,
done_script, priority?, 1)`, `DSLoadWave`, `DSStopWave`, `DSUnloadWave`, `ObjectPlayWave(obj,
id, …)`, and the helper `script_334(id, …)` (stops the previous one-shot, then
`DSPlayWave(id, 10000, 0, 0, 332, 2000, 1)`). Every menu sound is gated by `if !G2116`
(likely the sound-off option).

**Front-end (main menu) sounds** (from `tools/script7l.py` listings; R10 has the menu table):
| Wave | Length | Event | Evidence |
|---|---|---|---|
| 8403 | 0.43 s | bottom-bar key selected (GAME/NETWORK/LAB/OPTIONS/EXIT) | `script_8341(n)` (bar select, called by click scripts 8344-8349) plays it; also script 8538 (no static caller found) |
| 8404 | 0.37 s | left/right column slot selected | `script_8353` (left column, G2054) and `script_8354` (right column, G2055) |
| 74 | 0.16 s | "denied": action not available | `script_8350`, called e.g. by 8361 (when G2185 = -1), 8366 (SAVE when no campaign mission, G2141 not 1..22), 8385, 8388, 7548, 7725, and network submenu array 8621; also `script_334(74, …)` in scripts 1648/1682 |
| 75 | 0.64 s | option toggled / confirmed | `script_8351`, called by 6330/6331 (joystick on/off), 6340/6341, 7433-7435, 7762; `script_334(75, …)` in 2220, 6001, 7766, 7959, 7960 |
| 131 | 1.04 s | Escape on the menu: quit-confirm prompt | key 0x1b → script 8312: `script_334(131, 1, 1, 0)` + shows sprite 1998; Y → 8314 (quit), N/Esc → 8313 (no sound). Also 1953 (in mission) |
| 8398 | 5.61 s, 44.1 kHz | menu background loop | `script_8315`: `DSPlayWave(8398, 10000, 0, 1, 0, 200, 1)` (arg 4 = loop) at menu start (5998); unloaded by 8316 |

Hover plays **no** sound in the original: the hover scripts (column 5 of the menu arrays,
8320-8338 → `script_8333` → `script_8340`) only move the status-text sprite 8536, and the
leave scripts 8324/8331 hide it. The remake maps these in
`remake/game/ui/components/ui_sounds.gd` (loads `res://_import/audio/wave_<id>.wav` at
runtime; placeholders when the import is missing).

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
compositor's buffer. Per-frame render: `FUN_1002a09f` → `FUN_10006446` (object list in the
module globals `DAT_10040264`/`DAT_10040268`, i.e. RENDER+0x40264; object `+0x98` model,
`+0x54` flags; see "Runtime object struct"). RenderWare picks its driver
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
- **Layout arrays** (e.g. 8743, 76 x 7): `[unit_row, runtime_id, x, z, level_flag,
  heading*100, flag]` in game units. `level_flag` is not a coordinate: in `script_2040`/`2041`
  the height is `h = 0; if (level_flag == 1) h = G1846` (6 of 4537 rows set it; no script
  assigns G1846, so its value is still unknown). `script_2523` fills column 1 with the spawned object id, so later scripts find
  units by layout row. Row 1 of 1-1 is the player: Union infantry, on foot.
- **Unit catalogue = array 5843** (197 x 5): `[template, init script, class, category,
  variant]`. Categories: 141 Sentry, 142 Tactical Defense, 143 Cruiser, 144 Heavy Assault
  HAWC, **161 treaded armoured support, 181/182 hovercraft**, 22-24 infantry, 2xx structures,
  250 rock formations, 251-255 scenery, 500 waypoint, 550-553 nav/supply, 570 ?.
  (161 vs 181/182 was labelled the other way round until R0, 2026-10-14. Verified four ways:
  the 161 rows use the tread models with `?tl1*` textures and the 181/182 rows the hover-skirt
  models with `?hl2*` textures, seen in the viewer; their init scripts set the codex stats and
  loadouts of the treaded / hover vehicle; and with the swap LABTEXT kph = prop35 x 0.45 for
  all eight rows.) Rows 0-23 = Union / Darken / Merc / Scorp vehicles + infantry; they match
  LABTEXT.DAT (`tools/export_gamedata.py` joins them). The scripts are authoritative where the
  codex text differs (stat B of 5 vehicles, some ammo counts, Legionnaire zWASP vs FLECH).
  Scenery rows 251/252/253/255 have variant = world + 5 (each world has its own models);
  structures 211..237 use variant 1 or 88..99.
- **Template props** `[class, m1..m7, a, b]`: props 1/4/7 are the LOD0/LOD1/LOD2 models
  (`script_2146` clones them into object props 79/80/81), props 2/3/5/6 are LOD0/LOD1 in the
  two other texture sets (Prowler: `hbl1a*`, `hbl1w*`, `hbl1s*`; 330/318/318 triangles; LOD1
  169-179, LOD2 100) and go onto list `G1849`. What the a/w/s sets are for is open. Tanks and
  hovercraft have no LOD1 variants (props 4-6 = 0). `script_2039(class, template, x, z, heading,
  level_flag, category)` instantiates a unit: `script_2040`/`2041` call `AddObject(obj, 0, x, h,
  z)`, then `ObjectYaw(obj, heading)`, then `UpdatePosOrient(obj, 1)`.
- **Unit init scripts** (catalogue column 1, e.g. 2619 → 2631 for the Union Prowler) set:
  codex stat A (`script_2056` → props 97/94/134) and stat B (`script_2057` → 95/98/135);
  throttle limits (`script_2066(obj, rev, fwd, a, b)` → props 36/35/15/33), torso and pitch
  (`script_2070`, `script_2074`), turn/accel limits (SetMaxAngularVelocity/Accel, SetMaxAccel);
  weapons (`script_1656(obj, weapon id, ammo, hardpoint)` using **weapon table array 1281**);
  the animation state machine (`addAnimation`/`addTrigger` over FRME resources); and the
  cockpit resources props 72 (type-20 sprite), 75 (`ViewportCrop` script), 93 (gauge array),
  130 (`LinkModel` script). The AI is the template update script 1723 plus the task list (see
  "AI" below), not these props. The Union Lion branches on `G982` (set to 1 by the network
  scripts 2565/7xxx and 0 by 6277/7275, so probably the multiplayer flag): campaign stats
  90/2200, fwd 200; otherwise 20/1000, fwd 110.
- **LOD bands**: the template's `[2, min, max, 19, script]` records run scripts 2147/2148/2149
  (2150 picks by what exists) when the camera distance (float32 min..max in model units, e.g.
  0..0.21, 0.2..0.51, 0.5..1.2, 1.1..50) enters the band. They set prop 92 = 0/1/2,
  `setLOD(obj, n)`, `LinkModel(obj, prop 79/80/81)` and call `script_425(obj, lod)`, which maps
  per-LOD part ids into props 10/22/29/31. Prop 92 is the current LOD, not difficulty.
- **Scale**: game units / 100 = model units (ground tile = 6 model units = 600 game units).
  Headings are hundredths of a degree. **1 game unit ≈ 0.125 m** (hypothesis from R5: model
  heights x 100 vs codex heights match for the Ogre and Minotaur; it also explains the codex
  speed factor, kph = prop35 x 0.45 = prop35 x 0.125 x 3.6, if prop35 is in units/s). Unconfirmed
  until R2 measures a speed.
- **Palettes**: entries 10..185 are identical in all 12 mission palettes; **186..215 change per
  world** (same for all palettes of a world) and **216..245 per mission** (mostly backdrop sky).
  So vehicle textures are palette-independent, while 104 terrain/scenery textures (all with a
  world prefix `d`/`i`/`g`/`m` = world 0..3, never used outside their world) need the world
  palette (`export_models` writes `__w1..3` variants). Only `gaus2011/2012` (model 5925,
  unreferenced) use the per-mission range.
- **Rock formations** (category 250) have no texture in the model. The spawner applies
  `SetModelTexture(model, 2482 + world)` (type-1 128x128 bitmaps).
- **RWX vertex rule**: vertices are transformed by the CTM in effect when they are emitted.
  `ClumpBegin` makes the CTM the child's local transform and resets it to identity inside.
  Rock models rely on the first rule.

### Orientation and camera (R1, verified 2026-10-12)
Checked by rendering the mission viewer under all combinations of forward axis, heading sign
and Z mirror, and comparing them with windowed screenshots of the original (1-1 start view,
turned left and right) and with the tiling of category-252 pieces (1-3 top view).
- **No mirror.** Raw game `x`/`z` map straight onto Godot X/Z (and model space is raw RW, see
  "Model stream"). At the 1-1 start the dead tree is on the left and the bush and walker are
  just left of centre, as in the original. Mirrored renders swap them.
- **Heading sign +1.** `ObjectYaw(h)` equals Godot `rotation_degrees.y = h/100`: positive
  headings turn +X toward -Z. Proof: the category-252 trench in 1-3 is continuous with +1 and
  broken with -1.
- **Objects face local +Z.** The camera looks along `Basis(Y, h) * +Z`, i.e. Godot camera yaw
  = h/100 + 180. The chase camera `AttachCamera(obj, 0, 0, 10, -20)` (`script_2170`) sits
  behind the object at negative z. The cockpit camera is `AttachCamera(G973, 0, 0, 44, 0)`
  (`script_2191`) or `AttachCamera(G973, GetProperty(G973, 10), 0, L1, 0)` (`script_2171`).
  Facing -Z (the old viewer default) put the 1-1 start camera against the map-edge rocks.
- **Category 252** (`script_2524`): 1200x1200 pieces whose model origin is a corner (local
  [0,1200]^2). The layout gives the centre, and the spawner first moves to the corner:
  0 → (-600,-600), 9000 → (-600,+600), 18000 → (+600,+600), -9000 → (+600,-600), i.e.
  `origin = centre - R(h)*(600,600)`.
- **Mission start camera**: `script_2528` runs `SetCamera(x_row1, 0, z_row1, 0, 0, 100)`, and
  the camera is then attached to the player. The meaning of the 6th argument is unverified.
  `SetCameraYaw(G1819)` (G1819 = 0) is a look offset. `SetCameraClipping(10, 3000|5000|7000)`
  by detail level `G2117` (`script_2529`), so near = 0.1 model units.
- **FOV (measured, not decoded)**: about **50 degrees vertical** at 640x480 (64 degrees horizontal), with pitch
  0 (horizon on the screen centre line). Fitted from the bush and tree positions at the 1-1
  start, to within a few pixels. The exact value still needs `SetCamera` /
  `RwSetCameraViewwindow` in RENDER.R32.
- **Mission bounds** `script_2515(a, b, c, d)` → G1833..G1836. The ground loops run x from
  G1834 to G1833 and z from G1836 to G1835 (1-1: x in [-9150, 10200], z in [-10200, 3000]).

## Remake-relevant (Goal 2)
- All gameplay logic is in script bytecode (key 5) + RENDER.R32 natives (AI tasks/goals,
  movement behaviours: pursue/evade/flock/follow, collision, projectiles, damage/health).
- Unit stats in `LABTEXT.DAT` (vehicle database text), trivia in `TRIVIA.DAT/.IDX`.
- Assets (models, textures, sprites, audio, FMV) are all extractable from the 7L archive.
  Models and textures: done (`tools/export_models.py` → `remake/game/_import/`, viewed with
  the Godot model viewer). Object definitions, palettes and the FRME format are decoded (see
  below); FRME export to glTF (R4) and the metre scale (0.125 m/unit hypothesis) are still
  open. Handedness is settled (no mirror, see "Orientation and camera").
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
  `res7l.read_object`. Layout: `u32 slots`, then records: `[1,a,b]`, `[2,min,max,restype,res]`,
  `[6,interval,script]` update script, `[8,model]`, and finally `[7,size,n,props[n]]`, the
  property array that GetProperty/SetProperty index (runtime object +0xe4 = record count,
  properties at +0xec+16*count). `size` is usually 144. Templates seed only a few properties.
  Scripts set the rest (unit stats come from arrays via SetProperty). All 483 decode. In the
  shipped data every one of the 1136 range records has restype 19 (a script run when the camera
  distance, float32 min..max, enters the band; unit LOD bands use 2147..2150) and no template
  uses kinds 1 or 8; the loader accepts them anyway. Update records: `[6, 30, 1723]` on the
  42 vehicle templates, `[6, 1000, 0]` / `[6, 30, 0]` on most others.
- **Runtime object struct** (RENDER.R32, from `FUN_10006446`): the object list is the module
  global `DAT_10040264` (array of object pointers, capacity 2500) with the count at
  `DAT_10040268`; per object `+0xc/+0x10/+0x14` = float x, y, z, `+0x54` flags (byte `+0x55 & 5`
  = hidden, `& 0x80` no sort), `+0x58` float radius, `+0x88` sort key, `+0x8c` squared distance
  to the camera (written each frame), `+0x98` model, `+0xe4`/`+0xec` properties as above. The
  R2 spec has the exported getter addresses to decompile for the rest.
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

## Gameplay systems (R2-R9 research, 2026-10-12; checked and folded in by R0, 2026-10-14)
The backlog specs `docs/backlog/R2..R9` hold the detail (script ids, every property seen,
export addresses). This section keeps the facts the remake builds on. "H" marks a hypothesis.

### Player, boarding, camera, bounds (R5, R2)
- **Player = G973**: mission start script 8737 sets `G973 = ArrayGet(layout, 1, 1)` (layout
  row 1). Commandeer `script_2243` sets `G1826` = the old body. 1-1 globals: G1 = player,
  `G33[0..4]` = the five Mercs, `G13[0]` = the Prowler to board, `G625[0..1]` = waypoints.
- Vehicle/pilot props: 0 class code (<100 infantry, 100-199 vehicle, ≥200 structure, 500
  waypoint), 54 side, 77 control (1 player, -1 AI, 0 unmanned, -1000 cannot be boarded), 78
  pilot, 115 cockpit type (row of array 2216), 126 (on the pilot) vehicle occupied, 127 last
  vehicle. Board = `script_2223` (pilot parked at y=1000), dismount = `2226` (occupant at
  vehicle + (100, 0, -150) world units), eject all = `2225`, contact boarding `2229` → `2240`
  (needs `DotProduct(actor, 0, target, 0) >= 9000`).
- Camera modes `G972`: 1 cockpit `AttachCamera(G973, prop10, 0, dy, 0)`, 2 trailing (base
  30 infantry / 47 vehicle, zoom-out d += 3 every 40 ms up to 15/30; `AttachCamera(G973, 0,
  0, base + 2d, -12d)`), 4 external, 5 = script 2170. Scripts 2171, 2191-2194.
- **Bounds**: `script_2515(xmax, xmin, zmax, zmin)` → G1833..G1836. The ground scripts (2418
  for the desert) tile exactly that rectangle. Outside: 2359/2360 warn (waves 2352-2357),
  2363/2364 escalate, 2365/2366 kill. Nothing in the scripts clamps the position.
- Out-of-mission objects: the object list holds 2500 slots; ~823 live and 94 with a model in
  the 1-1 cockpit (R2 probe).

### Movement (R3; parameters read from scripts, natives not decompiled yet)
- Props: 12 throttle setpoint (`script_2064` clamps to [prop36, prop35]; keys add ±5), 34
  current forward velocity (`script_2062` → `SetVelocityForward`), 35/36 max forward/reverse
  throttle, 33 creep speed when turning from a standstill, 15 ? (set by 2066, read natively?),
  37 yaw command (-1/0/+1), 20-24 torso twist (`script_2070`, `StepTwist`), 25-32 weapon pitch
  (`script_2074`), 55-57 model dimensions (`SetModelDimensions` from the rest FRME), 136/137
  backups of 35/36 (`script_2315` restores them).
- Per tick: player update script 1727, AI units 1723 (template record `[6, 30, 1723]`), both
  → `script_1728`: `UpdateTimeStep(obj, dt, 41)`, `UpdateCollideCheck(obj, G1814, 30, 0)`,
  collision response 2227, clump twist/pitch 2077. `SetTargetAxis(obj, prop37, 2, dt)` turns,
  `ApproachTargetSpeed(obj, dt)` (2065) moves the velocity toward the setpoint.
- **Codex speed = prop35 x 0.45 kph** for 19 of the 20 vehicles (Venom 100 → 31.5 is the
  outlier; the Lion uses its campaign branch, 200). H: prop35 is game units per second.
- Controls: arrays 2548-2552 are the five keyboard presets (63 x 8 per action: `[action,
  oneshot, mod1, key1, mod2, key2, mod3, key3]`, Win32 VK codes; mod 1 CTRL, 2 SHIFT, 3
  joystick input, 5 plain key, 0 any modifier (H)); array 2544 (98 x 17) maps action id → handler
  script (0 = handled natively: turn, throttle, torso, pitch, fire, pan). Control schemes are
  scripts 1978/1979 (throttle) and 1980. Preset 0 bindings are listed in the R5 spec. The
  default preset is unknown.
- **Difficulty `G2114`** ∈ {0, 1, 2}: a three-way option set by scripts 6936/6937/6938 (H:
  the difficulty setting; no string is attached in the scripts). Mission 1-1 (8737) deactivates
  3/2/1 of its five Mercs by it and sets the kill target `G2432` = 2/3/4; the AI fire decision
  1677 fires only if `Random(1, 3 - G2114) == 1`. Detail level is `G2117` (clip distance).

### Animations (R4; file format verified over all entries)
- **FRME** = `char[4] "FRME"; u32 nparts; u32 nframes; u32 0`, then `nframes x nparts` records
  of 12 float32: a 4x3 row-vector matrix (rows 0-2 rotation/scale, row 3 translation), the RW
  `TransformCTM` without its last column. **Frame-major**; part p is the clump with tag p+1;
  matrices are **parent-relative** and equal the clump matrices of the model for the 1-frame
  rest poses (2597/2604/2611 vs Prowler LODs 2583/2589/2595). Size = 16 + 48·P·F for 331 of
  332 non-empty entries; **4733** says 10 x 71 but holds 700 records (70 frames). Scale is
  real (17,619 of 74,905 matrices have non-unit rows).
- Setup per unit (in the init script's callee, e.g. 2631): `addAnimation(obj, index, type,
  frme_lod0, frme_lod1, frme_lod2, n, a, b, script)`, `addTrigger(obj, frme, event, target,
  flag)`, `installAnimationType(obj, 11)` (11 = rest pose, 1 frame). Types 0-4 on HAWCs,
  5/7/9/10 kneel/prone/get-up on infantry (H). `animationSetupProps(12, 33, 15)` once at 3D
  init (2564). Meanings of n, a, b, the trigger events and the frame rate: open. Since the
  scripts set speed through prop 12 / `SetVelocityForward`, animation probably does not drive
  movement (H until `doAnimationUpdate` is read).

### Weapons (R6)
- **Array 1281** (32 x 25), one row per weapon; `script_1660(id)` returns the row. Columns:
  0 id, 1 class (1 energy, 2 gun, 3 guided missile, 4 rocket; names H), 2 ? (unread by
  scripts), 4 guided, 5 projectile speed, 6 damage, 7 reload/recharge, 8 recharge modifier, 9
  projectile factory script (1691..1707, clones an OPRT template), 10 gravity, 11 fire wave,
  12/13 min/max range, 15 shield-resist (→ prop 50), 16 shield drain (→ 52), 17 second-pool
  damage (→ 51), 18/19 splash damage/radius (→ 53/54), 20-22 impact effect templates, 23 ammo
  base (default ammo = x1.5, cap x2), 24 network object type; 3 and 14 are always 0.
- **Weapon id → name** (script 1716 draws key-4 strings by offset; checked against all 24
  loadouts in R0): 1 FIL-30, 2 P2MEC, 3 FLECH, 4 SAG/5T, 5 3cROCK, 6 3cREAP, 7 VISOM, 8 GRAY7,
  9 PUG, 10 CHUM, 11 DASY, 12 AIM-9, 13 HOMP11, 14 RUPP, 15 HSSO, 16 SREM, 17 LRIP, 18 CETI,
  19 RAID, 20 zWASP, 21 UNKPA, 22 GAUS30, 23 GAUS20, 24 PRIF44, 25 EGGR, 26 GASHR, 27 ECMp,
  28 POPPR, 29 ARC-M, 30 WaRT, 31 TAR-12, 32 LaserSite.
- Mounts: `Clone(1282)` (8 x 9) → prop 66, count prop 67; `script_1656(obj, id, ammo,
  hardpoint)` adds one (hardpoint ≤ prop 102). Fire: 1675 (action) → 1678 → 1679 → 1682
  (projectile: props 42 shooter, 58 row, 35/44/46/50-54, `SetGravity`). Callback table
  `G1861` (2564): 2228 hit, 1689 end, 1683, 1681 recharge, 2055/2058 stat changes, 430 sector
  lookup. Damage: 1708 (stat-A reduction), 1709 (split a/b), 2291/2292 (per-clump health
  prop 85 from `DefaultClumpHealths`), 2300 (random clump). **Stat A (97/94) vs stat B (95/98)**:
  which is armour and which shields is open; the damage scripts make 97/94 behave like shields.
- Spatial hash for collisions: array 427 (26 x 26 cells of 1200 units from -15600), 430-432.

### AI (R7)
- Per tick: update 1723 → `script_419` (think countdown prop 19 reloaded from prop 18;
  retarget timer prop 124 → 2339 vehicles / 2351 infantry) → `script_417` runs the current
  task script, then 403 drains the command queue (prop 53).
- Task list: `script_412` → `setTaskProps(58, 60)`, prop 58 = `Clone(411)` (10 tasks x 9
  fields: 0 task script, 3 target, 4-6 parameters; rest H), prop 60 = current index. Natives
  `insertTask/setCurrentTask/setNextTask(obj, script, prio, target, f4..f8)`, `existsGoal`,
  `activateGoal`, `completeTask`/`doNextTask`; hook `G991` on every switch.
- Task scripts 2016-2031 (names H): 2016 move, 2017 board, 2018 follow, 2019 attack (→ 2020
  vehicle / 2021 infantry), 2022 turret, 2023 guard object, 2024 guard position + scan, 2025
  harass, 2026 flee, 2027 strafe/circle, 2028 patrol, 2029 approach + parallel, 2030 circle,
  2031 hold. Order wrappers 2342-2349; movement wrappers 2032-2038 → MoveInCircle, MoveToEvade,
  MoveToFlock, MoveToFollow, MoveToParallel, MoveToPursue, MoveToTrueLead (RENDER natives).
- Targeting: 2015 → 2337 picks the nearest manned hostile within prop 40 (sensor range) from
  the 150-slot list `G1816`; hostility 2080 (prop 113 IFF codes differ; infantry compare side
  prop 54). Threat matrices 2316-2318 (41 x 41 by AI slot prop 59); 2323 sums damage over 60
  ticks (`G1868`), 424 retaliates. Default task from 2530: guard and scan 3000 units.
- Mission hooks: G985 destroyed, G984 vehicle entered, G988 spotted, G983, G987 damage, G992.

### Scenery and world textures (R9)
- Spawner `script_2523(mission, layout, world)`: 251 `SetLevel -50`, 570 `SetLevel -25`, 252
  corner tweak `script_2524`, 250 `SetModelTexture(model, 2482 + world)`. Scripts 2090/2092
  clone model prop 1 or 2 and apply `SetModelTexture(prop 3)` when set; who sets prop 3 is open.
  No other scenery gets a texture call; the per-world look comes from the palette ranges above.
