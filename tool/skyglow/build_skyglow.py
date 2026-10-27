"""Build assets/sky/skyglow.bin.gz: an estimate of how bright the night sky
is everywhere on land, for "Darker skies nearby".

Inputs (both public domain, see README.md here):
  - NASA Earth Observatory Black Marble 2016, grayscale 3 km GeoTIFF
    (BlackMarble_2016_3km_gray_geo.tif)
  - Natural Earth 1:50m land and lakes (ne_50m_land.geojson, ne_50m_lakes.geojson)

Usage: python3 build_skyglow.py <blackmarble.tif> <ne_50m_land.geojson> <ne_50m_lakes.geojson> <out.bin.gz> [--check]

Model: each lit pixel's light (linearised from the tone-mapped image) spreads
into the sky around it with Walker's law, brightness ~ distance^-2.5, out to
250 km. The summed glow becomes a zenith sky brightness in mag/arcsec^2 (the
number a Sky Quality Meter reads): 22.0 for a natural sky, ~18 under a city.

Output format (little-endian):
  'LUSG' u8 version=1, 3 pad bytes, f32 north, f32 west, f32 step (degrees),
  u32 rows, u32 cols, then rows*cols bytes, row-major from the north-west.
  0 = water; otherwise mag/arcsec^2 = 16 + (b - 1) * 0.025.
"""
import gzip
import json
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None

NORTH, SOUTH, STEP = 75.0, -60.0, 0.1
NATURAL = 22.0
GAMMA = 2.2   # the image is tone-mapped for display; undo a display gamma
B0 = 0.0      # set by calibrate(); glow that brightens the sky by ~0.75 mag
RADIUS_KM = 250.0
NEAR_KM = 3.0

# Zenith brightness (mag/arcsec^2) at well-known places, from published
# Sky Quality Meter readings and Bortle classes. Used only to fit B0.
REFERENCE = [
    ('Downtown Nashville', 36.16, -86.78, 18.2),
    ('Times Square', 40.758, -73.985, 17.0),
    ('Brentwood, TN suburbs', 36.03, -86.78, 19.3),
    ('Cherry Springs, PA', 41.663, -77.823, 21.7),
    ('Pickett CCC State Park, TN', 36.55, -84.80, 21.6),
    ('Cades Cove, Smokies', 35.60, -83.80, 21.3),
    ('Big Bend, TX', 29.25, -103.25, 21.9),
    ('Rural western Kansas', 38.5, -100.5, 21.6),
    ('Central London', 51.51, -0.13, 17.6),
    ('Death Valley', 36.46, -116.87, 21.8),
]


def load_lights(path):
    a = np.asarray(Image.open(path))
    a = a[:, :, 0] if a.ndim == 3 else a
    h, w = a.shape
    # 3x3 block average: 0.08 degree working grid.
    a = a.reshape(h // 3, 3, w // 3, 3).astype(np.float32).mean(axis=(1, 3))
    lin = (np.clip(a - 2, 0, None) / 253.0) ** GAMMA
    rows = a.shape[0]
    lat = 90 - (np.arange(rows) + 0.5) * 180.0 / rows
    return lin * np.cos(np.radians(lat))[:, None], 180.0 / rows


def glow(lights, step):
    """Walker's-law sum of every pixel's light within RADIUS_KM, per pixel."""
    rows, cols = lights.shape
    out = np.zeros_like(lights)
    dy_km = step * 110.57
    pad = int(np.ceil(RADIUS_KM / dy_km))
    band = 32
    for r0 in range(0, rows, band):
        r1 = min(rows, r0 + band)
        latc = 90 - ((r0 + r1) / 2) * step
        if latc > NORTH + 5 or latc < SOUTH - 5:
            continue
        dx_km = max(step * 111.32 * np.cos(np.radians(latc)), 0.5)
        lo, hi = r0 - pad, r1 + pad
        idx = np.clip(np.arange(lo, hi), 0, rows - 1)
        src = lights[idx]
        n = src.shape[0]
        dy = (np.arange(n) - 0)[:, None]
        dy = np.where(dy <= n // 2, dy, dy - n) * dy_km
        dx = np.arange(cols)[None, :]
        dx = np.where(dx <= cols // 2, dx, dx - cols) * dx_km
        d = np.maximum(np.hypot(dy, dx), NEAR_KM)
        k = np.where(d <= RADIUS_KM, d ** -2.5, 0.0)
        res = np.fft.irfft2(np.fft.rfft2(src) * np.fft.rfft2(k), s=src.shape)
        out[r0:r1] = res[r0 - lo:r1 - lo]
    return out


def sample(field, step, lat, lon):
    rows, cols = field.shape
    r = np.clip(((90 - lat) / step - 0.5).astype(int), 0, rows - 1)
    c = np.clip(((lon + 180) / step - 0.5).astype(int), 0, cols - 1)
    return field[r, c]


def sqm(b):
    return NATURAL - 2.5 * np.log10(1 + b / B0)


def calibrate(field, step):
    """Pick B0 so the references fit best (least squares in magnitudes)."""
    global B0
    lat = np.array([r[1] for r in REFERENCE])
    lon = np.array([r[2] for r in REFERENCE])
    want = np.array([r[3] for r in REFERENCE])
    b = sample(field, step, lat, lon)
    best = None
    for b0 in np.logspace(-6, 2, 800):
        err = np.mean((NATURAL - 2.5 * np.log10(1 + b / b0) - want) ** 2)
        if best is None or err < best[0]:
            best = (err, b0)
    B0 = best[1]
    return np.sqrt(best[0])


def land_mask(land, lakes, rows, cols):
    img = Image.new('L', (cols, rows), 0)
    draw = ImageDraw.Draw(img)

    def rings(geom):
        polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]
        for poly in polys:
            yield poly[0], poly[1:]

    def px(ring):
        return [((x + 180) / STEP, (NORTH - y) / STEP) for x, y in ring]

    for path, fill in ((land, 255), (lakes, 0)):
        for f in json.load(open(path))['features']:
            for outer, holes in rings(f['geometry']):
                draw.polygon(px(outer), fill=fill)
                for h in holes:
                    draw.polygon(px(h), fill=255 - fill)
    return np.asarray(img) > 0


def main():
    tif, land, lakes, out = sys.argv[1:5]
    lights, step = load_lights(tif)
    field = glow(lights, step)
    rms = calibrate(field, step)
    print(f'B0 {B0:.3g}, fit rms {rms:.2f} mag')
    for name, la, lo, want in REFERENCE:
        got = sqm(sample(field, step, np.array([la]), np.array([lo])))[0]
        print(f'  {name:30s} want {want:5.2f}  got {got:5.2f}')
    rows = int(round((NORTH - SOUTH) / STEP))
    cols = int(round(360 / STEP))
    lat = NORTH - (np.arange(rows) + 0.5) * STEP
    lon = -180 + (np.arange(cols) + 0.5) * STEP
    LAT, LON = np.meshgrid(lat, lon, indexing='ij')
    m = sqm(sample(field, step, LAT, LON))
    q = np.clip(np.round((m - 16) / 0.025) + 1, 1, 255).astype(np.uint8)
    q[~land_mask(land, lakes, rows, cols)] = 0
    header = b'LUSG' + struct.pack('<B3xfffII', 1, NORTH, -180.0, STEP, rows, cols)
    with gzip.open(out, 'wb', compresslevel=9) as f:
        f.write(header + q.tobytes())
    print(f'wrote {out}: {rows}x{cols}, land {np.mean(q > 0):.1%}')


if __name__ == '__main__':
    main()
