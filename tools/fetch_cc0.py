"""Download the CC0 assets the remake UI frame uses: PBR texture sets (ambientCG) and HDRIs for
reflections (Poly Haven). All are public domain (CC0 1.0).

Usage: python -I tools/fetch_cc0.py [outdir]   (default: remake/game/art_cc0, gitignored)

Only the maps Godot needs are kept: Color, NormalGL, Roughness, Metalness, AmbientOcclusion.
Each set lands in <outdir>/<Asset>/<Asset>_2K-JPG_<Map>.jpg; HDRIs in <outdir>/hdri/<name>_1k.hdr.
Files already present are skipped.
Licences: https://docs.ambientcg.com/license/ and https://polyhaven.com/license (both CC0).
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
    "Metal009": "brushed steel: keys, bezel lip, worn edges",
    "Metal027": "black powder coat: recesses, housings",
    "PaintedMetal016": "worn hazard stripes",
    "Rubber004": "cables and hoses",
}
HDRIS = {
    "studio_small_09": "studio reflections for the menu frame",
    "industrial_workshop_foundry": "warm industrial reflections (alternative)",
}
MAPS = ("Color", "NormalGL", "Roughness", "Metalness", "AmbientOcclusion")
RES = "2K-JPG"
AGENT = {"User-Agent": "g-nome-remake-fetch/1.0"}


def download(url):
    print("get ", url)
    return urllib.request.urlopen(urllib.request.Request(url, headers=AGENT), timeout=300).read()


def fetch(asset, outdir):
    dest = os.path.join(outdir, asset)
    if os.path.isdir(dest) and any(f.endswith("_Color.jpg") for f in os.listdir(dest)):
        print("have", asset)
        return
    data = download("https://ambientcg.com/get?file=%s_%s.zip" % (asset, RES))
    os.makedirs(dest, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for name in z.namelist():
            base = os.path.basename(name)
            if base.endswith(".jpg") and any(base.endswith("_%s.jpg" % m) for m in MAPS):
                with open(os.path.join(dest, base), "wb") as f:
                    f.write(z.read(name))


def fetch_hdri(name, outdir):
    dest = os.path.join(outdir, "hdri", "%s_1k.hdr" % name)
    if os.path.exists(dest):
        print("have", name)
        return
    data = download("https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/%s_1k.hdr" % name)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(data)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "remake", "game", "art_cc0")
    os.makedirs(outdir, exist_ok=True)
    for a in ASSETS:
        fetch(a, outdir)
    for h in HDRIS:
        fetch_hdri(h, outdir)
    with open(os.path.join(outdir, "LICENSE.txt"), "w") as f:
        f.write("Texture sets from ambientCG (https://ambientcg.com) and HDRIs from Poly Haven\n")
        f.write("(https://polyhaven.com), licensed CC0 1.0 Universal.\n")
        for a, role in list(ASSETS.items()) + list(HDRIS.items()):
            f.write("%s: %s\n" % (a, role))


if __name__ == "__main__":
    main()
