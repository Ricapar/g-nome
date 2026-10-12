"""Disassembler for G-Nome / 7th Level RT script bytecode (7L type-19 resources).

Reverse-engineered from RTLIB32.DLL:
  FUN_1001fdc6  runs one script resource: executes statements linearly; each handler
                returns the byte distance to the next statement (jumps are relative).
  FUN_1001f1f7  statement dispatcher: u16 opcode, mostly fixed-length records.
  FUN_10003330  expression VM: byte opcodes on a 32-bit integer stack, 0 terminates.
  FUN_10014e00  typed operand: (u32 value, u8 is_var). is_var=1 means "value is a variable id".

Variables: id < 0x13fe are globals (instance + 0x3e2f + id*4); id >= 0x13fe are frame
locals (frame - (id*4 - 0x4ff8)), shown here as L<id-0x13fe>.
Calls (expression op 0x0d): the callee id is on the stack below the args. id < 0xfa is an
RTLIB builtin (FUN_10003fad, a ~250-case switch); id >= 0xfa is a plugin native called
through ExternalCall (index id-0xfa into the import table, names in 7L key 11).
Expression op 0x0e calls another type-19 script (its resource id is popped).

usage: python -I tools/script7l.py <G-NOME.BIN> [resource-id ...]   (default: all)
       python -I tools/script7l.py <G-NOME.BIN> --check            (walk every script)
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import res7l  # noqa: E402

LOCAL_BASE = 0x13FE

# Fixed-size statements: opcode -> (length, mnemonic). Lengths are from FUN_1001f1f7.
FIXED = {
    0x02: (2, "nop2"), 0x04: (8, "s04"), 0x0B: (0x1A, "s0b"), 0x0D: (8, "s0d"),
    0x0E: (0x2E, "s0e"), 0x10: (0x26, "s10"), 0x11: (0x14, "s11"), 0x14: (8, "s14"),
    0x17: (0x20, "s17"), 0x1A: (0xC, "s1a"), 0xCA: (0xC, "sca"), 0x1B: (4, "s1b"),
    0x1C: (0xC, "s1c"), 0x1E: (0xC, "s1e"), 0x23: (6, "s23"), 0x2B: (0x12, "s2b"),
    0x2C: (0x16, "s2c"), 0x36: (0x14, "scene"), 0x39: (2, "quit"), 0x3A: (0x12, "setquitscene"),
    0x3C: (6, "s3c"), 0x3D: (6, "s3d"), 0x3E: (6, "trace"), 0x3F: (0x18, "s3f"),
    0x40: (0x28, "s40"), 0x42: (0x12, "s42"), 0x48: (0x32, "s48"), 0x4D: (0x10, "s4d"),
    0x53: (0x12, "gettime"), 0x59: (0x1A, "ifcall"), 0x5A: (0x12, "ifcmp"), 0x5C: (0xC, "s5c"),
    0x5E: (0x1C, "s5e"), 0x60: (0x10, "s60"), 0x61: (0xC, "s61"), 0x63: (0x14, "s63"),
    0x65: (0xC, "s65"), 0x6A: (0xC, "s6a"), 0x6B: (0x12, "s6b"), 0x6D: (8, "s6d"),
    0x71: (0xC, "s71"), 0x72: (6, "s72"), 0x74: (8, "s74"), 0x75: (8, "s75"), 0xDF: (8, "sdf"),
    0x78: (8, "s78"), 0x7A: (4, "mute"), 0x7C: (0x12, "s7c"), 0x8A: (8, "s8a"),
    0x8E: (4, "s8e"), 0x8F: (0x10, "s8f"), 0x91: (0x26, "s91"), 0x95: (0x12, "s95"),
    0x99: (0x10, "s99"), 0x9A: (0x1E, "s9a"), 0x9C: (0x10, "s9c"), 0xE4: (0x10, "se4"),
    0xA2: (2, "end"), 0xA3: (2, "sa3"), 0xA4: (0x1E, "sa4"), 0xA7: (0x1E, "sa7"),
    0xA9: (0x22, "sa9"), 0xB3: (0x12, "sb3"), 0xB4: (8, "sb4"), 0xB7: (0xC, "sb7"),
    0xB8: (0x12, "sb8"), 0xB9: (0xE, "sb9"), 0xC0: (0x32, "sc0"), 0xC2: (0x12, "sc2"),
    0xC3: (0xC, "sc3"), 0xC4: (0x12, "sc4"), 0xC6: (9, "sc6"), 0xD2: (4, "sd2"),
    0xD3: (8, "sd3"), 0xD4: (0xC, "sd4"), 0xD5: (0xE, "sd5"), 0xD6: (0xE, "sd6"),
    0xD9: (0x12, "sd9"), 0xDE: (0x12, "sde"), 0xE0: (0x2E, "se0"), 0xE1: (0xC, "se1"),
    0xE6: (0x12, "se6"),
}

# Expression VM (FUN_10003330): opcode -> (operand bytes, text)
EXPR = {
    0x01: (4, "push"), 0x02: (4, "load"), 0x03: (0, "index"), 0x04: (4, "addr"),
    0x05: (0, "deref"), 0x06: (0, "elem"), 0x08: (0, "assign"), 0x0D: (8, "call"),
    0x0E: (8, "callscript"), 0x0F: (0, "neg"), 0x10: (0, "not"), 0x11: (0, "bnot"),
    0x12: (0, "+"), 0x13: (0, "-"), 0x14: (0, "*"), 0x15: (0, "/"), 0x16: (0, "%"),
    0x17: (0, "=="), 0x18: (0, "<="), 0x19: (0, "<"), 0x1A: (0, ">="), 0x1B: (0, ">"),
    0x1C: (0, "!="), 0x1D: (0, "&&"), 0x1E: (0, "||"), 0x1F: (0, "&"), 0x20: (0, "|"),
    0x21: (0, "^"), 0x22: (0, "++x"), 0x23: (0, "x++"), 0x24: (0, "--x"), 0x25: (0, "x--"),
    0x26: (4, "jtrue"), 0x27: (4, "jfalse"), 0x28: (0, "dup*"), 0x29: (0, "<<"), 0x2A: (0, ">>"),
}

CMP = {0: "==", 1: "!=", 2: "<", 3: "<=", 4: ">", 5: ">="}  # FUN_10017f36 (to verify)

# RTLIB builtins (FUN_10003fad case = id). Named from each case's body; the ones scripts use
# are verified by hand, the rest come from the named API the case calls.
BUILTINS = {
    3: "abs", 11: "GetAngle", 12: "atoi", 18: "Collide", 24: "SpriteHitDetect",
    25: "Clone",            # ResCopyResource of a model/object/array/type-20 resource -> new id
    26: "Cosine", 30: "DebugPrintf",
    34: "Delete",           # ResDeleteResource of a cloned resource
    41: "Distance", 55: "StrCpy", 63: "SpriteGetBounds", 65: "StrLen",
    68: "ArrayHeader",      # (array, i) -> header word 10+i (dimension sizes)
    74: "SpriteGetNumCels", 77: "SpriteGetPosition", 78: "GetQuadrant",
    80: "SpriteGetScrollPos", 81: "SpriteGetInfo",
    82: "ArrayGet",         # (array, i0, i1, ...) on a type-11 array resource
    85: "PostAtom", 86: "GetUserName", 87: "AudioGetWaveSoundTime", 100: "ResGetType",
    106: "GetKeyState", 111: "WinExec", 117: "ResGetType2", 123: "AudioMute",
    137: "AudioPause", 139: "AudioPauseMidi", 140: "SpritePause",
    141: "PauseTimers", 152: "SpriteIsPicked", 153: "Random", 158: "ReflectAngle",
    165: "timeGetTime", 166: "SpriteScroll", 190: "SpriteSetScrollPos", 191: "SetScrollBox",
    193: "ArraySet",        # (array, i0, ..., value)
    200: "ScreenShake", 202: "Sine", 204: "SpriteGetExtraId", 205: "SpritePostMessage",
    206: "SpriteSendMessage", 207: "SpriteSetExtraId", 209: "SquareRoot", 213: "StrCmp",
    214: "StrCmpI", 215: "StrLen2", 216: "StrLen3", 221: "AudioMute2", 223: "ResGetType3",
    225: "SpriteIsVisible", 226: "SetFlag94dd", 231: "SpriteSetSync",
    232: "CacheVolume",     # copy a 7L volume to the hard disk
    235: "SetScreenRes", 237: "StrCat", 238: "StrCpy2", 239: "StrCpyN", 240: "MakeFullPath",
    242: "UncacheVolume", 243: "SetCursorPos", 248: "FileExistsOnCD",
}


def var(v):
    return "L%d" % (v - LOCAL_BASE) if v >= LOCAL_BASE else "G%d" % v


def operand(value, is_var):
    return var(value) if is_var else str(struct.unpack("<i", struct.pack("<I", value))[0])


def expr_len(code, p):
    """Byte length of the expression at p, including the 0 terminator."""
    q = p
    while True:
        op = code[q]
        if op == 0:
            return q + 1 - p
        if op not in EXPR and op not in (0x07, 0x09, 0x0A, 0x0B, 0x0C):
            raise ValueError("bad expr op 0x%x at 0x%x" % (op, q))
        q += 1 + EXPR.get(op, (0,))[0]


class Names:
    def __init__(self, d, keys):
        o, s = keys[11]
        self.natives = [n.decode() for n in re.findall(rb"[A-Za-z_][A-Za-z0-9_]+", d[o:o + s])]

    def callee(self, fid):
        if fid >= 0xFA:
            i = fid - 0xFA
            return self.natives[i] if i < len(self.natives) else "native_%d" % i
        return BUILTINS.get(fid, "builtin_%d" % fid)


def expr_text(code, p, names=None):
    """Decompile an expression into infix text (best effort) and return (text, length)."""
    st = []
    q = p
    while True:
        op = code[q]
        if op == 0:
            break
        n, name = EXPR.get(op, (0, "op%02x" % op))
        arg = struct.unpack_from("<I", code, q + 1)[0] if n == 4 else None
        q += 1 + n
        try:
            if op == 0x01:
                st.append(str(struct.unpack("<i", struct.pack("<I", arg))[0]))
            elif op == 0x02:
                st.append(var(arg))
            elif op == 0x04:
                st.append("&" + var(arg))
            elif op == 0x05:
                st.append("*(" + st.pop() + ")")
            elif op in (0x03, 0x06):
                i = st.pop(); a = st.pop()
                st.append("%s[%s]" % (a.lstrip("&") if op == 0x03 else a, i))
            elif op == 0x08:
                v = st.pop(); a = st.pop()
                st.append("%s = %s" % (a.lstrip("&"), v))
            elif op == 0x0D:
                nargs = struct.unpack_from("<I", code, q - 4)[0]
                args = [st.pop() for _ in range(nargs)][::-1]
                f = st.pop()
                fn = names.callee(int(f)) if names and f.lstrip("-").isdigit() else "call[%s]" % f
                st.append("%s(%s)" % (fn, ", ".join(args)))
            elif op == 0x0E:
                nl, nargs = struct.unpack_from("<II", code, q - 8)
                args = [st.pop() for _ in range(nargs)][::-1]
                f = st.pop()
                st.append("script_%s(%s)" % (f, ", ".join(args)))
            elif op in (0x0F, 0x10, 0x11):
                st.append({0x0F: "-", 0x10: "!", 0x11: "~"}[op] + "(" + st.pop() + ")")
            elif op in (0x22, 0x24):
                st.append(name[:2] + st.pop().lstrip("&"))
            elif op in (0x23, 0x25):
                st.append(st.pop().lstrip("&") + name[1:])
            elif op in (0x26, 0x27):
                st.append("<%s +%d>" % (name, arg))
            elif op == 0x28:
                st.append("*" + st[-1])
            elif 0x12 <= op <= 0x2A:
                b = st.pop(); a = st.pop()
                st.append("(%s %s %s)" % (a, name, b))
            else:
                st.append("?op%02x" % op)
        except IndexError:
            st.append("?underflow")
    return "; ".join(st), q + 1 - p


def disasm(code, names=None):
    """Yield (offset, text, length) for each statement of a type-19 script."""
    p = 0
    while p + 2 <= len(code):
        op = struct.unpack_from("<H", code, p)[0]
        if op == 0x01:
            ln = code[p + 9] * 4 + 10
            text = "s01 %s" % code[p + 2:p + ln].hex()
        elif op in (0xAF, 0xA1):
            # u32 total length, then an expression (0xa1 = return its value)
            ln = struct.unpack_from("<I", code, p + 2)[0]
            t, el = expr_text(code, p + 6, names)
            text = ("return %s" if op == 0xA1 else "%s") % t
            if 6 + el + (el & 1) != ln:
                text += "   ; len %d != %d" % (6 + el, ln)
        elif op in (0x5B, 0xE3):
            # rel target if false, rel target if true (= the next statement), expression
            f, tr = struct.unpack_from("<II", code, p + 2)
            t, el = expr_text(code, p + 10, names)
            text = "if !(%s) goto %04x" % (t, p + f)
            ln = tr  # 10 + expression, padded to an even length
        elif op == 0x68:
            rel = struct.unpack_from("<i", code, p + 2)[0]
            text, ln = "goto %04x" % (p + rel), 6
        elif op == 0x5A:
            rel, a, b = struct.unpack_from("<III", code, p + 2)
            c, fa, fb = code[p + 14], code[p + 15], code[p + 16]
            text = "if !(%s %s %s) goto %04x" % (operand(a, fa), CMP.get(c, "cmp%d" % c),
                                                 operand(b, fb), p + rel)
            ln = 0x12
        elif op == 0x59:
            rt, rf, hasf = struct.unpack_from("<IIB", code, p + 2)
            a, b = struct.unpack_from("<II", code, p + 14)
            c, fa, fb = code[p + 22], code[p + 23], code[p + 24]
            text = "if (%s %s %s) run script_%d else %s" % (
                operand(a, fa), CMP.get(c, "cmp%d" % c), operand(b, fb), rt,
                "script_%d" % rf if hasf else "-")
            ln = 0x1A
        elif op in (0xDA, 0xDB):
            v, toff, dflt = struct.unpack_from("<III", code, p + 2)
            cnt, fv = code[p + 14], code[p + 15]
            if op == 0xDA:
                subj, ln = operand(v, fv), 0x10
            else:
                subj, el = expr_text(code, p + 0x10, names)
                ln = v  # for 0xdb the first field is the statement length (padded)
            cases = []
            for k in range(cnt):
                cv, tgt, cf = struct.unpack_from("<IIB", code, p + toff + 2 + k * 12)
                cases.append("%s:%04x" % (operand(cv, cf), p + tgt))
            text = "switch %s { %s default:%04x }  (table @%04x)" % (
                subj, " ".join(cases), p + dflt, p + toff)
        elif op == 0xDC:
            # switch case-table entry (never executed): u32 value, u32 rel target, u8 is_var
            cv, tgt, cf = struct.unpack_from("<IIB", code, p + 2)
            text, ln = ".case %s" % operand(cv, cf), 12
        elif op in FIXED:
            ln, mn = FIXED[op]
            text = "%s %s" % (mn, code[p + 2:p + ln].hex())
        else:
            raise ValueError("unknown statement 0x%x at 0x%x" % (op, p))
        yield p, text, ln
        p += ln


def main():
    d, ents, keys = res7l.load(sys.argv[1])
    names = Names(d, keys)
    args = sys.argv[2:]
    scripts = [e for e in ents if e[1] == 19 and e[4] > 0]
    if args == ["--check"]:
        ok = bad = 0
        for e in scripts:
            code = res7l.read_internal(d, keys, e)
            try:
                end = 0
                for p, t, ln in disasm(code, names):
                    end = p + ln
                ok += end == len(code)
                bad += end != len(code)
            except Exception as ex:
                bad += 1
                if bad < 15:
                    print(e[0], ex)
        print("scripts ok", ok, "bad", bad)
        return
    want = {int(a, 0) for a in args}
    for e in scripts:
        if want and e[0] not in want:
            continue
        code = res7l.read_internal(d, keys, e)
        print("== script %d (%d bytes)" % (e[0], len(code)))
        try:
            for p, t, ln in disasm(code, names):
                print("  %04x  %s" % (p, t))
        except Exception as ex:
            print("  !! %s" % ex)


if __name__ == "__main__":
    main()
