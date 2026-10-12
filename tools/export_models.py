"""Export G-Nome 3D models (7L MODL/MPRT) to glTF 2.0 and textures (type 2) to PNG.

usage: python -I tools/export_models.py <G-NOME.BIN> <outdir> [--only N[,N...]]

Writes <outdir>/textures/<name>.png and <outdir>/models/<modl|mprt>_<index>.gltf (+ .bin).
Each RenderWare clump becomes a glTF node, named "clump_<tag>" when the clump has a tag
(SetTag; tags identify parts for animation and damage). Its local matrix is the CTM in
effect at ClumpBegin. Vertices are clump-local; RW's row-vector matrix maps 1:1 onto
glTF's column-major array.
"""
import base64
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bitmap7l  # noqa: E402
import res7l  # noqa: E402
import rwstream  # noqa: E402

IDENT = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]


def basename(path):
    return path.replace("/", "\\").rsplit("\\", 1)[-1].lower() if path else None


def matmul(a, b):
    """Row-vector convention: result = a * b (a applied first)."""
    return [sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4)) for r in range(4) for c in range(4)]


class Clump:
    def __init__(self, matrix):
        self.matrix = matrix
        self.tag = None
        self.verts = []   # (x, y, z, u, v)
        self.tris = {}    # material key -> [i0, i1, i2, ...] (0-based)
        self.children = []


def build(data):
    """Run a MODL/MPRT stream and return the root clump list."""
    roots = []
    stack = []            # open clumps
    ctm = IDENT[:]
    ctm_stack = []
    surf = {"color": (1.0, 1.0, 1.0), "opacity": 1.0, "texture": None, "surface": (0.3, 0.7, 0.0)}
    surf_stack = []

    def add_tri(idx):
        c = stack[-1]
        key = (surf["color"], surf["opacity"], surf["texture"])
        c.tris.setdefault(key, []).extend(i - 1 for i in idx)

    for _, op, a in rwstream.decode(data):
        if op == "ClumpBegin":
            c = Clump(ctm)
            (stack[-1].children if stack else roots).append(c)
            stack.append(c)
            ctm_stack.append(ctm)
            ctm = IDENT[:]
            surf_stack.append(dict(surf))
        elif op == "ClumpEnd":
            stack.pop()
            ctm = ctm_stack.pop()
            surf = surf_stack.pop()
        elif op == "TransformBegin":
            ctm_stack.append(ctm)
        elif op == "TransformEnd":
            ctm = ctm_stack.pop()
        elif op == "TransformCTM":
            ctm = matmul(a[0], ctm)
        elif op == "IdentityCTM":
            ctm = IDENT[:]
        elif op == "TranslateCTM":
            ctm = matmul([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, a[0], a[1], a[2], 1], ctm)
        elif op in ("ScaleCTM", "RotateCTM"):
            raise NotImplementedError(op)
        elif op == "SetTag":
            stack[-1].tag = a[0]
        elif op == "SetSurfaceColor":
            surf["color"] = tuple(round(x, 4) for x in a)
        elif op == "SetSurfaceOpacity":
            surf["opacity"] = round(a[0], 4)
        elif op == "SetSurface":
            surf["surface"] = tuple(a)
        elif op == "SetSurfaceTexture":
            surf["texture"] = basename(a[0])
        elif op == "Vertex":
            stack[-1].verts.append((a[0], a[1], a[2], 0.0, 0.0))
        elif op == "VertexExt":
            uv = next((v for k, v in a[3:] if k == "uv"), (0.0, 0.0))
            stack[-1].verts.append((a[0], a[1], a[2], uv[0], uv[1]))
        elif op == "Triangle":
            add_tri(a)
        elif op == "Quad":
            add_tri([a[0], a[1], a[2], a[0], a[2], a[3]])
        elif op == "Polygon":
            idx = a[1]
            for k in range(1, len(idx) - 1):
                add_tri([idx[0], idx[k], idx[k + 1]])
    return roots


class Gltf:
    def __init__(self):
        self.g = {"asset": {"version": "2.0", "generator": "g-nome-rea export_models.py"},
                  "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [],
                  "materials": [], "accessors": [], "bufferViews": [], "buffers": [],
                  "textures": [], "images": [], "samplers": [{"magFilter": 9728, "minFilter": 9986}]}
        self.bin = bytearray()
        self.mats = {}
        self.imgs = {}

    def view(self, blob, target):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.g["bufferViews"].append({"buffer": 0, "byteOffset": len(self.bin),
                                      "byteLength": len(blob), "target": target})
        self.bin += blob
        return len(self.g["bufferViews"]) - 1

    def accessor(self, blob, ctype, count, typ, target, mn=None, mx=None):
        acc = {"bufferView": self.view(blob, target), "componentType": ctype, "count": count, "type": typ}
        if mn is not None:
            acc["min"], acc["max"] = mn, mx
        self.g["accessors"].append(acc)
        return len(self.g["accessors"]) - 1

    def material(self, key, tex_uri):
        if key in self.mats:
            return self.mats[key]
        color, opacity, tex = key
        m = {"name": tex or "color", "pbrMetallicRoughness": {
            "baseColorFactor": [1, 1, 1, opacity] if tex else [*color, opacity],
            "metallicFactor": 0.0, "roughnessFactor": 0.9}}
        if opacity < 1:
            m["alphaMode"] = "BLEND"
        if tex and tex_uri(tex):
            if tex not in self.imgs:
                self.g["images"].append({"uri": tex_uri(tex)})
                self.g["textures"].append({"source": len(self.g["images"]) - 1, "sampler": 0})
                self.imgs[tex] = len(self.g["textures"]) - 1
            m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": self.imgs[tex]}
        self.g["materials"].append(m)
        self.mats[key] = len(self.g["materials"]) - 1
        return self.mats[key]

    def node(self, c, tex_uri):
        n = {"name": "clump_%d" % c.tag if c.tag is not None else "clump"}
        if c.matrix != IDENT:
            n["matrix"] = c.matrix
        if c.verts and c.tris:
            pos = b"".join(struct.pack("<3f", *v[:3]) for v in c.verts)
            uv = b"".join(struct.pack("<2f", *v[3:]) for v in c.verts)
            mn = [min(v[i] for v in c.verts) for i in range(3)]
            mx = [max(v[i] for v in c.verts) for i in range(3)]
            pa = self.accessor(pos, 5126, len(c.verts), "VEC3", 34962, mn, mx)
            ua = self.accessor(uv, 5126, len(c.verts), "VEC2", 34962)
            prims = []
            for key, idx in c.tris.items():
                ia = self.accessor(struct.pack("<%dI" % len(idx), *idx), 5125, len(idx), "SCALAR", 34963)
                prims.append({"attributes": {"POSITION": pa, "TEXCOORD_0": ua}, "indices": ia,
                              "material": self.material(key, tex_uri)})
            self.g["meshes"].append({"primitives": prims})
            n["mesh"] = len(self.g["meshes"]) - 1
        self.g["nodes"].append(n)
        me = len(self.g["nodes"]) - 1
        kids = [self.node(k, tex_uri) for k in c.children]
        if kids:
            self.g["nodes"][me]["children"] = kids
        return me

    def save(self, path):
        name = os.path.splitext(os.path.basename(path))[0] + ".bin"
        self.g["buffers"].append({"uri": name, "byteLength": len(self.bin)})
        for k in [k for k, v in self.g.items() if v == []]:
            del self.g[k]
        with open(path, "w") as f:
            json.dump(self.g, f, separators=(",", ":"))
        with open(os.path.join(os.path.dirname(path), name), "wb") as f:
            f.write(self.bin)


def export_textures(bin_path, d, ents, keys, outdir):
    o, s = keys[6]
    pal = bitmap7l.palette_from_entries(d[o:o + s])
    os.makedirs(outdir, exist_ok=True)
    have = set()
    skipped = 0
    for e in ents:
        if e[1] != 2 or e[4] == 0:
            continue
        raw = res7l.read_entry(bin_path, e)
        for off, _ in bitmap7l.texture_blocks(raw):
            try:
                name, r, px = bitmap7l.parse_texture_block(raw, off)
            except NotImplementedError:
                skipped += 1
                continue
            b = basename(name)
            if b in have:
                continue
            have.add(b)
            bitmap7l.write_png(os.path.join(outdir, os.path.splitext(b)[0] + ".png"),
                               r["w"], r["h"], px, pal)
    print("texture blocks skipped (LZW)", skipped)
    return have


def main():
    bin_path, outdir = sys.argv[1], sys.argv[2]
    only = None
    if "--only" in sys.argv:
        only = {int(x) for x in sys.argv[sys.argv.index("--only") + 1].split(",")}
    d, ents, keys = res7l.load(bin_path)
    texdir = os.path.join(outdir, "textures")
    have = export_textures(bin_path, d, ents, keys, texdir)
    mdir = os.path.join(outdir, "models")
    os.makedirs(mdir, exist_ok=True)
    missing = set()

    def tex_uri(t):
        if t in have:
            return "../textures/%s.png" % os.path.splitext(t)[0]
        missing.add(t)
        return None

    n = 0
    for e in ents:
        if e[1] not in (7, 8) or (only and e[0] not in only):
            continue
        roots = build(res7l.read_entry(bin_path, e))
        g = Gltf()
        g.g["scenes"][0]["nodes"] = [g.node(c, tex_uri) for c in roots]
        g.save(os.path.join(mdir, "%s_%05d.gltf" % ("modl" if e[1] == 7 else "mprt", e[0])))
        n += 1
    print("textures", len(have), "models", n, "missing textures", len(missing), sorted(missing)[:10])


if __name__ == "__main__":
    main()
