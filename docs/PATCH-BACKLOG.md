# Patch backlog (Goal 1, `patch/` and `tools/`)

**Parked.** We are working on the remake (`REMAKE-BACKLOG.md`) for now. No specs have been
written for these items yet; when one is picked up, write its spec in `docs/backlog/` first
(same structure as the remake specs). The notes below the table are the current source.

| ID | Item | Spec | Status |
|---|---|---|---|
| P1 | Portable install: redirect `7THLEVEL.INI` to the game folder; check save-game location | not written | parked |
| P2 | One-step install script (CD/ISO → patched, configured install) | not written | parked |
| P3 | Guard the occasional exit crash in RTLIB CRT `flsall` (`0x1002a240`, freed `__piob` `0x10060ab8`) | not written | parked |
| P4 | Test matrix: `Display=2`/`Stretch`/`Smooth`, full screen, Alt-Tab, save/load, later missions | not written | parked |
| P5 | CD-audio emulation: hook MCI `cdaudio` and play ripped tracks | not written | parked |
| P6 | Gamepad support (winmm joystick API) | not written | parked |
| P7 | DirectPlay multiplayer over TCP | not written | parked |

## Notes (moved from CLAUDE.md "Open work")
- **P1:** redirect `GetPrivateProfile*`/`WritePrivateProfile*` to the game folder; today the
  INI lands in `%LOCALAPPDATA%\VirtualStore\Windows\7THLEVEL.INI` through UAC virtualization.
  Check where save games (`SGNOME*.SAV`) are written.
- **P2:** copy from CD/ISO, apply the Smacker patch (`tools/patch_gnome.py`), drop in
  `ddraw.dll`, write the INI.
- **P3:** CRT `flsall` at RTLIB `0x1002a240` reads a freed `__piob` (`0x10060ab8`). Not seen
  since `ddraw.dll` was added.
- **P4:** test `Display=2` (+`Stretch`/`Smooth`), full screen with the latest DLL, Alt-Tab,
  save/load and later missions. Full-screen runs need the user's go-ahead (CLAUDE.md launch
  rules).
- **P5:** hook MCI `cdaudio` and play files instead, once the user has a real disc rip or the
  soundtrack files. The ISO's audio region is all zeros. The user also plans to test with the
  original CD-ROM.
- **P6/P7:** later: gamepads (winmm joystick API), DirectPlay multiplayer (TCP only).
