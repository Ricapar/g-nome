"""Apply G-Nome modern-Windows binary fixes to an installed copy of the game.

Usage: patch_gnome.py <install dir containing SMACKW32.DLL>

Each patch is (file offset, original bytes, replacement bytes); originals are
verified before writing so the script refuses to touch unknown builds, and is
idempotent (already-patched sites are skipped).

SMACKW32.DLL (RAD Smacker, 1996; sha256 a838b34f...abeae)
  SmackBufferBlit computes destination x/y as 16-bit words and pushes them
  zero-extended. Win9x GDI truncated coordinates to 16 bits, so e.g. 0xFEC0
  acted as -320 (G-Nome's window DC has its viewport origin at 320,240).
  NT-family GDI uses 32-bit coordinates, so the frame lands at x=65216 —
  off-screen — and every FMV plays invisibly (black screen + audio).
  Fix: load those coordinates sign-extended (cwde / movsx).
"""
import hashlib
import os
import sys

PATCHES = {
    "SMACKW32.DLL": {
        "sha256": "a838b34f6e4a97f043bad25a26aee017197bbf82382ede6c9ed9d0f3f10abeae",
        "sites": [
            # StretchDIBits path (0x401e6x): y then x are `and eax,0xffff` -> cwde
            (0x129B, "25ffff0000", "9890909090", "StretchDIBits dest y"),
            (0x12B6, "25ffff0000", "9890909090", "StretchDIBits dest x"),
            # BitBlt (DIBSection/WinG) path: `xor ebx,ebx; mov bx,[esp+N]` -> movsx ebx,word [esp+N]
            (0x12F9, "31db668b5c2440", "0fbf5c24409090", "BitBlt dest y"),
            (0x1304, "31db668b5c2444", "0fbf5c24449090", "BitBlt dest x"),
            # StretchBlt path: y = `xor eax,eax; mov ax,[esp+4c]` -> movsx eax,word [esp+4c]
            (0x13C1, "31c0668b44244c", "0fbf44244c9090", "StretchBlt dest y"),
            # x = `xor ebx,ebx; and eax,0xffff; mov bx,[esp+4c]` -> movsx ebx,[esp+4c]; and eax,0xffff; nop nop
            (0x13DC, "31db25ffff0000668b5c244c", "0fbf5c244c25ffff00009090", "StretchBlt dest x"),
        ],
    },
}


def patch_file(path, spec):
    data = bytearray(open(path, "rb").read())
    if hashlib.sha256(data).hexdigest() != spec["sha256"]:
        # Accept a file that is exactly our patched output; reject anything else.
        for off, old, new, _ in spec["sites"]:
            if data[off:off + len(bytes.fromhex(new))] != bytes.fromhex(new):
                sys.exit(f"{path}: unknown build (sha256 mismatch), not patching")
        print(f"{os.path.basename(path)}: already patched")
        return
    for off, old, new, what in spec["sites"]:
        old, new = bytes.fromhex(old), bytes.fromhex(new)
        assert len(old) == len(new), what
        if data[off:off + len(old)] != old:
            sys.exit(f"{path}: unexpected bytes at {off:#x} ({what})")
        data[off:off + len(old)] = new
        print(f"{os.path.basename(path)}: {off:#07x} {what}")
    if not os.path.exists(path + ".orig"):
        os.replace(path, path + ".orig")
    open(path, "wb").write(data)


def main():
    d = sys.argv[1]
    for name, spec in PATCHES.items():
        patch_file(os.path.join(d, name), spec)


if __name__ == "__main__":
    main()
