"""G-Nome 8-bit bitmaps, palettes and a minimal PNG writer.

Bitmap record (sprites = 7L type 1, and the body of a texture block in type 2):
  u32 width, u32 height, u32 flags, i32 hotspot_x, i32 hotspot_y, u32 resource_id
  then u16 row_offsets[height] and the pixel data.
flags 0x80 = RLE (decoded by RTLIB FUN_100480d0); otherwise the data is in the chunked
LZW format of DecompressBitmapData (`decompress_chunks`; 72 of the 1240 sprites use it).
flags 0x40 = rows stored top-down; when clear, RENDER.R32 flips the rows (bottom-up).

RLE, per row, until a 0 byte:
  b < 0x80        run: next byte repeated b times
  b >= 0x80       literal: n = b ^ 0xff (if b == 0xff, n = next byte), then n bytes
A second 0 right after a row's terminator ends the image.

Texture block (type 2): u32 0x3d|0x3e, u32 block_len, u32 name_len, name[name_len],
then a bitmap record. Textures must be 128 pixels wide (RENDER.R32 checks this).

Palettes: 236 x {r, g, b, 0}. These are the non-system entries 10..245 of a 256-colour
Windows palette. Key resource 6 is the default palette, and 7L type 17 holds 14 palettes
(offsets relative to the key-5 script block).
"""
import struct
import zlib


def parse_record(data, off=0):
    w, h, flags, hx, hy, rid = struct.unpack_from("<IIIiiI", data, off)
    return {"w": w, "h": h, "flags": flags, "hx": hx, "hy": hy, "id": rid, "data_off": off + 0x18}


def _lzw_block(src, nbits, out, limit):
    """One LZW sub-block (RTLIB FUN_100356c0): fixed-width MSB-first codes, a fresh
    dictionary, literal codes 0..255, end code (1 << nbits) - 1, no clear code. Returns
    True if the end code was reached."""
    end = (1 << nbits) - 1
    prefix, suffix, first = {}, {}, {}
    acc = nacc = pos = 0

    def code():
        nonlocal acc, nacc, pos
        while nacc < nbits:
            acc = (acc << 8) | src[pos]; pos += 1; nacc += 8
        nacc -= nbits
        c = (acc >> nacc) & end
        acc &= (1 << nacc) - 1
        return c

    def string(c):
        s = bytearray()
        while c >= 256:
            s.append(suffix[c]); c = prefix[c]
        s.append(c)
        s.reverse()
        return s

    prev = code()
    out.append(prev)
    nxt = 256
    while len(out) < limit:
        c = code()
        if c == end:
            return True
        if c < nxt:
            s = string(c)
        else:  # KwKwK
            s = string(prev); s.append(s[0])
        out += s
        if nxt <= end - 1:
            prefix[nxt], suffix[nxt] = prev, s[0]
            nxt += 1
        prev = c
    return False


def decompress_chunks(data, p, size):
    """RTLIB DecompressBitmapData: u16 chunk headers. Top 3 bits: 0 = raw copy, 0x4000 /
    0x6000 / 0x8000 = LZW with 10 / 11 / 12-bit codes, 0xe000 = end. The low 13 bits are
    the payload length. An LZW payload is a series of [u16 len][LZW stream] sub-blocks."""
    out = bytearray()
    while True:
        hdr = struct.unpack_from("<H", data, p)[0]; p += 2
        kind, ln = hdr & 0xe000, hdr & 0x1fff
        if kind == 0xe000:
            break
        if kind == 0:
            out += data[p:p + ln]
        else:
            nbits = {0x4000: 10, 0x6000: 11, 0x8000: 12}[kind]
            q, stop = p, p + ln
            while q < stop and len(out) < size:
                sl = struct.unpack_from("<H", data, q)[0]
                _lzw_block(data[q + 2:q + 2 + sl], nbits, out, size)
                q += 2 + sl
        p += ln
        if len(out) >= size:
            break
    return out[:size], p


def decode_record(data, off=0):
    """Return (header dict, bytearray of w*h palette indices, top-down)."""
    r = parse_record(data, off)
    w, h = r["w"], r["h"]
    if not r["flags"] & 0x80:
        stride = (w + 3) & ~3
        px, _ = decompress_chunks(data, r["data_off"], stride * h)
        if len(px) != stride * h:
            raise ValueError("LZW bitmap short: %d of %d" % (len(px), stride * h))
        if stride != w:
            px = bytearray(b"".join(px[y * stride:y * stride + w] for y in range(h)))
        if not r["flags"] & 0x40:
            px = bytearray(b"".join(bytes(px[(h - 1 - y) * w:(h - y) * w]) for y in range(h)))
        return r, px
    out = bytearray(w * h)
    p = r["data_off"] + h * 2
    row = 0
    while row < h:
        x = 0
        base = row * w
        while True:
            b = data[p]; p += 1
            if b == 0:
                break
            if b < 0x80:
                v = data[p]; p += 1
                out[base + x:base + x + b] = bytes([v]) * b
                x += b
            else:
                n = b ^ 0xff
                if b == 0xff:
                    n = data[p]; p += 1
                out[base + x:base + x + n] = data[p:p + n]
                p += n
                x += n
        row += 1
        if p >= len(data) or data[p] == 0:
            break
    if not r["flags"] & 0x40:
        out = bytearray(b"".join(bytes(out[(h - 1 - y) * w:(h - y) * w]) for y in range(h)))
    return r, out


def parse_texture_block(data, off=0):
    """Return (name, header, pixels) for the texture block at off."""
    tag, blen, nlen = struct.unpack_from("<III", data, off)
    if tag not in (0x3d, 0x3e):
        raise ValueError("not a texture block")
    name = data[off + 12:off + 12 + nlen].split(b"\0", 1)[0].decode("latin-1")
    r, px = decode_record(data, off + 12 + nlen)
    return name, r, px


def texture_blocks(data):
    """Yield (offset, tag) for each texture block in a 7L type-2 entry. An entry holds one or
    more blocks back to back; block_len counts the bytes after the tag word."""
    p = 0
    while p + 12 <= len(data):
        tag, blen = struct.unpack_from("<II", data, p)
        if tag not in (0x3d, 0x3e):
            return
        yield p, tag
        p += 4 + blen


def palette_from_entries(raw, first=10):
    """236 x RGBx -> 256 x (r, g, b). System colours are filled with the standard VGA ones."""
    pal = [(0, 0, 0)] * 256
    sysc = [(0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0), (0, 0, 128), (128, 0, 128),
            (0, 128, 128), (192, 192, 192), (192, 220, 192), (166, 202, 240)]
    sysh = [(255, 251, 240), (160, 160, 164), (128, 128, 128), (255, 0, 0), (0, 255, 0),
            (255, 255, 0), (0, 0, 255), (255, 0, 255), (0, 255, 255), (255, 255, 255)]
    pal[0:10] = sysc
    pal[246:256] = sysh
    for i in range(len(raw) // 4):
        r, g, b, _ = raw[i * 4:i * 4 + 4]
        pal[first + i] = (r, g, b)
    return pal


def write_png(path, w, h, pixels, pal=None, transparent=None):
    """Write 8-bit indexed (pal given) or raw RGB/RGBA rows. pixels = bytes of w*h indices."""
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    raw = b"".join(b"\0" + bytes(pixels[y * w:(y + 1) * w]) for y in range(h))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 3, 0, 0, 0))
    png += chunk(b"PLTE", b"".join(bytes(c) for c in pal))
    if transparent is not None:
        png += chunk(b"tRNS", b"\xff" * transparent + b"\0")
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
