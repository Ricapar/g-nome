"""Export G-Nome game data (strings, missions, world table, objects, arrays) to JSON.

usage: python -I tools/export_gamedata.py <G-NOME.BIN> <outdir>

Writes into <outdir>/data/ (use remake/game/_import, which is gitignored: this is game data):
  strings.json   all string constants (7L key 4), in order
  missions.json  campaign missions (title, world-table row, objective lines)
  worlds.json    per-mission world setup (array 2512)
  globals.json   initial values of script globals (key 3)
  objects.json   OB3D/OPRT object templates
  arrays.json    every type-11 array (dims + data)
"""
import json
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import res7l  # noqa: E402

WORLD_TABLE = 2512
WORLD_COLS = ["backdrop", "palette", "fog_depth", "fog_r", "fog_g", "fog_b", "world", "wave"]


def strings(d, keys):
    o, s = keys[4]
    return [x.decode("latin-1") for x in re.findall(rb"[\x20-\x7e]{1,}", d[o:o + s])]


def missions(strs):
    """Campaign missions. Titles look like '1-1: Renegade Mercs'. Objective lines sit before
    the titles. Each mission's list starts with a 'Primary:' line, except mission 1-1, whose
    list starts with 'Head for waypoint one'."""
    titles = [s for s in strs if re.match(r"^\d-\d: ", s)]
    obj_lines = strs[strs.index("Head for waypoint one"):strs.index("Pre-Briefing")]
    groups, cur = [], []
    for line in obj_lines:
        # a 'Primary:' line opens a new mission unless the current one has no primary yet
        if line.startswith("Primary:") and any(c.startswith("Primary:") for c in cur):
            groups.append(cur)
            cur = []
        cur.append(line)
    if cur:
        groups.append(cur)
    out = []
    for k, t in enumerate(titles):
        code, name = t.split(": ", 1)
        out.append({"code": code, "name": name, "objectives": groups[k] if k < len(groups) else []})
    return out, len(groups)


def main():
    bin_path, outdir = sys.argv[1], os.path.join(sys.argv[2], "data")
    os.makedirs(outdir, exist_ok=True)
    d, ents, keys = res7l.load(bin_path)

    def dump(name, obj):
        with open(os.path.join(outdir, name), "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=1)

    strs = strings(d, keys)
    dump("strings.json", strs)
    ms, ngroups = missions(strs)
    dump("missions.json", ms)

    dims, v = res7l.read_array(bin_path, ents[WORLD_TABLE])
    rows = [dict(zip(WORLD_COLS, v[r * dims[1]:(r + 1) * dims[1]])) for r in range(dims[0])]
    dump("worlds.json", {"note": "array 2512; row index = world-setup index used by script 2514",
                         "rows": rows})

    o, s = keys[3]
    w = struct.unpack_from("<%di" % (s // 4), d, o)
    dump("globals.json", {"G%d" % w[i]: w[i + 1] for i in range(0, len(w) - 1, 2)})

    objs = {}
    for e in ents:
        if e[1] in (9, 10) and e[4]:
            recs, x, props = res7l.read_object(bin_path, e)
            objs[e[0]] = {"kind": "OB3D" if e[1] == 9 else "OPRT", "records": recs,
                          "prop_slots": x, "props": props}
    dump("objects.json", objs)

    arrs = {}
    for e in ents:
        if e[1] == 11 and e[4] > 0x3c:
            dims, v = res7l.read_array(bin_path, e)
            arrs[e[0]] = {"dims": dims, "data": v}
    dump("arrays.json", arrs)
    print("strings %d, missions %d (objective groups %d), worlds %d, objects %d, arrays %d" % (
        len(strs), len(ms), ngroups, len(rows), len(objs), len(arrs)))


if __name__ == "__main__":
    main()
