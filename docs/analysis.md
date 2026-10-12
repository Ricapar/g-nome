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
| 1 | — | 1240 | 2D sprite bitmaps (compressed; `DecompressBitmap*`) |
| 2 | — | 835 | Textures; embed original path e.g. `\7thlevel\gnome\src\data\bitmaps\mesoonbl.BMP` |
| 4 | `FRME` | 333 | 3D animation frames |
| 7 | `MODL` | 647 | 3D models — tokenized RWX-like stream (vertex 0x3c, uv 0x12/0x14, poly 0x23) |
| 8 | `MPRT` | 154 | model parts |
| 9 | `OB3D` | 426 | 3D object definitions |
| 10 | `OPRT` | 57 | object properties |
| 11 | — | 709 | sound/event records |
| 12 | — | 592 | waves, 22050 Hz (~24 MB, voice + SFX) |
| 13–22 | — | — | inline script-side resources |

Key resources: 4 = string constants (movie names, faction names, weapon names),
5 = script bytecode (~1 MB, 11 chunks), 10 = plugin list, 11 = native import names.

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

## Remake-relevant (Goal 2)
- All gameplay logic is in script bytecode (key 5) + RENDER.R32 natives (AI tasks/goals,
  movement behaviours: pursue/evade/flock/follow, collision, projectiles, damage/health).
- Unit stats in `LABTEXT.DAT` (vehicle database text), trivia in `TRIVIA.DAT/.IDX`.
- Assets (models, textures, sprites, audio, FMV) are all extractable from the 7L archive.
- Next: reverse the RTLIB32 bytecode interpreter to build a script disassembler.
