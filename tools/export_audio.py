"""Export every G-Nome wave (7L type 12) to RIFF PCM WAV, plus an index.

usage: python -I tools/export_audio.py <G-NOME.BIN> <outdir>

Writes (use remake/game/_import, which is gitignored: this is game data):
  <outdir>/audio/wave_<id>.wav   16-bit PCM (8-bit for the one raw 8-bit wave), original
                                 rate and channels; decoder in tools/wave7l.py
  <outdir>/audio/<NAME>.WAV      the loose WAV files from the disc folder, copied as-is
  <outdir>/data/waves.json       per wave: header fields, duration, peak, and which scripts
                                 play/load it by literal id (DSPlayWave, DSLoadWave, ...)
The remake loads these at runtime (AudioStreamWAV.load_from_file), so they need no Godot
import step (_import has a .gdignore).
Exits non-zero if any wave fails to decode.
"""
import json
import os
import re
import shutil
import sys
from array import array

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import res7l  # noqa: E402
import script7l  # noqa: E402
import wave7l  # noqa: E402

LOOSE = ["TRK_01B.WAV", "SQEEL.WAV"]
# Literal wave ids as the first argument. script_334(id, ...) is the game's one-shot helper
# (stops the previous one, then DSPlayWave(id, ...)).
WAVE_CALL = re.compile(r"\b(DSPlayWave|DSLoadWave|DSStopWave|DSUnloadWave|script_334)\((\d+)")

# Sounds of the main menu / front end, identified from the menu scripts (docs/analysis.md,
# "Waves"). Kept here so waves.json carries the mapping for the remake.
MENU = {
    8398: "menu ambience loop (script 8315, DSPlayWave loop flag 1)",
    8403: "bottom-bar key select: GAME/NETWORK/LAB/OPTIONS/EXIT (script 8341, also 8538)",
    8404: "side-column slot select, left and right columns (scripts 8353, 8354)",
    74: "denied / not available (script 8350, e.g. SAVE outside a campaign mission)",
    75: "option toggled / confirmed (script 8351, e.g. joystick on/off)",
    131: "Escape on the menu: quit-confirm prompt (script 8312)",
}


def script_refs(d, keys, ents):
    """Map wave id -> sorted list of (script id, call name) for literal-id calls."""
    names = script7l.Names(d, keys)
    refs = {}
    for e in ents:
        if e[1] != 19 or e[4] == 0:
            continue
        code = res7l.read_internal(d, keys, e)
        try:
            for _, text, _ in script7l.disasm(code, names):
                for call, wid in WAVE_CALL.findall(text):
                    refs.setdefault(int(wid), set()).add((e[0], call))
        except Exception:
            pass
    return {k: sorted(v) for k, v in refs.items()}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    bin_path, outdir = sys.argv[1], sys.argv[2]
    adir = os.path.join(outdir, "audio")
    ddir = os.path.join(outdir, "data")
    os.makedirs(adir, exist_ok=True)
    os.makedirs(ddir, exist_ok=True)
    d, ents, keys = res7l.load(bin_path)
    refs = script_refs(d, keys, ents)
    index, failed, total = [], 0, 0.0
    for e in ents:
        if e[1] != 12 or e[4] == 0:
            continue
        try:
            h, pcm, width = wave7l.decode(res7l.read_entry(bin_path, e))
        except ValueError as ex:
            print("FAIL", e[0], ex)
            failed += 1
            continue
        if h["id"] != e[0]:
            print("WARN wave %d header id %d" % (e[0], h["id"]))
        name = "wave_%d.wav" % e[0]
        wave7l.write_wav(os.path.join(adir, name), h, pcm, width)
        frames = len(pcm) // (width * h["channels"])
        if width == 2:
            a = array("h", pcm)
            peak = max(max(a, default=0), -min(a, default=0)) / 32768
        else:
            peak = max((abs(b - 128) for b in pcm), default=0) / 128
        dur = frames / h["rate"]
        total += dur
        rec = {
            "id": e[0], "file": "audio/" + name, "rate": h["rate"], "channels": h["channels"],
            "bits": 8 * width, "frames": frames, "duration": round(dur, 4),
            "peak": round(peak, 4), "compressed": h["compressed"], "flags": h["flags"],
            "scripts": [{"script": s, "call": c} for s, c in refs.get(e[0], [])],
        }
        if e[0] in MENU:
            rec["menu"] = MENU[e[0]]
        index.append(rec)
    src = os.path.dirname(os.path.abspath(bin_path))
    loose = []
    for f in LOOSE:
        p = os.path.join(src, f)
        if os.path.exists(p):
            shutil.copyfile(p, os.path.join(adir, f))
            loose.append("audio/" + f)
    with open(os.path.join(ddir, "waves.json"), "w") as f:
        json.dump({"waves": index, "loose": loose, "menu": {str(k): v for k, v in MENU.items()}},
                  f, indent=1)
    print("waves: %d exported, %d failed, %.1f min total; loose: %d"
          % (len(index), failed, total / 60, len(loose)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
