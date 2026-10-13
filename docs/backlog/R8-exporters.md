# R8 — Remaining exporters: sprites/UI, waves, Smacker video

Status: **active**: waves done (2026-10-13); sprites and video still todo.

## Progress
- **Waves: done (2026-10-13).** Codec cracked statically (plain headerless IMA ADPCM, see
  `docs/analysis.md` "Waves"). `tools/wave7l.py` (decoder, single-wave CLI) and
  `tools/export_audio.py <G-NOME.BIN> <outdir>` → `<outdir>/audio/wave_<id>.wav` (592, 0
  failures, 44.6 min, ~9 s run) + the two loose WAVs + `<outdir>/data/waves.json` (format,
  duration, peak, flags, literal-id script references, and a `menu` mapping). The menu sounds
  are identified and wired into the remake's `UiSounds` (runtime load from
  `res://_import/audio`, placeholders as fallback).
  Not done: byte-exact comparison against PCM captured from the running game (the decoder's
  tables match the DLL bytes exactly and speech decodes cleanly, so this was skipped); the
  user still has to judge the sounds by ear. `scripts` in waves.json only covers literal ids
  in `DS*Wave(...)` and `script_334(id, ...)`; waves played through variables (arrays such as
  2512 column 7, unit/weapon tables) are not traced yet.

## Goal
Export every remaining asset type from the retail disc into formats Godot 4 can use directly:
- type-1 sprite and UI bitmaps → PNG with the correct palette and transparency, plus a JSON manifest;
- type-12 waves (and the loose `.WAV` files) → PCM WAV;
- `*.SMK` Smacker movies → a video format Godot plays (Ogg Theora), plus an optional lossless master.

These give the remake placeholders for sounds and FMV, and **reference images** (not placeholder
art) for the menus, HUD/cockpit, Lab and briefings: the new UI is built from scratch (R11).
Original data is never committed: all outputs go to `remake/game/_import/` (gitignored).

## Background
- The remake (`remake/README.md`, Phase 0 item 1) still lists "sprites/UI → PNG with the correct
  palette; waves → WAV; SMK → modern video" as open. Models, textures, backdrops and rock
  textures are already exported (`tools/export_models.py`, `tools/export_gamedata.py`).
- RTLIB32.DLL is the 2D sprite compositor and the audio engine. RENDER.R32 plays in-mission
  sounds through DirectSound (`DSLoadWave`/`DSPlayWave`). SMACKER.R32 + SMACKW32.DLL play the FMV
  from the disc's `Source Directory` (see `docs/analysis.md`, "Architecture" and "Configuration").

## What is already known
### Archive and tools (facts)
- `tools/res7l.py`: `load()`, `read_entry()` (types 1..12, in `G-NOME.%03d` volumes),
  `read_internal()` (types 13..21, offsets relative to key 5). All referenced volumes exist in `ISO/G-NOME/`.
- `tools/bitmap7l.py`: `decode_record()` (RLE flag 0x80 and chunked LZW, bottom-up unless flag
  0x40), `palette_from_entries()` (236 RGBx → 256 entries, system colours filled in), and
  `write_png()` (indexed PNG; `transparent=k` makes index k transparent via tRNS).
- Inventory (`.venv\Scripts\python -I tools/res7l.py ISO\G-NOME\G-NOME.BIN`, 2026-10-12):

| Type | n | Meaning | Exported? |
|---|---|---|---|
| 1 | 1240 | bitmaps (sprites, UI, backdrops) | only 12 backdrops + 4 rock textures |
| 2 | 835 | texture libraries | yes (923 PNGs) |
| 4 | 333 | FRME animations | no (R4) |
| 7/8 | 647/154 | MODL/MPRT | yes (glTF) |
| 9/10 | 426/57 | OB3D/OPRT | yes (JSON) |
| 11 | 709 | int32 arrays | yes (JSON) |
| 12 | 592 | waves, 24.3 MB | **no** |
| 13 | 17 | 14-byte records, unknown | no |
| 14 | 82 | look like script statement bytecode (0xAF/0x2C/0xA9 openers) | no |
| 15 | 290 | 16 bytes: `u32 bitmap_id, 0, 0, 0` (always a type-1 id) | no |
| 16 | 66 | u32 lists of type-20 or type-12 ids (sprite sequences? sound sets?) | no |
| 17 | 14 | palettes (944 B) | used |
| 18 | 95 | small records referencing type 13/19 ids | no |
| 19 | 2342 | scripts | disassembled (`tools/script7l.py`) |
| 20 | 913 | mostly 74 bytes; word 7 references type 2/11/9 ids; `Clone` target | no |
| 21 | 628 | 40-byte records; word 6 references a script or bitmap (buttons/hot spots?) | no |

  The meanings of types 13–16, 18, 20 and 21 are **hypotheses** from cross-reference counts
  only. There are no type-22 entries.

### Type-1 bitmaps (measured; decoding is exact)
- All 1240 decode with `bitmap7l.decode_record`: 1168 RLE, 72 LZW. `resource_id` == index for all.
  Hotspot non-zero in 263 (keep it in the manifest: it's the sprite origin).
- Sizes: 47 full-screen 640x480 (menu frames, cockpits, Lab, help pages, the exit advert), 12
  backdrop panoramas 1328x383, and many small cel runs of identical size with consecutive ids
  (e.g. 615–714 at 9x99, 721–812 at 25x103/19x85, 6063–6151 at 18x16). These are probably
  animation strips, gauges or font glyphs.
- **Transparency:** index 0 is used by 582 bitmaps and marks holes (e.g. cockpit windows in
  2621, the main-menu viewport in 8400, all of 8397). The compositor treats it as transparent.
  Pixels never use indices 1–9, and only bitmap 7200 uses 246–255.
- Sample renders with key-6 palette (main menu 8400, Lab-style frame 1181, cockpit 2621,
  controls help 1909, exit advert 2396) all have correct colours.

### How the palette is chosen (strong hypothesis, from the scripts)
- Statement `0xB4` (8 bytes, typed operand; `sb4` in `script7l` output) sets the screen palette:
  - scripts 8, 9 (after `SmackerUnload`), 6000–6002, 6007, 6008, 8390, 9250 use `sb4 2510`;
  - world setup script 2514 uses `sb4 L2`, where `L2 = ArrayGet(2512, row, 1)` is the mission palette.
- Palettes (measured): type-17 2510 and 2511 are byte-identical to key 6. The 12 mission palettes
  (2487–2509, odd ids, all used by array 2512) differ from key 6 **only** in entries 186..245.
- So: **UI/menus/HUD use key 6 (= 2510).** 1102 of 1240 bitmaps use only indices 0..185, so
  their colours are the same under every palette. 138 use indices >185. Among them are the
  backdrops (2486–2508), rocks (2482–2485), 2396, 8400, 7046, 7192, 7200, 7218 and the 84xx
  icon group (77x51 / 83x35, 8406–8459+). Menu ones render correctly with key 6. Backdrops and
  rocks need the mission palette (already handled in `export_gamedata.py`).
- Runtime palette at RTLIB sprite object `+0x1424` (LOGPALETTE, used by `patch/gnomefix.c`
  for `GetSystemPaletteEntries`). This can be read in the running game to confirm.
- Open: whether any screen besides missions sets a non-2510 palette, or uses
  `SpriteChangePalette`/`SpriteFadePalette` ranges (RTLIB exports `ResGetMaxFadeColors`,
  `ResGetMaxTransColors`).

### Type-12 waves (measured header; codec now known, see Progress and analysis.md "Waves")
The text below is the pre-RE research, kept for history. Resolved: f2 = compressed (IMA ADPCM,
4:1, 16-bit out), f0 = load whole into memory; f1 still unconfirmed. `DecompressWave*` is a
separate stream API the game's resource path doesn't use; the decoder is `ima2pcm`.
- 32-byte header, then data: `u32 data_len (= size-32)`, `u8 f0, f1, f2, f3`, `u32 0`,
  `u32 resource_id (= index)`, then a 16-byte PCMWAVEFORMAT `{u16 tag=1, u16 ch, u32 rate,
  u32 bytes/s, u16 align, u16 bits}`.
- Formats: 383 x 22050 Hz mono 16-bit, 205 x 11025 mono 16-bit, 2 x 22050 stereo 16-bit,
  1 x 44100 mono 16-bit, 1 x 11025 mono 8-bit.
- Flag combos (f0,f1,f2,f3): (0,1,1,0) 374, (0,0,1,0) 130, (1,1,1,0) 73, (1,0,1,0) 14,
  (0,1,0,0) 1. Only id 284 has f2 = 0, and only it reads as plain PCM (8-bit 11025, starts
  `80 80 80…`). The others look like noise when read as PCM16.
  **Hypothesis:** f2 = compressed with RTLIB's own codec. Nibble-heavy patterns (`77 77 82 80
  80 08 88…`) suggest 4-bit ADPCM-like, about 4:1, so roughly 37 min of audio. f0/f1 may be
  loop/stream flags.
- RTLIB32 exports `DecompressWaveInit`, `DecompressWaveData`, `DecompressWaveReset`,
  `DecompressWaveExit` (and the encoder `CompressWave*`), plus `AudioCreateWave`,
  `AudioOpenWave`, `ResCreateWaveEvent`, `AudioResampleWave`. RENDER.R32 imports
  `ResCreateWaveEvent` and implements `DSLoadWave`/`DSPlayWave`/`ObjectPlayWave`.
- Scripts call `DSPlayWave(id, 10000, 0, …)` with type-12 ids directly (49 calls; e.g. ids
  307–309). Array 2512 column 7 is a per-world ambient wave.
- Loose files in `ISO/G-NOME/`: `TRK_01B.WAV` (RIFF PCM16 mono 22050, ~20.8 s) and `SQEEL.WAV`
  (RIFF PCM16 mono 22050). Copy them as they are. The CD-audio music is not on the image (P5).

### Smacker movies (measured from headers)
| File | Size | Video | Frames | fps | Duration | Audio |
|---|---|---|---|---|---|---|
| `G-NOME.SMK` | 15.8 MB | SMK2 320x200 | 963 | 15 | 64.2 s | 22050 st 16-bit (Smacker-compressed) |
| `DREAM.SMK` | 15.0 MB | SMK2 320x200 | 1012 | 15 | 67.5 s | 22050 st 16-bit |
| `CREDITS.SMK` | 42.6 MB | SMK2 320x200 | 1380 | 10 | 138 s | 22050 st 16-bit |
| `NEWS.SMK` | 6.5 MB | SMK2 320x200 | 474 | 15 | 31.6 s | 22050 st 16-bit |
| `WILKINS.SMK` | 6.6 MB | SMK2 320x200 | 266 | 15 | 17.7 s | 11025 st 16-bit |

- Movie table = key-4 string constants at offsets 0x00..0x3a: index 0 `domintro.smk` (Dominion
  leftover, not on disc), 1 `g-nome.smk`, 2 `dream.smk`, 3 `credits.smk`, 4 `wilkins.smk`,
  5 `news.smk`. Script 7 is the player: `script_7(movie_index, next_script, …)` →
  `SmackerSetupView(0, 0, 3, 640, 0, 1)` → `SmackerPlayAnimation(…)` → script 9. The callers are
  script_7(2, 11) at boot (intro = DREAM), (3, 8390) credits, (1, 9241), (3, 9245/9244), (4, 9247), (5, 9249).
- The 320x200 frames are presumably shown pixel-doubled to 640x400, letterboxed in 640x480
  (`SmackerSetupView` mode 3 is a guess). Smacker frames carry their own palette.
- `ffmpeg` decodes Smacker (`smk` demuxer, `smackvid`/`smackaud` decoders) but **is not installed**
  (not on PATH). Godot 4's `VideoStreamPlayer` only plays Ogg Theora (`.ogv`) out of the box.

## Plan
1. **Sprites: `tools/export_sprites.py <G-NOME.BIN> <outdir>`.**
   - Decode every type-1 entry and write `<outdir>/sprites/bmp_<id>.png` with the key-6
     palette and index 0 transparent (`write_png(..., transparent=0)`).
   - Leave full-screen opaque backgrounds alone, or mark them `opaque` in the manifest. Their
     index-0 areas are deliberate holes where the 3D view or a movie shows through.
   - For bitmaps that use indices >185 and are referenced from mission/world data, also write
     `bmp_<id>__p<palette>.png` for each relevant mission palette. Don't duplicate what
     `export_gamedata.py` already writes (backdrops, rocks).
   - Write `<outdir>/data/sprites.json`: id, w, h, flags, codec (rle/lzw), hotspot, max index,
     `palette_sensitive`, plus groupings: consecutive same-size runs, and the type-15/16/20/21
     cross-references.
   - Optional: add contact sheets per run (one PNG per strip) to speed up identification.
2. **Identify screens.** Use the script listing (`tools/script7l.py`) to map full-screen
   bitmaps and cel runs to screens (main menu, GAME, Lab, options, briefing, debrief, cockpit
   HUD per vehicle class). Record the result in the manifest or `docs/analysis.md`. Decoding
   types 15/16/20/21 (sprite/cel/button structures) is the way in. That needs RE of RTLIB's
   sprite statements; check `sa4`, `s75`, `sdf`, `s6b`, `sc0`, `sd9`, `s10`, `sb9` in script 7 and the menu scripts.
3. **Wave codec. DONE 2026-10-13** (see Progress). Original plan: RE `DecompressWaveInit/Data/Reset` in RTLIB32. Confirm header flag meanings
   from `AudioCreateWave`/`ResCreateWaveEvent` and RENDER's `DSLoadWave`, and find where the
   decompressed length comes from. Use the REA MCP tools (`open_binary` RTLIB32.DLL →
   `batch_decompile` the exports). Note: the REA backend is shared with other sessions;
   coordinate and `close_binary` when done.
   Then write `tools/wave7l.py` (decoder) and `tools/export_audio.py <G-NOME.BIN> <outdir>` →
   `<outdir>/audio/wave_<id>.wav` (RIFF PCM, original rate/channels) plus
   `<outdir>/data/waves.json` (id, format, flags, duration, which scripts/arrays use it). Also
   copy `TRK_01B.WAV`/`SQEEL.WAV` from the disc folder.
   - Fallback if the codec is slow to crack: inject a DLL (`tools/dev/inject`) that hooks
     `DecompressWaveData` or DirectSound buffer `Unlock` and dumps PCM. This also gives the
     ground truth for step 6.
4. **Video: `tools/export_video.py <disc G-NOME dir> <outdir>`** wraps ffmpeg.
   - Get ffmpeg first. Ask the user before installing, e.g. `winget install Gyan.FFmpeg`, or
     use a portable build path passed with `--ffmpeg`.
   - Per movie: `ffmpeg -i DREAM.SMK -vf scale=640:400:flags=neighbor -c:v libtheora -q:v 8
     -c:a libvorbis -q:a 6 <outdir>/video/dream.ogv`.
   - Optional lossless master outside Godot's import scope (or in a folder with `.gdignore`):
     `-c:v ffv1 -c:a flac dream.mkv`, for future upscaling.
   - Skip `domintro.smk` and record the movie-index table in `<outdir>/data/movies.json`.
5. **Integrate:** add the three commands to `remake/README.md` "Getting started", and describe
   the formats in `docs/analysis.md`.

## Verification
- **Counts:** 1240 sprite PNGs; 592 WAVs + 2 loose; 5 `.ogv`. The exporters exit non-zero on
  any decode failure.
- **Sprites vs the original:** use `tools/dev/drive.ps1` (windowed, `Display=1`; no need to
  ask) to screenshot the main menu (`wait:4, key:SPACE, wait:2, shot:menu`), the GAME screen
  (`click:162,455`), the Lab and the options (buttons at y≈455 in bitmap 8400). Also take the
  mission 1-1 cockpit (path in `CLAUDE.md`). Compare against the exported full-screen PNGs,
  pixel diff outside dynamic areas. Expect near-exact RGB, since windowed mode shows the
  sprite palette as RGB. Write shots to `%TEMP%`, never the repo.
- **Palette check:** read RTLIB's sprite palette at `+0x1424` in the menu with
  `tools/dev/peek.exe` and diff it against key 6 / 2510. Do the same in a mission against
  array 2512's palette for that mission.
- **Audio:** the decoder never over- or under-runs, and durations look plausible. Compare
  byte-exact with PCM captured from the running game (step 3 fallback) for a few ids. Ask the
  user to listen to a sample set (voice lines, weapons, ambient) — sound can't be judged from
  screenshots.
- **Video:** `ffprobe` frame count and duration match the table above, and the audio stays in
  sync for the whole clip. Open one `.ogv` in Godot's `VideoStreamPlayer`. Have the user compare
  against the original FMV by eye: external screenshots of FMV in full-screen 8-bit mode come out
  black (`docs/analysis.md`), and it's not known yet whether windowed mode captures FMV.

## Open questions / risks
- ~~Wave codec is unknown~~ resolved 2026-10-13 (IMA ADPCM). Open: meaning of header flag f1.
- Meanings of internal types 13–16, 18, 20 and 21, and so how bitmaps group into
  sprites/buttons/animations. Without this, sprites are exported by id only.
- Whether index 0 is the only transparent index (`ResGetMaxTransColors` hints at a range).
  Also whether shadows or translucency use colour remapping.
- Whether any UI screen uses a palette other than 2510. Watch the 84xx group and 7046/7192/7200/7218.
- FMV display geometry (doubling/letterbox mode 3) and whether the game alters Smacker palettes.
- Godot importing about 2000 extra files slows the first import. Consider `.gdignore` for masters.
- Copyright: outputs stay in `remake/game/_import/` (gitignored); never commit them.

## Dependencies
- None blocking. Related items:
  - R9 shares the palette logic (mission palettes 186..245).
  - R5 needs weapon/engine sounds as placeholders. Cockpit/HUD sprites are reference only (R16, R17).
  - R10 (menu decode) shares the type-20/21 sprite-structure work.
  - P5 covers the CD-audio music, which is not on the image and not covered here.
  - R2/`tools/dev/inject` infrastructure can be reused for PCM ground-truth capture.

## Notes to fold into analysis.md
- ~~**Type-11 row**~~ folded 2026-10-13 (type 11 = int32 arrays).
- ~~**Type-12 header**~~ folded 2026-10-13 (analysis.md "Waves": header, codec, menu sounds).
- **Palettes:** "the first [type-17 palette] equals key 6" is wrong. **2510 and 2511** equal
  key 6. 2487–2509 (odd) are the 12 mission palettes and differ only in 186..245.
- **Internal types:** the index has types 13..21; there is no type 22.
- **Statement `0xB4`** = set palette (typed operand). The UI uses 2510; script 2514 uses
  array 2512 column 1.
- **Type-1 stats:** 1168 RLE / 72 LZW, 47 full-screen bitmaps, index 0 transparent/hole,
  1102 of 1240 use only indices 0..185.
- **Docstring:** the `tools/bitmap7l.py` module docstring still says LZW is "not implemented",
  but it is (`decompress_chunks`) and 72 sprites use it.
- **Movies:** the key-4 movie table (index 0 = `domintro.smk`), player script 7 and its
  callers, and the SMK header table.
