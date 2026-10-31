"""Builds assets/sky/places.json: towns and cities of 50,000+ people for
"who else was under the pass" (domain/satellites/under_the_pass.dart).

Source: Natural Earth 1:10m populated places (public domain),
https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_10m_populated_places_simple.geojson

pop_max is a metro population, so a place within 25 km of a bigger one is
dropped (Yokohama inside Tokyo's count) to avoid counting people twice.

    python3 -I tool/population/build.py path/to/ne_10m_populated_places_simple.geojson
"""
import json
import math
import sys

MIN_POP = 50_000
MERGE_KM = 25


def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))


def main(src, out):
    feats = json.load(open(src, encoding="utf-8"))["features"]
    places = sorted(
        (
            (p["pop_max"], p["nameascii"] or p["name"], p["latitude"], p["longitude"])
            for p in (f["properties"] for f in feats)
            if (p.get("pop_max") or 0) >= MIN_POP
        ),
        reverse=True,
    )
    kept = []
    for pop, name, lat, lon in places:
        if any(abs(lat - k[2]) < 0.5 and km((lat, lon), (k[2], k[3])) < MERGE_KM for k in kept):
            continue
        kept.append((pop, name, lat, lon))
    rows = [[name, round(lat, 2), round(lon, 2), round(pop / 1000)] for pop, name, lat, lon in kept]
    with open(out, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(rows)} places, {sum(r[3] for r in rows) / 1e6:.2f} billion people -> {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "assets/sky/places.json")
