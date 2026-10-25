const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/** Geohash of a point; precision 4 ≈ 39 × 20 km cells (enough for aurora). */
export function geohash(lat: number, lon: number, precision = 4): string {
  const latR: [number, number] = [-90, 90], lonR: [number, number] = [-180, 180];
  let hash = "", bit = 0, ch = 0, even = true;
  while (hash.length < precision) {
    const r = even ? lonR : latR;
    const v = even ? lon : lat;
    const mid = (r[0] + r[1]) / 2;
    if (v >= mid) {
      ch |= 1 << (4 - bit);
      r[0] = mid;
    } else {
      r[1] = mid;
    }
    even = !even;
    if (++bit === 5) {
      hash += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }
  return hash;
}
