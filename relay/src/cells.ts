// Half-degree cells, as the app files reports under them
// (lib/domain/aurora/seen_nearby.dart: reportCell, cellsNear). Keep in step.

export const CELL_DEG = 0.5;
const EARTH_KM = 6371;

export type Cell = { la: number; lo: number };

const rad = (d: number) => (d * Math.PI) / 180;

export function distanceKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_KM * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** The centre of the cell containing a point. */
export function cellOf(lat: number, lon: number): Cell {
  const snap = (v: number) => (Math.floor(v / CELL_DEG) + 0.5) * CELL_DEG;
  const wrapped = ((((lon + 180) % 360) + 360) % 360) - 180;
  return { la: snap(Math.min(89.99, Math.max(-89.99, lat))), lo: snap(wrapped) };
}

/** A cell centre exactly as the app sends it, and nothing finer. */
export function isCell(c: unknown): c is Cell {
  if (typeof c !== 'object' || c === null) return false;
  const { la, lo } = c as Record<string, unknown>;
  if (typeof la !== 'number' || typeof lo !== 'number' || !isFinite(la) || !isFinite(lo)) return false;
  if (Math.abs(la) >= 90 || lo < -180 || lo >= 180) return false;
  const k = cellOf(la, lo);
  return Math.abs(k.la - la) < 1e-9 && Math.abs(k.lo - lo) < 1e-9;
}

export const cellKey = (c: Cell) => `${c.la},${c.lo}`;

/** Cells whose centres are within radiusKm (+ half a cell) of a cell. */
export function cellsNear(c: Cell, radiusKm: number): Cell[] {
  const dLat = radiusKm / 111.2;
  const dLon = radiusKm / (111.2 * Math.max(0.05, Math.cos(rad(c.la))));
  const out = new Map<string, Cell>();
  for (let la = c.la - dLat; la <= c.la + dLat + CELL_DEG; la += CELL_DEG) {
    for (let lo = c.lo - dLon; lo <= c.lo + dLon + CELL_DEG; lo += CELL_DEG) {
      const k = cellOf(la, lo);
      if (distanceKm(c.la, c.lo, k.la, k.lo) <= radiusKm + 40) out.set(cellKey(k), k);
    }
  }
  return [...out.values()];
}
