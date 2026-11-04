"""Builds assets/sky/figures.json and assets/sky/figures/*.png: the artwork
of each constellation for the Sky tab's panorama, pinned to three stars.

Sources (see assets/sky/SOURCES-figures.txt):
- Stellarium's "modern" sky culture, skycultures/modern/index.json and
  illustrations/ (https://github.com/Stellarium/stellarium). Each image names
  three anchor stars by Hipparcos number and their pixel positions.
- Anchor positions from d3-celestial's data/stars.6.json (BSD-3, the same
  source as stars.json); the three fainter than magnitude 6 are from the HYG
  database v4.0 (CC BY-SA 4.0), below.

    python3 -I tool/figures/build.py path/to/index.json path/to/illustrations path/to/stars.6.json
"""
import json
import os
import shutil
import sys

# Fainter than d3-celestial's magnitude-6 cut. HYG v4.0 (Hipparcos), J2000.
FAINT = {
    17999: (57.71844, 23.96147),  # Taurus
    91589: (280.182855, -47.027246),  # Telescopium
    102805: (312.40737, 12.545128),  # Delphinus
}


def main(index, illustrations, stars6, out_dir):
    cons = json.load(open(index, encoding="utf-8"))["constellations"]
    pos = {int(f["id"]): tuple(f["geometry"]["coordinates"]) for f in json.load(open(stars6))["features"]}
    pos.update(FAINT)
    figures = []
    os.makedirs(os.path.join(out_dir, "figures"), exist_ok=True)
    for c in cons:
        img = c.get("image")
        if not img:
            continue  # Serpens has none; Puppis and Vela share Carina's Argo Navis
        name = os.path.basename(img["file"])
        anchors = []
        for a in img["anchors"]:
            ra, dec = pos[a["hip"]]
            anchors.append([a["pos"][0], a["pos"][1], round(ra % 360, 5), round(dec, 5)])
        figures.append({"id": c["id"].split()[-1], "file": name, "size": img["size"], "anchors": anchors})
        shutil.copy(os.path.join(illustrations, name), os.path.join(out_dir, "figures", name))
    with open(os.path.join(out_dir, "figures.json"), "w", encoding="utf-8") as f:
        json.dump(
            {"source": "Stellarium modern sky culture: illustrations Free Art License, data CC BY-SA 4.0", "figures": figures},
            f,
            separators=(",", ":"),
        )
    print(len(figures), "figures")


if __name__ == "__main__":
    main(*sys.argv[1:4], out_dir=os.path.join(os.path.dirname(__file__), "..", "..", "assets", "sky"))
