# CLAUDE.md — G-Nome compatibility & reverse-engineering project

## Goals
1. **Patch** the retail G-Nome (7th Level, 1997, Win95) so it runs well on modern Windows. This
   is largely done; see README.md "Status".
2. **A remake** in Godot 4 under `remake/` (branch `remake`). Gameplay, missions, story and
   vehicles stay faithful to the original. Visuals are modern, MechWarrior-grade: original
   assets serve as placeholders and scale references until new art replaces them. The plan
   and decisions are in `remake/README.md`. Keep documenting formats, behaviours and
   addresses in `docs/analysis.md`.

## Starting a session (how to reorient)
**Current focus: the remake (Goal 2). The patch backlog is parked.**
1. Check `git status` and `git log --oneline -5` on branch `remake` to see what landed last.
2. Open `docs/REMAKE-BACKLOG.md`. Take the item the user names, or else the first `active`
   item, or else the first `todo` item in the recommended order given in that file (currently
   R1 → R0 → R2 → R3 → R5 → R4 → R6 → R7; R8 and R9 can go anywhere).
3. Read that item's spec in `docs/backlog/<ID>-*.md`. It has the background, known facts with
   file paths and addresses, the steps, how to verify, and open questions. Use
   `remake/README.md` for the plan and decisions, and `docs/analysis.md` for format details.
4. If something is still unclear, earlier session transcripts are in
   `%USERPROFILE%\.claude\projects\C--Users-Ricapar-Documents-Git-g-nome-rea\*.jsonl`. They
   are large, so grep them for keywords; don't read them whole.
5. While working, set the item's status to `active` in both the backlog table and the spec.
   When it's finished, set it to `done`, fold anything new into `docs/analysis.md` (including
   the spec's "Notes to fold into analysis.md"), and update dependent specs if their
   assumptions changed. New work found along the way becomes a new backlog item with its own
   spec.

## Read first
- `README.md` covers the user-facing summary: fixes, install steps, INI options, known issues
  and credits.
- `docs/analysis.md` holds the technical notes: engine architecture, 7L archive format, every
  fix with addresses and data structures, and the dead ends. **Update it when you learn
  something.**

## Repo layout
- `patch/gnomefix.c` + `gnomefix.def` + `build.cmd` build `ddraw.dll`, the compatibility
  layer. It is a DirectDraw proxy that IAT-patches the game modules. Build with
  `patch\build.cmd`; output goes to `patch/out/` (gitignored). After building, **check that
  `patch/out/ddraw.dll` was actually produced** before copying it. A failed build leaves the
  old DLL in place.
- `tools/patch_gnome.py` byte-patches `SMACKW32.DLL` (FMV coordinate fix). It checks the hash
  and is idempotent.
- `tools/res7l.py` reads the "7L" resource archive. `peinfo.py` and `strs.py` are small
  helpers.
- `ISO/` (gitignored) holds the extracted disc. `G-Nome (1996).iso` (gitignored) is the disc
  image. Its CD-audio region is all zeros, so there is **no music** in it.

## Environment
- Windows 11, single 3840x1600 monitor, UAC on, unelevated shell. Git Bash + PowerShell.
- MSVC Build Tools 2022 (x86, `vcvars32.bat`); `patch\build.cmd` already handles this.
- Python: create a venv (`pip install -r tools/requirements.txt`) and run scripts with `-I`.
- REA MCP tools (Ghidra 12.1.4 backend) for decompilation. Load them via ToolSearch, use
  `open_binary` on a game DLL, then `batch_decompile`, `xrefs`, `procedure_callers` and
  `read_bytes`. Call `close_binary` when done.
- **Gotcha:** Python heredocs in Git Bash mangle `\r\n`/`\\` escapes inside C string
  literals. Edit C source with the Edit tool, not scripted string replacement.

## Test install & running the game
- **Test install:** `test-install/G-Nome/` (gitignored, ~163 MB). It's a copy of `ISO/G-NOME`
  with the patched `SMACKW32.DLL` (original kept as `.orig`) and a `ddraw.dll`. After
  rebuilding the patch, copy `patch/out/ddraw.dll` into it. To recreate it: copy `ISO/G-NOME`
  → run `tools/patch_gnome.py` on it → copy the DLL in. Save games (`SGNOME*.SAV`) live in
  this folder.
- INI: `%LOCALAPPDATA%\VirtualStore\Windows\7THLEVEL.INI` (UAC virtualization of
  `C:\Windows\7THLEVEL.INI`). Current values: `Dir`/`CmdLine` point at `test-install`,
  `Source Directory=G:\G-NOME\`, and `[gnomefix] DrawDistance=200, Display=1, Scale=0,
  Smooth=0`. **Update `Dir`/`CmdLine` if the install moves.**
- The disc image was mounted as **G:** with `Mount-DiskImage`. Remount it if needed. The game
  reads movies from `Source Directory`.
- Launch: `G-NOME.EXE G-Nome.BIN` with the install folder as working directory.
- Log: `%TEMP%\gnomefix.log`. Crashes: `Get-WinEvent` Application log, Id 1000.

### Launch rules (agreed with the user)
- **Windowed runs (`Display=1`)**: launch, drive and screenshot freely without asking. Keep
  runs short and close the game afterwards.
- **Full-screen runs (`Display=0`, and treat `Display=2` the same)**: first explain what the
  run tests, what the user will see, how long it lasts and what to do, then wait for an
  explicit go-ahead. Full screen takes over the only monitor, and external screenshots of
  8-bit emulated mode come out black.
- Ask the user to judge what screenshots can't show: sound, feel, speed, pop-in.

### Automation (windowed)
`tools/dev/drive.ps1 -Dir test-install\G-Nome -Out <dir> -Steps @(...) [-MaxSeconds n]`
launches the game, finds the window, and runs steps:
- `wait:<s>`, `key:<NAME>`, `hold:<NAME>:<ms>`;
- `click:<x>,<y>`, in game 640x480 coordinates mapped through the window's integer scale;
- `shot:<name>`, which saves a 640x480 PNG of the window and prints elapsed and CPU time.

Then it kills the game. Write screenshots outside the repo (e.g. `%TEMP%`) and view them
with Read.

Other diagnostics in `tools/dev/` (build with `tools\dev\build.cmd`; outputs are gitignored):
- `gtrace.c` → `gtrace.dll`, an IAT tracer for GDI/USER calls with env switches. **Don't use
  it together with gnomefix's hooks**: it overwrites the same import entries.
- `inject`, `peek` and `stacksample` load a DLL into the game, read its memory, and sample
  thread stacks.
- `runtest.ps1` and `brightrun.ps1` are older full-screen-era test runners.

Path from boot to the mission 1-1 cockpit (game coordinates):
`wait:4, key:SPACE` (skip intro) → `click:162,455` (GAME) → `click:40,164` (NEW) →
`click:598,164` (CAMPAIGN) → `wait:3, key:SPACE` (skip briefing animation) →
`click:598,164` (LAUNCH) → `wait:8` → cockpit. Arrow keys steer.

## Key technical facts (details in docs/analysis.md)
- `RTLIB32.DLL` is the 7th Level RT engine: GDI sprite compositor, audio, script VM.
  `RENDER.R32` is the 3D game (RenderWare 2.0, `RWL20.DLL` + driver `RWDL8D20.DLL`).
  `SMACKER.R32`/`SMACKW32.DLL` handle FMV, and `NETGN.R32` handles DirectPlay.
- RTLIB composes every frame in one 640x480 8-bit buffer. RENDER.R32 points a RenderWare
  user raster straight at it. Script natives are exports of the `.r32` plugins, resolved by
  RTLIB through `GetProcAddress`; that is how the draw-distance hook works.
- Windowed mode must present a **640x480x8 palette device** to RTLIB and RenderWare
  (`GetDeviceCaps`, `GetSystemPaletteEntries` built from RTLIB's sprite palette at sprite
  object `+0x1424`). RTLIB's true-colour path never shows the 3D "external draw" region, and
  RenderWare's 8-bit driver refuses other devices.
- Music is CD audio via MCI `cdaudio` (`mciSendCommandA` in RTLIB: `AudioPlayCDTrack` etc.).

## Open work
Tracked in two backlogs (see "Starting a session" above):
- `docs/REMAKE-BACKLOG.md` is **active**: items R0–R9, each with a spec in `docs/backlog/`.
  Specs were written from read-only research: treat their claims as leads to verify.
- `docs/PATCH-BACKLOG.md` is **parked**: items P1–P7 (portable INI, installer, exit crash,
  test matrix, CD audio, gamepad, multiplayer). No specs yet. Don't work on these unless the
  user asks.

## Git
- Remote `origin` = github.com/Ricapar/g-nome. `main` holds the first full commit.
- Never commit game data (`ISO/`, `*.iso`, extracted files) or `patch/out/`.
- **Always clear to commit and push** (standing permission from the user). Commit and push
  often, at every meaningful step, so there are checkpoints to track against. Work on a
  branch (currently `remake`), not `main`.
