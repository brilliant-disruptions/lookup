"""Clean a Hevelius plate into app-ready linework: light ink on black, no
grid/rules, no engraved stars, no lettering or neighbouring figures,
mirrored to the sky as seen from inside, with three anchor stars.

    python -I clean.py config.json NAME plate.jpg stars6.json out_dir
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as ndi
from scipy.signal import fftconvolve


def gnom(ra, dec, ra0, dec0):
    ra, dec, ra0, dec0 = map(np.radians, (ra, dec, ra0, dec0))
    c = np.sin(dec0) * np.sin(dec) + np.cos(dec0) * np.cos(dec) * np.cos(ra - ra0)
    xi = np.cos(dec) * np.sin(ra - ra0) / c
    eta = (np.cos(dec0) * np.sin(dec) - np.sin(dec0) * np.cos(dec) * np.cos(ra - ra0)) / c
    return np.degrees(xi), np.degrees(eta)


def design(xi, eta, quad):
    cols = [np.ones_like(xi), xi, eta] + ([xi * xi, xi * eta, eta * eta] if quad else [])
    return np.stack(cols, axis=-1)


def fit(xi, eta, px, quad):
    coef, *_ = np.linalg.lstsq(design(xi, eta, quad), px, rcond=None)
    return coef, quad


def apply(model, xi, eta):
    coef, quad = model
    return design(np.asarray(xi, float), np.asarray(eta, float), quad) @ coef


def candidates(d, scale=1.0):
    """Star glyphs: ink inside a disc with the engraver's cleared halo
    around it. Hatching has no halo, so it scores low. Returns positions,
    scores and glyph radii."""
    best = np.full(d.shape, -1e9)
    rad = np.zeros(d.shape)
    halo_at = np.zeros(d.shape)
    for r in np.array([3.5, 5, 6.5, 8.5]) * scale:
        n = int(r + 6)
        yy, xx = np.mgrid[-n:n + 1, -n:n + 1]
        dist = np.hypot(xx, yy)
        disc = (dist <= r).astype(float)
        ring = ((dist > r + 1) & (dist <= r + 4)).astype(float)
        halo = fftconvolve(d, ring / ring.sum(), mode='same')
        sc = fftconvolve(d, disc / disc.sum(), mode='same') - halo
        better = sc > best
        best[better] = sc[better]
        rad[better] = r
        halo_at[better] = halo[better]
    peaks = (best == ndi.maximum_filter(best, int(7 * scale))) & (best > 20)
    ys, xs = np.nonzero(peaks)
    return np.stack([xs, ys], 1).astype(float), best[ys, xs], rad[ys, xs], halo_at[ys, xs]


def hough_lines(d, mask_far, min_cover):
    """Long straight 1-3 px rules: the plate grid, joins, ecliptic, tropics."""
    h, w = d.shape
    r = np.clip(d - ndi.uniform_filter(d, 9), 0, None)
    r[mask_far] = 0  # don't let the frame drive peaks
    ys, xs = np.nonzero(r > 20)
    wts = r[ys, xs]
    diag = int(math.hypot(w, h)) + 2
    found = []
    for t in np.arange(0, 180, 0.2):
        th = math.radians(t)
        rho = np.round(xs * math.cos(th) + ys * math.sin(th)).astype(int) + diag
        acc = np.bincount(rho, weights=wts, minlength=2 * diag)
        acc = ndi.uniform_filter1d(acc, 3) * 3  # allow 1px wobble
        pk = np.nonzero((acc == ndi.maximum_filter1d(acc, 9)) & (acc > 2500))[0]
        found += [(acc[rr], t, rr - diag) for rr in pk]
    found.sort(reverse=True)
    found = found[:400]
    r = ndi.maximum_filter(r, 3)
    lines = []
    for score, t, rho in found:
        if any(abs(t - t2) < 1.2 and abs(rho - r2) < 8 for _, t2, r2, _ in lines):
            continue
        cov = coverage(r, t, rho)
        if cov >= min_cover:
            lines.append((score, t, rho, cov))
    return lines


def line_pixels(shape, t, rho):
    h, w = shape
    th = math.radians(t)
    c, s = math.cos(th), math.sin(th)
    n = int(math.hypot(w, h))
    u = np.arange(-n, n)
    x = rho * c - u * s
    y = rho * s + u * c
    ok = (x >= 0) & (x < w - 1) & (y >= 0) & (y < h - 1)
    return x[ok], y[ok]


def coverage(r, t, rho):
    x, y = line_pixels(r.shape, t, rho)
    if len(x) < 150:
        return 0
    v = r[np.round(y).astype(int), np.round(x).astype(int)]
    return float((v > 15).mean())


def erase_line(a, t, rho, half):
    """Replace pixels within `half` of the line by the hatching just beyond
    it, mirrored in and cross-faded, so strokes run on where the rule was."""
    h, w = a.shape
    th = math.radians(t)
    c, s = math.cos(th), math.sin(th)
    yy, xx = np.mgrid[0:h, 0:w]
    dist = xx * c + yy * s - rho
    band = np.abs(dist) <= half
    by, bx = np.nonzero(band)
    dd = dist[by, bx]
    def sample(k):
        sx = np.clip(bx + (k - dd) * c, 0, w - 1)
        sy = np.clip(by + (k - dd) * s, 0, h - 1)
        return ndi.map_coordinates(a, [sy, sx], order=1)
    wt = (dd + half) / (2 * half)
    out = a.copy()
    out[by, bx] = wt * sample(2 * half + 1.5 - dd) + (1 - wt) * sample(-2 * half - 1.5 - dd)
    return out


def erase_disc(a, x, y, r):
    h, w = a.shape
    x0, x1 = int(max(0, x - r - 6)), int(min(w, x + r + 7))
    y0, y1 = int(max(0, y - r - 6)), int(min(h, y + r + 7))
    yy, xx = np.mgrid[y0:y1, x0:x1]
    dist = np.hypot(xx - x, yy - y)
    ring = (dist > r + 1.5) & (dist <= r + 5)
    if not ring.any():
        return
    fill = 0.35 * np.percentile(a[y0:y1, x0:x1][ring], 5)  # a dark pocket where the app's star sits
    wgt = np.clip((r + 1.5 - dist) / 2.0, 0, 1)
    a[y0:y1, x0:x1] = a[y0:y1, x0:x1] * (1 - wgt) + fill * wgt


def polygon_mask(size, cfg):
    if 'mask' in cfg:  # made by auto.py
        m = Image.open(cfg['mask']).convert('L')
        if cfg.get('cut'):
            dr = ImageDraw.Draw(m)
            for poly in cfg['cut']:
                dr.polygon([tuple(p) for p in poly], fill=0)
        return m
    m = Image.new('L', size, 0)
    dr = ImageDraw.Draw(m)
    for poly in cfg.get('outline', []):
        dr.polygon([tuple(p) for p in poly], fill=255)
    for cx, cy, rx, ry, ang in cfg.get('ellipses', []):
        a = math.radians(ang)
        pts = [(cx + rx * math.cos(u) * math.cos(a) - ry * math.sin(u) * math.sin(a),
                cy + rx * math.cos(u) * math.sin(a) + ry * math.sin(u) * math.cos(a))
               for u in np.linspace(0, 2 * math.pi, 72)]
        dr.polygon(pts, fill=255)
    for poly in cfg.get('cut', []):
        dr.polygon([tuple(p) for p in poly], fill=0)
    return m


def main(cfg_path, name, plate, stars6, out_dir):
    cfg = json.load(open(cfg_path))[name]
    if 'mask' in cfg:  # stored relative to the config file
        cfg['mask'] = os.path.join(os.path.dirname(os.path.abspath(cfg_path)), cfg['mask'])
    img = Image.open(plate).convert('L')
    a = np.asarray(img).astype(float)
    h, w = a.shape
    scale = w / 990

    # Catalogue, registered from the three hand-placed anchors.
    feats = json.load(open(stars6))['features']
    hip = np.array([int(f['id']) for f in feats])
    ra = np.array([f['geometry']['coordinates'][0] % 360 for f in feats])
    dec = np.array([f['geometry']['coordinates'][1] for f in feats])
    mag = np.array([f['properties']['mag'] for f in feats])
    idx = {hh: i for i, hh in enumerate(hip)}
    anc = cfg['anchors']  # [[hip, x, y], ...]
    ai = [idx[h_] for h_, _, _ in anc]
    ra0, dec0 = float(np.mean(ra[ai])), float(np.mean(dec[ai]))
    xi, eta = gnom(ra, dec, ra0, dec0)
    near = (np.abs(xi) < 60) & (np.abs(eta) < 60)
    model = fit(xi[ai], eta[ai], np.array([[x, y] for _, x, y in anc], float), False)

    d = 255 - a
    cand, cs, _, _ = candidates(d, scale)
    print('  glyph score percentiles 50/90/99:', np.percentile(cs, [50, 90, 99]).round(1), len(cs))
    sel = near & (mag <= 6.0)
    for rad, quad in ((16 * scale, False), (10 * scale, False), (7 * scale, True), (5 * scale, True)):
        p = apply(model, xi[sel], eta[sel])
        inside = (p[:, 0] > 5) & (p[:, 0] < w - 5) & (p[:, 1] > 5) & (p[:, 1] < h - 5)
        src, dst = [], []
        for i in np.nonzero(inside)[0]:
            dd = np.hypot(*(cand - p[i]).T)
            j = int(np.argmin(dd))
            if dd[j] < rad:
                src.append(i)
                dst.append(cand[j])
        src = np.array(src)
        dst = np.array(dst)
        if len(src) < (12 if quad else 4):
            quad = False
        model = fit(xi[sel][src], eta[sel][src], dst, quad)
        res = np.hypot(*(apply(model, xi[sel][src], eta[sel][src]) - dst).T)
        print(f'  r={rad:.0f} matched {len(src)} rms {np.sqrt((res ** 2).mean()):.2f}px quad={quad}')
    matched = {int(hip[sel][i]): tuple(dst[k]) for k, i in enumerate(src)}

    # Rules, then the plate's join(s), on the plate's own tone.
    frame = np.zeros_like(a, bool)
    m_ = int(28 * scale)
    frame[:m_] = frame[-m_:] = True
    frame[:, :m_] = frame[:, -m_:] = True
    lines = hough_lines(d, frame, cfg.get("min_cover", 0.85))
    print(f'  {len(lines)} rules:', [(round(t, 1), int(rho), round(c, 2)) for _, t, rho, c in lines])
    for _, t, rho, _ in lines:
        a = erase_line(a, t, rho, 1.8 * scale)
    for t, rho, half in cfg.get('joins', []):
        a = erase_line(a, t, rho, half)

    # Engraved stars. Hevelius' positions are off by up to ~10 arcmin, so
    # the catalogue only lowers the bar: a distinct glyph (dark disc in a
    # cleared halo) goes anywhere in the figure; a weaker one goes if a real
    # star is near; the brightest stars go even if the detector missed them.
    d = 255 - a
    mask = polygon_mask(img.size, cfg)
    inside = np.asarray(mask).astype(float) / 255
    cand, cs, cr, ch = candidates(d, scale)
    # The halo must be cleared all the way round: a figure's outline has
    # paper on one side only, and that is not a star.
    ang = np.linspace(0, 2 * np.pi, 24, endpoint=False)
    rx = cand[:, :1] + (cr[:, None] + 3 * scale) * np.cos(ang)
    ry = cand[:, 1:] + (cr[:, None] + 3 * scale) * np.sin(ang)
    ringv = ndi.map_coordinates(d, [np.clip(ry, 0, h - 1), np.clip(rx, 0, w - 1)], order=1)
    ok = (ch < cfg.get('halo', 95)) & (np.percentile(ringv, 80, axis=1) < cfg.get('halo_hi', 90))
    p_all = apply(model, xi[near & (mag <= 6.3)], eta[near & (mag <= 6.3)])
    mags = mag[near & (mag <= 6.3)]
    nearest = np.full(len(cand), np.inf)
    for (x, y) in p_all:
        nearest = np.minimum(nearest, np.hypot(*(cand - (x, y)).T))
    ci = np.clip(cand.astype(int), 0, [w - 1, h - 1])
    free = ok & (cs > cfg.get('glyph_free', 85)) & (inside[ci[:, 1], ci[:, 0]] > 0.2)
    helped = ok & (cs > cfg.get('glyph', 35)) & (nearest <= 14 * scale)
    erased = []
    for q in np.nonzero(free | helped)[0]:
        x, y = cand[q]
        r = cr[q] + 2.0 * scale  # the rays reach past the ring
        erase_disc(d, x, y, r)
        erased.append((x, y, r))
    # Glyphs engraved over hatching have no halo; there a compact dark blob
    # (difference of Gaussians) beside a real star gives them away.
    g = ndi.gaussian_filter(d, 2.5 * scale) - ndi.gaussian_filter(d, 6.25 * scale)
    pk = (g == ndi.maximum_filter(g, int(7 * scale) | 1)) & (g > cfg.get('blob', 32))
    for y, x in zip(*np.nonzero(pk)):
        if inside[y, x] < 0.2 or not len(p_all):
            continue
        if np.hypot(*(p_all - (x, y)).T).min() > 9 * scale:
            continue
        if erased and min(np.hypot(ex - x, ey - y) for ex, ey, _ in erased) < 6 * scale:
            continue
        erase_disc(d, x, y, 6.5 * scale)
        erased.append((x, y, 6.5 * scale))
    for (x, y), mm in zip(p_all, mags):
        if mm > cfg.get('always_mag', 3.5) or not (0 <= x < w and 0 <= y < h):
            continue
        if erased and min(np.hypot(ex - x, ey - y) for ex, ey, _ in erased) < 8 * scale:
            continue
        r = (max(3.0, 8.5 - 1.4 * mm) + 2.5) * scale
        erase_disc(d, x, y, r)
        erased.append((x, y, r))
    for x, y, r in cfg.get('extra_stars', []):
        erase_disc(d, x, y, r * scale)
        erased.append((x, y, r * scale))

    mf = np.asarray(mask.filter(ImageFilter.GaussianBlur(7 * scale))).astype(float) / 255
    ink = np.clip((d - cfg.get('floor', 25)) * cfg.get('gain', 1.25), 0, 255) * mf

    bbox = mask.getbbox()
    pad = int(10 * scale)
    box = (max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(w, bbox[2] + pad), min(h, bbox[3] + pad))
    out = Image.fromarray(ink.astype('uint8')).crop(box).transpose(Image.FLIP_LEFT_RIGHT)
    k = min(1.0, 640 / out.width)
    if k < 1:
        out = out.resize((round(out.width * k), round(out.height * k)), Image.LANCZOS)
    out.convert('RGB').save(f'{out_dir}/{cfg["file"]}')

    # Anchors in the output image (model positions are sub-pixel).
    W = box[2] - box[0]
    entry_anchors = []
    for h_ in cfg['figure_anchors']:
        x, y = apply(model, [xi[idx[h_]]], [eta[idx[h_]]])[0]
        entry_anchors.append([round((W - 1 - (x - box[0])) * k, 1), round((y - box[1]) * k, 1),
                              round(float(ra[idx[h_]]), 4), round(float(dec[idx[h_]]), 4)])
    entry = {'id': name, 'file': cfg['file'], 'size': [out.width, out.height], 'anchors': entry_anchors}
    print(json.dumps(entry))
    json.dump(entry, open(f'{out_dir}/{name}.entry.json', 'w'))

    # Debug overlay on the plate: what was found and removed.
    dbg = Image.open(plate).convert('RGB')
    dr = ImageDraw.Draw(dbg)
    for _, t, rho, _ in lines:
        x, y = line_pixels(a.shape, t, rho)
        dr.line([(x[0], y[0]), (x[-1], y[-1])], fill=(255, 0, 0), width=1)
    for x, y, r in erased:
        dr.ellipse([x - r, y - r, x + r, y + r], outline=(0, 90, 255))
    for h_, ax, ay in anc:
        dr.rectangle([ax - 3, ay - 3, ax + 3, ay + 3], outline=(255, 0, 255))
    edge = np.asarray(mask.filter(ImageFilter.FIND_EDGES)) > 0
    dbg_a = np.asarray(dbg).copy()
    dbg_a[edge] = (0, 200, 0)
    Image.fromarray(dbg_a).save(f'{out_dir}/{name}.debug.png')


if __name__ == '__main__':
    main(*sys.argv[1:])
