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


MISSION_TABLE = 6984   # rows: [index, array, type16, main script, array, n]
UNIT_TABLE = 5843      # rows: [template, init script, class, category, variant]
CATEGORY = {141: "Sentry HAWC", 142: "Tactical Defense HAWC", 143: "Cruiser HAWC",
            144: "Heavy Assault HAWC", 161: "Hovercraft", 181: "Armored Support Vehicle",
            182: "Armored Support Vehicle", 22: "Infantry", 23: "Infantry", 24: "Infantry"}
CODEX_MATCH = {141: "Sentry", 142: "Tactical", 143: "Cruiser", 144: "Multipedal Assault",
               161: "Airborne", 181: "Armored Support", 182: "Armored Support"}
# catalogue rows 0-23 are the four factions' vehicles + infantry, in this order
FACTION_ROWS = [("Union", range(0, 6)), ("Darken", range(6, 11)), ("Merc", range(11, 18)),
                ("Scorp", range(18, 24))]


def labtext(path):
    """LABTEXT.DAT: length-prefixed strings. Vehicle records are
    [title, type, name, speed, stat_a, stat_b, height, weight, weapon lines...]."""
    d = open(path, "rb").read()
    s, p = [], 0
    while p < len(d):
        n = d[p]
        s.append(d[p + 1:p + n].decode("latin-1").strip())
        p += 1 + n
    starts = [i for i in range(len(s) - 3) if s[i + 3].endswith("kph") and s[i].endswith(
        ("HAWC", "Vehicle", "Platform"))]
    recs = []
    for k, i in enumerate(starts):
        j = starts[k + 1] if k + 1 < len(starts) else len(s)
        weapons = []
        for line in s[i + 8:j]:
            if line.startswith("1 Swivel") or line.startswith("2 ") or line.startswith("1 ") \
                    or line.startswith("*") or "rounds" in line or "missiles" in line or "rockets" in line:
                weapons.append(line)
            else:
                break
        recs.append({"title": s[i], "type": s[i + 1], "name": s[i + 2], "speed": s[i + 3],
                     "stat_a": int(s[i + 4]), "stat_b": int(s[i + 5]), "height": s[i + 6],
                     "weight": s[i + 7], "weapons": weapons})
    return recs


def script_calls(d, keys, ents, sid, names, depth=1):
    """Text of script sid and the scripts it calls directly (one level)."""
    import script7l
    out, todo, seen = [], [(sid, 0)], set()
    while todo:
        s, dep = todo.pop()
        if s in seen or not (0 < s < len(ents)) or ents[s][1] != 19:
            continue
        seen.add(s)
        code = res7l.read_internal(d, keys, ents[s])
        text = "\n".join(t for _, t, _ in script7l.disasm(code, names))
        out.append(text)
        if dep < depth:
            todo += [(int(x), dep + 1) for x in re.findall(r"script_(\d+)\(", text)]
    return "\n".join(out)


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

    # backdrop panoramas, each with its mission palette
    import bitmap7l
    texdir = os.path.join(sys.argv[2], "textures")
    os.makedirs(texdir, exist_ok=True)
    for row in rows:
        out = os.path.join(texdir, "backdrop_%d.png" % row["backdrop"])
        if not os.path.exists(out):
            pal = bitmap7l.palette_from_entries(res7l.read_internal(d, keys, ents[row["palette"]]))
            r, px = bitmap7l.decode_record(res7l.read_entry(bin_path, ents[row["backdrop"]]))
            bitmap7l.write_png(out, r["w"], r["h"], px, pal)

    # rock formations (unit category 250) get a per-world texture at spawn time:
    # script 2523 calls SetModelTexture(model, 2482 + world) (type-1 bitmaps)
    world_pal = {}
    for row in rows:
        world_pal.setdefault(row["world"], row["palette"])
    for w, pal_id in world_pal.items():
        pal = bitmap7l.palette_from_entries(res7l.read_internal(d, keys, ents[pal_id]))
        r, px = bitmap7l.decode_record(res7l.read_entry(bin_path, ents[2482 + w]))
        bitmap7l.write_png(os.path.join(texdir, "rock_w%d.png" % w), r["w"], r["h"], px, pal)

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
    # unit catalogue + codex
    import script7l
    names = script7l.Names(d, keys)
    codex = labtext(os.path.join(os.path.dirname(bin_path), "LABTEXT.DAT"))
    by_title = {}
    for c in codex:
        by_title.setdefault(c["title"].split(" ")[0], []).append(c)
    dims, v = res7l.read_array(bin_path, ents[UNIT_TABLE])
    units = []
    for r in range(dims[0]):
        row = v[r * dims[1]:(r + 1) * dims[1]]
        if not any(row):
            continue
        u = {"row": r, "template": row[0], "init_script": row[1], "class": row[2],
             "category": row[3], "variant": row[4], "kind": CATEGORY.get(row[3])}
        if 0 < row[0] < len(ents) and ents[row[0]][1] in (9, 10):
            _, _, props = res7l.read_object(bin_path, ents[row[0]])
            u["template_props"] = props
        for fac, rng in FACTION_ROWS:
            if r in rng:
                u["faction"] = fac
                hit = [c for c in by_title.get(fac, []) if CODEX_MATCH.get(row[3], "?") in
                       c["title"] + " / " + c["type"]]
                if hit:
                    u["codex"] = hit[0]
        units.append(u)
    dump("units.json", units)

    # campaign missions: main script, world row, layout array
    dims, v = res7l.read_array(bin_path, ents[MISSION_TABLE])
    mrows = []
    for r in range(dims[0]):
        row = v[r * dims[1]:(r + 1) * dims[1]]
        if not row[3]:
            continue
        text = script_calls(d, keys, ents, row[3], names, depth=1)
        world = re.findall(r"script_2513\((\d+)\)", text)
        layout = re.findall(r"script_2523\(\d+, (\d+),", text)
        bounds = re.findall(r"script_2515\(([^)]*)\)", text)
        mrows.append({"table_row": r, "index": row[0], "main_script": row[3],
                      "world_row": int(world[0]) if world else None,
                      "layout_array": int(layout[0]) if layout else None,
                      "bounds": bounds[0] if bounds else None, "extra": [row[1], row[2], row[4], row[5]]})
    for m, row in zip(ms, mrows):  # table rows 1..22 = campaign missions in order
        m.update(row)
    dump("missions.json", ms)
    dump("mission_table.json", mrows)

    layouts = {}
    for m in mrows:
        if m["layout_array"]:
            dims, v = res7l.read_array(bin_path, ents[m["layout_array"]])
            layouts[m["layout_array"]] = [
                dict(zip(["unit_row", "runtime_id", "x", "z", "y", "heading", "flag"],
                         v[i * dims[1]:(i + 1) * dims[1]])) for i in range(1, dims[0])]
    dump("layouts.json", layouts)
    print("strings %d, missions %d (objective groups %d), worlds %d, objects %d, arrays %d, "
          "units %d, layouts %d" % (len(strs), len(ms), ngroups, len(rows), len(objs), len(arrs),
                                    len(units), len(layouts)))


if __name__ == "__main__":
    main()
