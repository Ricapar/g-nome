"""Synthesize the menu's UI sounds (our own, placeholders until R8 exports the originals).

    python -I remake/art/ui/sounds/make_sounds.py remake/game/ui/sounds

Writes 16-bit mono 44.1 kHz WAVs:
  hover.wav  - a soft high tick when focus or the mouse moves onto a control
  slot.wav   - a two-tone electronic blip for the glass slot buttons
  key.wav    - a mechanical clunk with a metal ring for the bottom keys
  back.wav   - a falling blip for cancel / back
Deterministic (fixed random seed), standard library only.
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 44100


def render(dur, fn):
    return [fn(i / RATE) for i in range(int(dur * RATE))]


def env(t, attack, decay):
    return min(t / attack, 1.0) * math.exp(-t / decay) if attack > 0 else math.exp(-t / decay)


def lowpass(x, cutoff):
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    y, out = 0.0, []
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out


def write(path, x, gain=0.8):
    peak = max(abs(v) for v in x) or 1.0
    # short fade out so nothing clicks at the end
    n = len(x)
    fade = int(0.004 * RATE)
    data = b"".join(struct.pack("<h", int(32767 * gain * v / peak * min(1.0, (n - i) / fade)))
                    for i, v in enumerate(x))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print("wrote", path)


def hover():
    return render(0.035, lambda t: math.sin(2 * math.pi * 3200 * t) * env(t, 0.0008, 0.006))


def slot():
    def f(t):
        hz = 990 if t < 0.045 else 1480
        tone = math.sin(2 * math.pi * hz * t) + 0.25 * math.sin(2 * math.pi * hz * 3 * t)
        return tone * env(t, 0.002, 0.06)
    return lowpass(render(0.16, f), 6000)


def key():
    rnd = random.Random(7)
    noise = lowpass([rnd.uniform(-1, 1) for _ in range(int(0.3 * RATE))], 2500)

    def f(t):
        i = int(t * RATE)
        thump = math.sin(2 * math.pi * (95 - 40 * t) * t) * env(t, 0.002, 0.05)
        click = noise[i] * env(t, 0.0005, 0.012) * 1.6
        ring = sum(a * math.sin(2 * math.pi * hz * t) for hz, a in ((1870, 0.3), (2950, 0.2), (4410, 0.1)))
        return thump + click + ring * env(t, 0.001, 0.07) * 0.5
    return render(0.3, f)


def back():
    def f(t):
        hz = 1320 * (1.0 - 0.45 * min(t / 0.12, 1.0))
        return math.sin(2 * math.pi * hz * t) * env(t, 0.002, 0.07)
    return lowpass(render(0.18, f), 5000)


def main(out):
    os.makedirs(out, exist_ok=True)
    write(os.path.join(out, "hover.wav"), hover(), 0.35)
    write(os.path.join(out, "slot.wav"), slot(), 0.6)
    write(os.path.join(out, "key.wav"), key(), 0.85)
    write(os.path.join(out, "back.wav"), back(), 0.55)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "sounds")
