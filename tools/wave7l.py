"""Decoder for 7th Level "7L" type-12 wave resources (G-Nome sounds and voices).

Reverse-engineered from RTLIB32.DLL (see docs/analysis.md, "Waves"):
  ResCreateWaveEvent @ 0x10047451 reads the 32-byte header and hands it to AudioCreateWave
  @ 0x1002f033 -> FUN_1002f168, which copies the header flags into the wave object.
  ima2pcm @ 0x100342f0 (export #315) is the decoder; the in-memory path FUN_1002fba8 and the
  streaming path FUN_100327d0 both call it.

Resource layout (32-byte header, then data):
  0x00 u32 data_len            bytes after the header
  0x04 u8  f0                  1 = load whole wave into memory (wave obj +0x86); 0 = may stream
  0x05 u8  f1                  copied to wave obj +0x89 (meaning not confirmed)
  0x06 u8  f2                  1 = IMA ADPCM compressed (wave obj +0x8d); 0 = raw PCM
  0x07 u8  f3                  always 0
  0x08 u32 0                   copied to wave obj +0x80 (u16)
  0x0c u32 resource_id         == index id
  0x10 PCMWAVEFORMAT           {u16 tag=1, u16 channels, u32 rate, u32 bytes/s, u16 align,
                                u16 bits}: the format of the *decoded* audio
The codec is plain IMA/DVI ADPCM without block headers: one continuous stream, predictor
and step index both start at 0, low nibble first. Mono: each byte gives two samples.
Stereo: each byte gives one frame, low nibble = left, high nibble = right (each channel
has its own predictor/index). Output is always 16-bit, so a compressed wave decodes to
data_len * 4 bytes.

usage: python -I tools/wave7l.py <G-NOME.BIN> <id> <out.wav>
"""
import os
import struct
import sys
import wave
from array import array

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import res7l  # noqa: E402

HEADER_SIZE = 32

# Standard IMA ADPCM tables. RTLIB stores them premultiplied: a 89x8 table of differences
# (DAT_100529e0, diff[step][code & 7]) and the index adjust table times 8 (DAT_10052f70).
STEPS = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55,
    60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411,
    1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
    5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500,
    20350, 22385, 24623, 27086, 29794, 32767,
]
INDEX_ADJ = [-1, -1, -1, -1, 2, 4, 6, 8]


def diff_table():
    """The 89x8 difference table exactly as RTLIB's DAT_100529e0 (integer IMA)."""
    out = []
    for s in STEPS:
        for c in range(8):
            d = s >> 3
            if c & 4:
                d += s
            if c & 2:
                d += s >> 1
            if c & 1:
                d += s >> 2
            out.append(d)
    return out


_DIFF = diff_table()
# Per (step index, nibble): signed delta and next step index.
_DELTA = [[0] * 16 for _ in STEPS]
_NEXT = [[0] * 16 for _ in STEPS]
for _i in range(len(STEPS)):
    for _n in range(16):
        _d = _DIFF[_i * 8 + (_n & 7)]
        _DELTA[_i][_n] = -_d if _n & 8 else _d
        _NEXT[_i][_n] = min(max(_i + INDEX_ADJ[_n & 7], 0), len(STEPS) - 1)


def parse_header(raw):
    """Return a dict with the header fields of a type-12 resource."""
    data_len, f0, f1, f2, f3, zero, rid = struct.unpack_from("<IBBBBII", raw, 0)
    tag, ch, rate, bps, align, bits = struct.unpack_from("<HHIIHH", raw, 16)
    return {
        "id": rid, "data_len": data_len, "flags": [f0, f1, f2, f3], "reserved": zero,
        "compressed": bool(f2), "format_tag": tag, "channels": ch, "rate": rate,
        "bytes_per_sec": bps, "block_align": align, "bits": bits,
    }


def decode_ima(data, channels):
    """Decode RTLIB's headerless IMA ADPCM stream to a list-like array of int16 samples
    (interleaved for stereo)."""
    out = array("h", bytes(len(data) * 4))
    delta, nxt = _DELTA, _NEXT
    p0 = p1 = 0
    i0 = i1 = 0
    o = 0
    if channels == 2:
        for b in data:
            n = b & 15
            p0 += delta[i0][n]
            p0 = 32767 if p0 > 32767 else (-32768 if p0 < -32768 else p0)
            i0 = nxt[i0][n]
            n = b >> 4
            p1 += delta[i1][n]
            p1 = 32767 if p1 > 32767 else (-32768 if p1 < -32768 else p1)
            i1 = nxt[i1][n]
            out[o] = p0
            out[o + 1] = p1
            o += 2
    else:
        for b in data:
            n = b & 15
            p0 += delta[i0][n]
            p0 = 32767 if p0 > 32767 else (-32768 if p0 < -32768 else p0)
            i0 = nxt[i0][n]
            out[o] = p0
            n = b >> 4
            p0 += delta[i0][n]
            p0 = 32767 if p0 > 32767 else (-32768 if p0 < -32768 else p0)
            i0 = nxt[i0][n]
            out[o + 1] = p0
            o += 2
    return out


def decode(raw):
    """Decode a type-12 resource. Returns (header dict, pcm bytes, sample width in bytes)."""
    h = parse_header(raw)
    data = raw[HEADER_SIZE:HEADER_SIZE + h["data_len"]]
    if len(data) != h["data_len"]:
        raise ValueError("wave %d: truncated (%d of %d bytes)" % (h["id"], len(data), h["data_len"]))
    if h["format_tag"] != 1:
        raise ValueError("wave %d: format tag %d" % (h["id"], h["format_tag"]))
    if h["compressed"]:
        if h["bits"] != 16 or h["channels"] not in (1, 2):
            raise ValueError("wave %d: compressed %d-bit %d ch not supported"
                             % (h["id"], h["bits"], h["channels"]))
        pcm = decode_ima(data, h["channels"])
        if sys.byteorder != "little":
            pcm.byteswap()
        return h, pcm.tobytes(), 2
    return h, bytes(data), h["bits"] // 8


def write_wav(path, h, pcm, width):
    with wave.open(path, "wb") as w:
        w.setnchannels(h["channels"])
        w.setsampwidth(width)
        w.setframerate(h["rate"])
        w.writeframes(pcm)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    bin_path, rid, out = sys.argv[1], int(sys.argv[2], 0), sys.argv[3]
    _, ents, _ = res7l.load(bin_path)
    e = ents[rid]
    if e[1] != 12 or e[4] == 0:
        sys.exit("resource %d is not a wave" % rid)
    h, pcm, width = decode(res7l.read_entry(bin_path, e))
    write_wav(out, h, pcm, width)
    frames = len(pcm) // (width * h["channels"])
    print("wave %d: %d Hz %d ch, %.3f s -> %s" % (rid, h["rate"], h["channels"],
                                                  frames / h["rate"], out))


if __name__ == "__main__":
    main()
