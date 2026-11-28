"""Builds assets/sky/towns.json.gz: the towns place search looks through,
on the phone (domain/places/town_search.dart), so no search ever leaves it.

Source: GeoNames (CC BY 4.0, https://www.geonames.org/), from
https://download.geonames.org/export/dump/:
cities5000.zip (every place of 5,000+ people), admin1CodesASCII.txt (state or
region names) and countryInfo.txt (country names). Keep
assets/sky/SOURCES-towns.txt.

Each row: [name, ascii name or "" when the same, lat, lon (2 places: about
a kilometre, the most a forecast or the sky needs), population, region,
country].

    python3 -I tool/places/build.py path/to/geonames-dir
"""
import gzip
import json
import os
import sys


def table(path, key_col, val_col):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            c = line.rstrip("\n").split("\t")
            out[c[key_col]] = c[val_col]
    return out


def main(src, out):
    regions = table(os.path.join(src, "admin1CodesASCII.txt"), 0, 1)
    countries = table(os.path.join(src, "countryInfo.txt"), 0, 4)
    rows = []
    with open(os.path.join(src, "cities5000.txt"), encoding="utf-8") as f:
        for line in f:
            c = line.rstrip("\n").split("\t")
            name, ascii_, lat, lon, cc, a1, pop = c[1], c[2], float(c[4]), float(c[5]), c[8], c[10], int(c[14] or 0)
            if not name:
                continue
            rows.append([
                name,
                "" if ascii_ == name else ascii_,
                round(lat, 2),
                round(lon, 2),
                pop,
                regions.get(f"{cc}.{a1}", ""),
                countries.get(cc, cc),
            ])
    rows.sort(key=lambda r: -r[4])
    data = json.dumps(rows, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with gzip.GzipFile(out, "wb", compresslevel=9, mtime=0) as g:
        g.write(data)
    print(f"{len(rows)} towns, {os.path.getsize(out) / 1e6:.2f} MB -> {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "assets/sky/towns.json.gz")
