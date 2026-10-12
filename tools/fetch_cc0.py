"""Download the CC0 PBR texture sets the remake UI frame uses (ambientCG, public domain).

Usage: python -I tools/fetch_cc0.py [outdir]   (default: remake/game/art_cc0, gitignored)

Only the maps Godot needs are kept: Color, NormalGL, Roughness, Metalness, AmbientOcclusion.
Each set lands in <outdir>/<Asset>/<Asset>_2K-JPG_<Map>.jpg. Already-present sets are skipped.
Licence: ambientCG assets are CC0 1.0 (https://docs.ambientcg.com/license/).
"""
import io
import os
import sys
import urllib.request
import zipfile

ASSETS = {
    # asset id: role in the UI frame (see remake/UI-DESIGN.md, "Target look")
    "PaintedMetal004": "red armour plates (chipped red paint)",
    "Metal038": "dark scratched steel: collars, frames, bezel",
    "Metal009": "brushed steel: keys, bezel lip",
    "Metal027": "black powder coat: recesses, housings",
    "PaintedMetal016": "worn hazard stripes",
    "Rubber004": "cables and hoses",
}
MAPS = ("Color", "NormalGL", "Roughness", "Metalness", "AmbientOcclusion")
RES = "2K-JPG"


def fetch(asset, outdir):
    dest = os.path.join(outdir, asset)
    if os.path.isdir(dest) and any(f.endswith("_Color.jpg") for f in os.listdir(dest)):
        print("have", asset)
        return
    url = "https://ambientcg.com/get?file=%s_%s.zip" % (asset, RES)
    print("get ", url)
    req = urllib.request.Request(url, headers={"User-Agent": "g-nome-remake-fetch/1.0"})
    data = urllib.request.urlopen(req, timeout=300).read()
    os.makedirs(dest, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            base = os.path.basename(name)
            if base.endswith(".jpg") and any(base.endswith("_%s.jpg" % m) for m in MAPS):
                with open(os.path.join(dest, base), "wb") as f:
                    f.write(z.read(name))


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "remake", "game", "art_cc0")
    os.makedirs(outdir, exist_ok=True)
    for a in ASSETS:
        fetch(a, outdir)
    with open(os.path.join(outdir, "LICENSE.txt"), "w") as f:
        f.write("Texture sets from ambientCG (https://ambientcg.com), licensed CC0 1.0 Universal.\n")
        for a, role in ASSETS.items():
            f.write("%s: %s\n" % (a, role))


if __name__ == "__main__":
    main()
