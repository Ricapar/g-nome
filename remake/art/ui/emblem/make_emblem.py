"""Generate the winged insignia used as a decal on the menu frame (our own design, inspired by
the emblem in remake/art/ui/reference/target_briefing.png).

    python -I remake/art/ui/emblem/make_emblem.py remake/game/ui/frame/emblem.svg

A shield with a chevron in the middle, five swept feathers per wing, and a small banner below.
White on transparent; the decal tints and weathers it in Godot.
"""
import sys

W, H = 512, 320
CX = W / 2


def poly(pts):
    return "M" + " L".join("%.1f %.1f" % p for p in pts) + " Z"


def mirror(pts):
    return [(2 * CX - x, y) for x, y in pts]


def main(out):
    paths = []
    # shield with a notch at the top and a point at the bottom
    shield = [(CX - 46, 70), (CX - 14, 70), (CX, 84), (CX + 14, 70), (CX + 46, 70), (CX + 40, 160), (CX, 214),
              (CX - 40, 160)]
    paths.append(poly(shield))
    # chevron cut-out drawn in the background colour via even-odd fill
    chev = [(CX - 28, 110), (CX, 132), (CX + 28, 110), (CX + 28, 128), (CX, 152), (CX - 28, 128)]
    # feathers: swept quads, longest at the top
    for k in range(5):
        y0 = 78 + k * 21
        root_in, root_out = (CX - 54, y0), (CX - 54, y0 + 15)
        tip = 228 - k * 34
        tip_y = 40 + k * 32
        f = [root_in, (CX - tip + 26, tip_y - 6), (CX - tip, tip_y + 4), root_out]
        paths.append(poly(f))
        paths.append(poly(mirror(f)))
    # banner
    banner = [(CX - 70, 226), (CX + 70, 226), (CX + 58, 242), (CX + 70, 258), (CX - 70, 258), (CX - 58, 242)]
    paths.append(poly(banner))
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (W, H, W, H),
           '<path fill="#ffffff" fill-rule="evenodd" d="%s"/>' % " ".join(paths[:1] + [poly(chev)]),
           '<path fill="#ffffff" d="%s"/>' % " ".join(paths[1:]),
           "</svg>"]
    with open(out, "w") as f:
        f.write("\n".join(svg) + "\n")
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "emblem.svg")
