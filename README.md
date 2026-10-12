# G-Nome on modern Windows

**G-Nome** is a 1997 mech combat game by 7th Level, Inc. for Windows 95. Its 16-bit installer
can't run on 64-bit Windows. The game itself does start on Windows 10/11, but several graphics
problems make it hard to play.

This repository contains:

- a **compatibility patch** that makes the original game run correctly on Windows 11, plus
  optional quality-of-life features: a window mode, borderless full screen, longer draw
  distance and lower CPU use;
- **reverse-engineering notes and tools** for the game's engine and file formats. These
  support a longer-term goal: a faithful remake on a modern engine that keeps the original
  menus, controls and gameplay.

> **No game data is included.** You need your own copy of the G-Nome CD (or an image of it).
> The repo's `.gitignore` excludes disc images and extracted game files.

## Status

Tested on Windows 11 Pro (build 26200), 3840x1600 desktop:

| Area | State |
|---|---|
| Game starts, menus, briefings | ✅ |
| Intro and in-game movies (Smacker) | ✅ fixed: they were invisible (black screen) |
| Menu backgrounds, cockpit frame | ✅ fixed: missing after palette fades |
| HUD text (weapon names) | ✅ fixed: invisible when created during a fade |
| 3D missions (RenderWare) | ✅ |
| Keyboard controls, sound effects, voices | ✅ |
| Window mode with integer scaling | ✅ |
| Longer draw distance | ✅ |
| CPU use (original busy loop pinned a core) | ✅ about 1–4% |
| Borderless full screen (`Display=2`) | ⚠️ built, not yet tested |
| CD audio music | ❌ needs the audio tracks (see Known issues) |
| Joystick, multiplayer (DirectPlay) | ❓ untested |

## What was wrong, and how it's fixed

The game draws everything with GDI on a 640x480, 256-colour screen. It uses DirectDraw only to
switch display modes. Windows 8 and later emulate 256-colour modes on a true-colour desktop,
and several Windows 95 assumptions break there:

1. **Movies drew off-screen.** RAD's Smacker library (`SMACKW32.DLL`) passes blit coordinates
   as unsigned 16-bit values (e.g. 65216). Windows 95's GDI truncated them to 16 bits, so
   65216 meant -320. Modern GDI is 32-bit, so every frame landed ~65,000 pixels to the right.
   *Fix:* a 6-site byte patch that sign-extends those coordinates (`tools/patch_gnome.py`).
2. **Palette fades left art black.** The engine fades the screen with `AnimatePalette`. On real
   8-bit hardware that recolours pixels already on screen. Under emulation, pixels keep the
   colour they were drawn with, so backgrounds drawn while the screen was black stayed black.
   *Fix:* after each palette step, redraw the full frame from the engine's own 640x480 buffer.
3. **Text sprites vanished.** Text is drawn into a bitmap and read back through the *current*
   palette. During a fade that palette is black, so the text became the transparent colour.
   *Fix:* render the text into a private mask and produce the exact pixel values Windows 95
   did.

Fixes 2 and 3, and all the optional features, live in a small replacement **`ddraw.dll`**
(`patch/gnomefix.c`). The engine (`RTLIB32.DLL`) imports `DirectDrawCreate`, so a `ddraw.dll`
in the game folder loads before anything is drawn. It forwards DirectDraw to the real system
DLL and patches the import tables of the game's modules. No game executable is modified except
`SMACKW32.DLL` (fix 1).

Window mode hands the game a virtual 640x480 screen and reports a 640x480 8-bit palette display
to it. That keeps every module (including RenderWare's 8-bit display driver) on its original
code path. A background thread scales the virtual screen into the window, and mouse and cursor
coordinates are translated both ways.

Full technical notes, including addresses, data structures and dead ends, are in
[`docs/analysis.md`](docs/analysis.md).

## Installing (replicating this setup)

You need:

- the G-Nome CD, or an image of it (mounting an `.iso` in Windows works);
- Windows 10/11;
- [Python 3](https://www.python.org/) (standard library only for the patch script);
- [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/) with the C++
  workload, to build `ddraw.dll` (32-bit / x86).

Steps:

1. **Copy the game.** Copy the `G-NOME` folder from the CD to a folder of your choice, e.g.
   `C:\Games\G-Nome\G-Nome`. Don't run the CD's `SETUP.EXE`; it's 16-bit and won't start.
2. **Patch Smacker** (movie fix). The script checks the file's hash and the original bytes,
   saves a `.orig` backup, and is safe to run twice:
   ```
   python tools\patch_gnome.py C:\Games\G-Nome\G-Nome
   ```
3. **Build and add `ddraw.dll`:**
   ```
   patch\build.cmd
   copy patch\out\ddraw.dll C:\Games\G-Nome\G-Nome\
   ```
4. **Create `7THLEVEL.INI`.** The game reads it from the Windows folder. Unelevated programs
   without a manifest have that path redirected by Windows to
   `%LOCALAPPDATA%\VirtualStore\Windows\7THLEVEL.INI`, so creating the file there works
   without admin rights. Adjust the paths:
   ```ini
   [G-Nome Setup]
   Dir=C:\Games\G-Nome
   Name=G-Nome.exe
   CmdLine=C:\Games\G-Nome\G-Nome\G-Nome.BIN
   Source Directory=D:\G-NOME\
   [G-Nome]
   MaxJoySticks=2
   [audio]
   MidiVolume=100
   WaveVolume=100
   [gnomefix]
   Display=1
   DrawDistance=200
   ```
   `Source Directory` is where the game reads its movies: the CD drive (or mounted image), or
   any folder holding a copy of the CD's `G-NOME` directory.
5. **Run** `G-NOME.EXE G-Nome.BIN` with the game folder as the working directory. A shortcut
   with target `C:\Games\G-Nome\G-Nome\G-NOME.EXE G-Nome.BIN` and "Start in" set to that
   folder works.

### Options (`[gnomefix]` section)

| Key | Default | Meaning |
|---|---|---|
| `Display` | `0` | `0` original full-screen 640x480; `1` window; `2` borderless full screen |
| `Scale` | `0` | Integer zoom for `Display=1/2`; `0` = largest that fits |
| `Stretch` | `0` | `Display=2`: fill the screen at 4:3 (non-integer zoom) |
| `Smooth` | `0` | `1` = filtered scaling instead of sharp pixels |
| `DrawDistance` | `100` | Percent; scales each mission's far clip plane and fog distance |
| `IdleSleep` | `1` | Wait for input instead of spinning when idle (saves a CPU core) |

`ddraw.dll` writes a short log to `%TEMP%\gnomefix.log`.

## Known issues

- **No CD music from most ISO images.** The game plays music as CD audio tracks through MCI
  `cdaudio`. A plain `.iso` holds only the data track. The image used here reserved space for
  the audio but contains only zeros. A full rip (BIN/CUE or similar) or separate audio files
  would allow adding CD-audio emulation to `ddraw.dll`.
- **Occasional crash on exit** (access violation in the C runtime's stream flush inside
  `RTLIB32.DLL`). Seen twice early on, not since `ddraw.dll` was added. Harmless to play,
  but not yet understood.
- `Display=2`, joysticks and DirectPlay multiplayer haven't been tested.

## Repository layout

| Path | Contents |
|---|---|
| `patch/gnomefix.c`, `gnomefix.def`, `build.cmd` | The `ddraw.dll` compatibility layer |
| `tools/patch_gnome.py` | Verified byte patch for `SMACKW32.DLL` |
| `tools/res7l.py` | Reader for the "7L" resource archive (`G-NOME.BIN` + `G-NOME.0xx`) |
| `tools/peinfo.py`, `tools/strs.py` | Small PE-inspection and string-dump helpers |
| `tools/dev/` | Development aids: windowed test automation (`drive.ps1`), a GDI call tracer DLL, DLL injector, memory peeker, stack sampler |
| `CLAUDE.md` | Context file for continuing this work with Claude Code |
| `docs/analysis.md` | Reverse-engineering notes: architecture, formats, every fix |

## Credits

- **7th Level, Inc.** created G-Nome (1997) and its RT engine (`RTLIB32.DLL`).
- **Criterion Software** made RenderWare 2.0, the game's 3D renderer.
- **RAD Game Tools** made Smacker, the video codec and player library.
- **Microsoft** made DirectX, GDI and the Windows APIs this all runs on.

G-Nome and all related names and trademarks belong to their respective owners. This project
is not affiliated with or endorsed by them. It contains no game data; it patches and
documents a copy you already own.

## How this was made (AI tools)

This work was done in a few sessions with AI assistance, directed and tested by a human:

- **[Claude Code](https://claude.com/claude-code)** is Anthropic's agentic coding tool for the
  terminal. It ran the **Claude Opus 5.5** model and did the analysis and implementation:
  reading binaries, forming and testing hypotheses, writing the patch DLL, tracers and scripts,
  and these docs. In the later stages it also launched the game in window mode, drove it with
  simulated input and checked its own screenshots.
- **REA**, a reverse-engineering MCP server, gave Claude Code structured access to
  **[Ghidra](https://ghidra-sre.org/) 12.1.4** for decompilation, cross-references, string
  searches and assembly. That's how the game's DLLs were analyzed without source code.
- **Supporting tools:** Python with [pefile](https://github.com/erocarrera/pefile) and
  [Capstone](https://www.capstone-engine.org/) for PE inspection and disassembly, Microsoft
  Visual C++ Build Tools for the 32-bit DLLs, and PowerShell/Win32 scripts for launching,
  screenshots and input automation.
- Purpose-built diagnostic tools (now in `tools/dev/`): an import-table tracer DLL, a DLL
  injector, a memory peeker and a stack sampler. They traced GDI calls, palette state and
  RenderWare activity in the running game.

The human side covered goals, judgment calls and everything that needed eyes and ears on real
hardware. More than once, a photo of the monitor settled a question no tool could answer.
