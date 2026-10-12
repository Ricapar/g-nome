"""Decoder for G-Nome's tokenized RenderWare 2.0 script streams (MODL / MPRT resources).

The stream is the RWX script API serialised as little-endian u32 words. Each command is a
1-based opcode followed by its arguments. RENDER.R32 runs it with the interpreter
FUN_10003432, which uses the opcode table at 0x10037050: 0x24-byte entries of
{fn, argtype[8]}, terminated by type 0.

Argument types (how many words each consumes):
  1,2,3,4,5,6,8,a,b,c,10  one word (3 = float, 5/a/... = int)
  7                       nothing (pointer to the stream position, used with 0x17)
  9, 0x11, 0x16           length word n, then n words (string / name block)
  0xd                     16 floats (4x4 matrix, RW row-major, translation in row 3)
  0xe                     int array whose length is the previous argument
  0xf, 0x15, 0x17         nothing
  0x12, 0x13              optional vertex subtoken: 0x12 u v | 0x13 nx ny nz | anything else
                          (normally 0x14) = absent; the marker word is always consumed
Opcodes 0x3d/0x3e (types 7,0x17) embed a texture: u32 byteLen, u32 nameLen, name, then
a compressed bitmap record (expanded by RTLIB ResExpandBitmapRec). The whole block is
byteLen bytes from the byteLen word.

Resource header: 4-byte magic ("MODL"/"MPRT") + u32 (meaning unknown), then the stream.
"""
import struct

F, I, MAT, STR, IARR, NONE, VOPT, PTR = "f", "i", "mat", "str", "iarr", "none", "vopt", "ptr"

# opcode: (name, [argkinds])
OPS = {
    0x01: ("AddHint", [I]),
    0x02: ("AddTextureModeToSurface", [I]),
    0x03: ("SetSurfaceAmbient", [F]),
    0x04: ("SetAxisAlignment", [I]),
    0x05: ("Block", [F, F, F]),
    0x06: ("ClumpBegin", []),
    0x07: ("ClumpEnd", []),
    0x08: ("SetSurfaceColor", [F, F, F]),
    0x09: ("Cone", [F, F, I]),
    0x0a: ("Cylinder", [F, F, F, I]),
    0x0b: ("SetSurfaceDiffuse", [F]),
    0x0c: ("Disc", [F, F, I]),
    0x0d: ("SetSurfaceGeometrySampling", [I]),
    0x0e: ("Hemisphere", [F, I]),
    0x0f: ("SetHints", [I]),
    0x10: ("IdentityCTM", []),
    0x11: ("IdentityJointTM", []),
    0x12: ("Include", []),
    0x13: ("IncludeGeometry", []),
    0x14: ("JointTransformBegin", []),
    0x15: ("JointTransformEnd", []),
    0x16: ("SetSurfaceLightSampling", [I]),
    0x17: ("MaterialBegin", []),
    0x18: ("MaterialEnd", []),
    0x19: ("SetSurfaceMaterialModes", [I]),
    0x1a: ("ModelBegin", []),
    0x1b: ("ModelEnd", []),
    0x1c: ("SetSurfaceOpacity", [F]),
    0x1d: ("Polygon", [I, IARR]),
    0x1e: ("PolygonExt", [I, IARR, I]),
    0x1f: ("ProtoBegin", [STR]),
    0x20: ("ProtoEnd", []),
    0x21: ("ProtoInstance", [STR]),
    0x22: ("ProtoInstanceGeometry", [STR]),
    0x23: ("Quad", [I, I, I, I]),
    0x24: ("QuadExt", [I, I, I, I, I]),
    0x25: ("RemoveHint", [I]),
    0x26: ("RemoveTextureModeFromSurface", [I]),
    0x27: ("RotateCTM", [F, F, F, F]),
    0x28: ("RotateJointTM", [F, F, F, F]),
    0x29: ("ScaleCTM", [F, F, F]),
    0x2a: ("SetSurfaceSpecular", [F]),
    0x2b: ("Sphere", [F, I]),
    0x2c: ("SetSurface", [F, F, F]),
    0x2d: ("SetTag", [I]),
    0x2e: ("SetSurfaceTexture", [STR]),
    0x2f: ("SetTextureDithering", [I]),
    0x30: ("SetSurfaceTextureMasked", [STR, STR]),
    0x31: ("SetTextureGammaCorrection", [I]),
    0x32: ("SetSurfaceTextureModes", [I]),
    0x33: ("Op33", [I]),  # table entry has a NULL function
    0x34: ("TransformCTM", [MAT]),
    0x35: ("TransformBegin", []),
    0x36: ("TransformEnd", []),
    0x37: ("TransformJointTM", [MAT]),
    0x38: ("TranslateCTM", [F, F, F]),
    0x39: ("Triangle", [I, I, I]),
    0x3a: ("TriangleExt", [I, I, I, I]),
    0x3b: ("Vertex", [F, F, F]),
    0x3c: ("VertexExt", [F, F, F, VOPT, VOPT]),
    0x3d: ("Texture", [PTR]),
    0x3e: ("TextureMasked", [PTR]),
}


def _cstr(b):
    return b.split(b"\0", 1)[0].decode("latin-1")


def decode(data, start=8):
    """Yield (offset, opname, args) for every command in a MODL/MPRT resource."""
    n = len(data) // 4
    w = struct.unpack_from("<%dI" % n, data)
    i = start // 4
    while i < n:
        off = i * 4
        op = w[i]
        i += 1
        if op not in OPS:
            raise ValueError("unknown opcode 0x%x at 0x%x" % (op, off))
        name, kinds = OPS[op]
        args = []
        for k in kinds:
            if k == F:
                args.append(struct.unpack_from("<f", data, i * 4)[0]); i += 1
            elif k == I:
                args.append(w[i]); i += 1
            elif k == MAT:
                args.append(list(struct.unpack_from("<16f", data, i * 4))); i += 16
            elif k == STR:
                ln = w[i]; i += 1
                args.append(_cstr(data[i * 4:(i + ln) * 4]) if ln else None); i += ln
            elif k == IARR:
                cnt = args[-1]
                args.append(list(w[i:i + cnt])); i += cnt
            elif k == VOPT:
                tag = w[i]; i += 1
                if tag == 0x12:
                    args.append(("uv", struct.unpack_from("<2f", data, i * 4))); i += 2
                elif tag == 0x13:
                    args.append(("n", struct.unpack_from("<3f", data, i * 4))); i += 3
            elif k == PTR:
                blen, nlen = w[i], w[i + 1]
                name_ = _cstr(data[(i + 2) * 4:(i + 2) * 4 + nlen])
                args.append({"name": name_, "offset": i * 4, "size": blen, "name_len": nlen})
                i += blen // 4
        yield off, name, args


def main():
    import sys
    data = open(sys.argv[1], "rb").read()
    print("magic", data[:4], "hdr", struct.unpack_from("<I", data, 4)[0])
    depth = 0
    for off, name, args in decode(data):
        if name.endswith("End"):
            depth -= 1
        a = ", ".join(("[%s]" % " ".join("%.3g" % x for x in v)) if isinstance(v, list) and v and isinstance(v[0], float)
                      else repr(v) if not isinstance(v, float) else "%.4g" % v for v in args)
        print("%06x %s%s %s" % (off, "  " * max(depth, 0), name, a))
        if name.endswith("Begin"):
            depth += 1


if __name__ == "__main__":
    main()
