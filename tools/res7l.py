"""Reader for 7th Level "7L" resource archives (G-NOME.BIN + G-NOME.NNN volumes).

Layout derived from RTLIB32.DLL (ResOpenFile @ 0x10045d57 and helpers):

  Header (0x1a8 bytes, byte-sum == 0 mod 256)
    0x000  u16  magic 'L7' ("7L")
    0x002  u16  header size (0x1a8)
    0x004  char[2] "32" (platform)
    0x006  pascal-ish title ("G-Nome")
    0x056  u16  version (must be 2)
    0x05c  u32[11] cumulative chunk sizes of the script block (key 5)
    0x11c  u32  script chunk count
    0x128  u32  extra (dynamic) index slots
    0x138  u32  index offset
    0x13c  u32  index size (entries * 10)
    0x140 + (n-1)*8   {u32 offset, u32 size} for "key resource" n:
             3 = 8-byte records, 4 = string constants, 5 = script bytecode,
             6 = ?, 10 = plugin names (render/netgn/smacker),
             11 = native function import names
  Index entry (10 bytes): u8 type, u8 volume, u32 offset, u32 size
    types 1..12 live in volume file "<base>.%03d" % volume
    types 13..22 live inside the BIN's script data
"""
import collections
import os
import struct
import sys

TYPE_NAMES = {
    1: "bitmap", 2: "texture", 4: "FRME", 7: "MODL", 8: "MPRT",
    9: "OB3D", 10: "OPRT", 11: "array", 12: "wave",
}


def load(path):
    d = open(path, "rb").read()
    if d[:2] != b"7L":
        raise ValueError("not a 7L archive")
    io, isz = struct.unpack_from("<II", d, 0x138)
    ents = [(i, *struct.unpack_from("<BBII", d, io + i * 10)) for i in range(isz // 10)]
    keys = {}
    for n in range(1, 12):
        o, s = struct.unpack_from("<II", d, 0x140 + (n - 1) * 8)
        if s:
            keys[n] = (o, s)
    return d, ents, keys


def read_entry(bin_path, ent):
    """Return raw bytes for an external (type 1..12) entry."""
    _, t, v, o, s = ent
    base = os.path.splitext(bin_path)[0]
    with open("%s.%03d" % (base, v), "rb") as f:
        f.seek(o)
        return f.read(s)


def read_internal(d, keys, ent):
    """Return raw bytes for an internal (type 13..22) entry; offsets are relative to key 5."""
    _, t, v, o, s = ent
    base = keys[5][0]
    return d[base + o:base + o + s]


def read_array(bin_path, ent):
    """Decode a 7L type-11 array (script data table; RTLIB loader FUN_1001218d).
    Header 0x3c bytes: u32 (runtime ptr), u32 byte_size, u32 ?, u32 resource_id, u32 ndims,
    u32 strides[5], u32 dims[5]; then int32 data. Returns (dims, flat list of ints)."""
    raw = read_entry(bin_path, ent)
    hdr = struct.unpack_from("<15I", raw, 0)
    nd = hdr[4]
    dims = list(hdr[10:10 + nd])
    n = hdr[1] // 4
    return dims, list(struct.unpack_from("<%di" % n, raw, 0x3c))

def read_object(bin_path, ent):
    """Decode an OB3D/OPRT object template (RENDER.R32 loader FUN_100043f0).
    u32 magic, u32 slots, then records until type 7:
      [1, a, b]                     type 1 (a, b)
      [2, min, max, restype, res]   restype 7 (MODL): model LOD for distance min..max,
                                    otherwise a script/resource active in that range
      [6, interval, script]         update script
      [8, res]                      model, always
      [7, x, n, props[n]]           property array (GetProperty/SetProperty index), ends
    Returns (records, x, props). Floats are left as raw u32 (use as_float)."""
    raw = read_entry(bin_path, ent)
    w = struct.unpack_from("<%dI" % (len(raw) // 4), raw)
    i, recs = 2, []
    x, props = None, []
    while i < len(w):
        t = w[i]
        if t == 1 or t == 6:
            recs.append((t, w[i + 1], w[i + 2])); i += 3
        elif t == 2:
            recs.append((2,) + tuple(w[i + 1:i + 5])); i += 5
        elif t == 8:
            recs.append((8, w[i + 1])); i += 2
        elif t == 7:
            x, n = w[i + 1], w[i + 2]
            props = list(w[i + 3:i + 3 + n])
            break
        else:
            raise ValueError("unknown object record %d" % t)
    return recs, x, props


def as_float(u):
    return struct.unpack("<f", struct.pack("<I", u))[0]


def main():
    d, ents, keys = load(sys.argv[1])
    print("entries", len(ents))
    print("keys", {k: (hex(o), s) for k, (o, s) in keys.items()})
    by = collections.defaultdict(lambda: [0, 0])
    for _, t, v, o, s in ents:
        by[t][0] += 1
        by[t][1] += s
    for t in sorted(by):
        print(f"type {t:3} {TYPE_NAMES.get(t, ''):8} n={by[t][0]:5} bytes={by[t][1]:10}")


if __name__ == "__main__":
    main()

