"""Register a plate to the sky and cut out one figure, without hand work.

Finds the plate's engraved stars, matches them to the real sky with a
RANSAC search over similarity transforms (either handedness), then masks
the figure as the shaded ink that lies nearer this constellation's stick
figure than any other's. Writes a clean.py config entry and the mask.

    python -I auto.py ID FILE plate.jpg stars6.json constellations.json work_dir cfg.json
"""
import json
import math
import os
import sys
from itertools import combinations

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # -I drops it
from clean import candidates, gnom

# The app's Argo Navis is filed under Carina; Ophiuchus holds the serpent.
EXTRA = {'Car': ['Pup', 'Vel'], 'Oph': ['Ser']}


def unit_mean(ra, dec):
    r, d = np.radians(ra), np.radians(dec)
    v = np.stack([np.cos(d) * np.cos(r), np.cos(d) * np.sin(r), np.sin(d)], 1).mean(0)
    return math.degrees(math.atan2(v[1], v[0])) % 360, math.degrees(math.asin(v[2] / np.linalg.norm(v)))


def tri(p):
    u, v = p[1] - p[0], p[2] - p[0]
    return abs(u[0] * v[1] - u[1] * v[0]) / 2


def main(cid, file, plate, stars6, consts, work, cfg_path):
    img = Image.open(plate).convert('L')
    if img.width < 900:  # small scans: work at the pilot's scale
        k = 990 / img.width
        img = img.resize((990, round(img.height * k)), Image.LANCZOS)
    a = np.asarray(img).astype(float)
    h, w = a.shape
    scale = w / 990
    img.save(f'{work}/{cid}.plate.png')

    feats = json.load(open(stars6))['features']
    hip = np.array([int(f['id']) for f in feats])
    ra = np.array([f['geometry']['coordinates'][0] % 360 for f in feats])
    dec = np.array([f['geometry']['coordinates'][1] for f in feats])
    mag = np.array([f['properties']['mag'] for f in feats])
    tree_sky = cKDTree(np.stack([ra * np.cos(np.radians(dec)), dec], 1))

    cons = {c['id']: c for c in json.load(open(consts))['constellations']}
    ids = [cid] + EXTRA.get(cid, [])
    lines = [ln for i in ids for ln in cons[i]['l']]
    pts = np.array([p for ln in lines for p in ln])
    ra0, dec0 = unit_mean(pts[:, 0] % 360, pts[:, 1])
    # Line vertices -> catalogue stars.
    # Brightest star within 0.3 deg of each vertex (nearest can be a faint companion).
    near = tree_sky.query_ball_point(np.stack([(pts[:, 0] % 360) * np.cos(np.radians(pts[:, 1])), pts[:, 1]], 1), 0.3)
    own = sorted({min(n, key=lambda i: mag[i]) for n in near if n}, key=lambda i: mag[i])

    xi, eta = gnom(ra, dec, ra0, dec0)
    cosc = np.sin(np.radians(dec0)) * np.sin(np.radians(dec)) + np.cos(np.radians(dec0)) * np.cos(np.radians(dec)) * np.cos(np.radians(ra - ra0))
    front = cosc > math.cos(math.radians(70))
    W = xi + 1j * eta

    d = 255 - a
    cand, cs, cr, _ = candidates(d, scale)
    # Drop the border's degree ticks: find the frame line on each side.
    def edge(prof, n):
        k = int(0.2 * n)
        return int(np.argmax(prof[:k])), n - k + int(np.argmax(prof[n - k:]))
    x0, x1 = edge(d.mean(0), w)
    y0, y1 = edge(d.mean(1), h)
    mg = 30 * scale
    inside = (cand[:, 0] > x0 + mg) & (cand[:, 0] < x1 - mg) & (cand[:, 1] > y0 + mg) & (cand[:, 1] < y1 - mg)
    cand, cs, cr = cand[inside], cs[inside], cr[inside]
    order = np.argsort(-cs)
    allc = cand[order[:600]]
    tree = cKDTree(allc)
    strong = cand[np.argsort(-cs * cr)[:60]]  # big glyphs = bright stars

    # The figure fills much of its plate: bound the scale by its extent,
    # and only score stars on or near it (else tiny scales win).
    ext = np.abs(W[own][:, None] - W[own][None, :]).max()
    rad = np.abs(W[own] - W[own].mean()).max() * 1.3
    test = np.nonzero(front & (mag <= 5.0) & (np.abs(W - W[own].mean()) < rad))[0]
    wt = 6.0 - mag[test]
    best = (0, None)
    bright = own[:7]
    tol = 7 * scale
    sc = strong[:, 0] + 1j * strong[:, 1]
    K, L = np.meshgrid(np.arange(len(sc)), np.arange(len(sc)))
    m_ = K != L
    zk, zl = sc[K[m_]], sc[L[m_]]
    # Hevelius drew the globe from outside; Bode from inside.
    for mirror in ((False,) if os.environ.get('BODE') else (True,)):
        Wm = np.conj(W) if mirror else W
        for i, j in combinations(bright, 2):
            dw = Wm[j] - Wm[i]
            if abs(dw) < 1.5:
                continue
            A = (zl - zk) / dw
            ok = (np.abs(A) * ext > 0.35 * w) & (np.abs(A) * ext < 1.3 * w)
            if not ok.any():
                continue
            A_, B_ = A[ok], zk[ok] - A[ok] * Wm[i]
            P = A_[:, None] * Wm[test][None, :] + B_[:, None]
            inb = (P.real > 0) & (P.real < w) & (P.imag > 0) & (P.imag < h)
            q, _ = tree.query(np.stack([P.real.ravel(), P.imag.ravel()], 1), distance_upper_bound=tol)
            hit = (q.reshape(P.shape) < tol) & inb
            score = (hit * wt).sum(1) - 0.5 * ((~hit & inb) * (wt > 2.5) * wt).sum(1)
            k = int(np.argmax(score))
            if score[k] > best[0]:
                best = (float(score[k]), (mirror, A_[k], B_[k]))
    if os.environ.get('HINT'):  # two hand-placed stars: hip,x,y,hip,x,y
        h1, x1, y1, h2, x2, y2 = map(float, os.environ['HINT'].split(','))
        i1, i2 = int(np.nonzero(hip == h1)[0][0]), int(np.nonzero(hip == h2)[0][0])
        mirror = not os.environ.get('BODE')
        Wm = np.conj(W) if mirror else W
        A_ = ((x2 + 1j * y2) - (x1 + 1j * y1)) / (Wm[i2] - Wm[i1])
        best = (-1, (mirror, A_, x1 + 1j * y1 - A_ * Wm[i1]))
    if best[1] is None:
        raise SystemExit(f'{cid}: no registration')
    mirror, A, B = best[1]
    Wm = np.conj(W) if mirror else W

    # Refine to an affine on all matches, then pick anchors.
    sel = np.nonzero(front & (mag <= 5.5))[0]
    P = A * Wm[sel] + B
    for it, tl in enumerate((3 * tol, 2 * tol, 1.5 * tol, tol, tol)):
        q, qi = tree.query(np.stack([P.real, P.imag], 1), distance_upper_bound=tl)
        m = q < tl
        X = np.stack([np.ones(m.sum()), xi[sel][m], eta[sel][m]], 1)
        coef, *_ = np.linalg.lstsq(X, allc[qi[m]], rcond=None)
        Pp = np.stack([np.ones(len(sel)), xi[sel], eta[sel]], 1) @ coef
        P = Pp[:, 0] + 1j * Pp[:, 1]
    res = np.hypot(*(np.stack([P.real, P.imag], 1)[m] - allc[qi[m]]).T)
    nmatch = int(m.sum())
    print(f'{cid}: score {best[0]:.0f} mirror={mirror} matched {nmatch} rms {np.sqrt((res**2).mean()):.1f}px scale {abs(A):.1f}px/deg')

    def proj(r_, d_):
        x_, e_ = gnom(np.asarray(r_), np.asarray(d_), ra0, dec0)
        v = np.stack([np.ones_like(x_), x_, e_], -1) @ coef
        return v

    matched = {int(sel[t]): allc[qi[t]] for t in np.nonzero(m)[0]}
    own_in = [i for i in own if i in matched and mag[i] <= 4.8]
    if len(own_in) < 3:
        own_in = [i for i in sel[m] if mag[i] <= 4.5][:12]
    best_t, area = None, 0
    for t in combinations(own_in[:12], 3):
        p = np.array([matched[i] for i in t])
        ar = tri(p)
        if ar > area:
            best_t, area = t, ar
    anchors = [[int(hip[i]), round(float(matched[i][0]), 1), round(float(matched[i][1]), 1)] for i in best_t]
    fig_t, area = None, 0
    figc = [i for i in own if front[i] and mag[i] <= 5.0][:14]
    if len(figc) < 3:  # e.g. CVn has two line stars: borrow bright stars nearby
        near = np.argsort(np.abs(W - W[figc].mean()) + 10 * (mag > 4.5))
        figc += [int(i) for i in near if front[i] and int(i) not in figc][:3 - len(figc) + 2]
    for t in combinations(figc, 3):
        p = proj(ra[list(t)], dec[list(t)])
        ar = tri(p)
        if ar > area:
            fig_t, area = t, ar

    # Territory: nearest stick figure, all constellations on the plate.
    lab = Image.new('I', (w, h), 0)
    dr = ImageDraw.Draw(lab)
    names = list(cons)
    group = {n: (cid if n in ids else n) for n in names}
    labels = {n: k + 1 for k, n in enumerate(names)}
    big = 4 * max(w, h)
    for n in names:
        for ln in cons[n]['l']:
            ln = np.array(ln)
            c_ = np.sin(np.radians(dec0)) * np.sin(np.radians(ln[:, 1])) + np.cos(np.radians(dec0)) * np.cos(np.radians(ln[:, 1])) * np.cos(np.radians(ln[:, 0] - ra0))
            p = proj(ln[:, 0], ln[:, 1])
            for s in range(len(ln) - 1):
                if c_[s] < 0.35 or c_[s + 1] < 0.35:
                    continue
                if np.abs(p[s:s + 2]).max() > big:
                    continue
                dr.line([tuple(p[s]), tuple(p[s + 1])], fill=labels[group[n]], width=3)
    lab = np.asarray(lab)
    dist, (iy, ix) = ndi.distance_transform_edt(lab == 0, return_indices=True)
    nearest = lab[iy, ix]
    mine = nearest == labels[cid]
    xp = os.path.join(work, 'extra.json')  # hand-drawn 'keep' polygons widen the territory
    kept = np.zeros((h, w), bool)
    if os.path.exists(xp) and json.load(open(xp)).get('keep'):
        km = Image.new('L', (w, h), 0)
        for poly in json.load(open(xp))['keep']:
            ImageDraw.Draw(km).polygon([tuple(q) for q in poly], fill=255)
        kept = np.asarray(km) > 0
        mine = mine | kept
    ownline = (lab == labels[cid])
    dmine = ndi.distance_transform_edt(~ownline)

    # Shaded ink, closed into solid shapes.
    # Hatched shading is dense; lettering, lines and outlines are not.
    paper = np.percentile(d, 40)
    dens = ndi.gaussian_filter(np.clip(d - paper, 0, None), 5 * scale)
    ink = dens > float(os.environ.get('INK', 45))
    def disk(r):
        r = max(1, int(r))
        return np.hypot(*np.mgrid[-r:r + 1, -r:r + 1]) <= r
    solid = ndi.binary_fill_holes(ndi.binary_closing(ink, disk(10 * scale)))
    core = solid
    solid = ndi.binary_dilation(solid, disk(5 * scale))
    pxdeg = abs(A)
    keep = solid & ((mine & (dmine < 14 * pxdeg)) | kept)
    labs, n = ndi.label(keep)
    if n:
        near_line = dmine < 1.5 * pxdeg
        good = np.zeros(n + 1, bool)
        sizes = ndi.sum(np.ones_like(labs), labs, np.arange(n + 1))
        touch = ndi.sum(near_line, labs, np.arange(n + 1))
        good = (touch > 0) & (sizes > (30 * scale) ** 2)
        good[0] = False
        keep = good[labs]
    # Lettering and stray glyphs in the margin: small strokes off the core.
    strokes, ns = ndi.label((d - paper > 60) & keep & ~core)
    if ns:
        sl = ndi.find_objects(strokes)
        small = np.array([0] + [max(s_[0].stop - s_[0].start, s_[1].stop - s_[1].start) < 30 * scale for s_ in sl])
        keep = keep & ~ndi.binary_dilation(small[strokes].astype(bool), disk(2 * scale))
    mask = Image.fromarray((keep * 255).astype('uint8'))
    chk = img.convert('RGB')
    chk.paste((255, 60, 60), mask=mask.point(lambda v: v // 4))
    dc = ImageDraw.Draw(chk)
    for ln in lines:
        p = proj(np.array(ln)[:, 0], np.array(ln)[:, 1])
        dc.line([tuple(q) for q in p], fill=(0, 120, 255), width=2)
    chk.save(f'{work}/{cid}.check.png')
    mask.save(f'{work}/{cid}.mask.png')
    cover = keep.sum() / max(1, (dmine < 1.5 * pxdeg).sum())

    cfg = json.load(open(cfg_path)) if os.path.exists(cfg_path) else {}
    entry = cfg.get(cid, {})
    entry.update({'file': file, 'anchors': anchors, 'figure_anchors': [int(hip[i]) for i in fig_t],
                  'mask': f'{work}/{cid}.mask.png', 'auto': {'score': round(best[0]), 'matched': nmatch,
                  'rms': round(float(np.sqrt((res ** 2).mean())), 1), 'mirror': bool(mirror), 'mask_px': int(keep.sum())}})
    cfg[cid] = entry
    json.dump(cfg, open(cfg_path, 'w'), indent=1)


if __name__ == '__main__':
    main(*sys.argv[1:])
