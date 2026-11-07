// Rare events: a small hand-curated list of comets and novae bright enough
// to look for. The phone only interpolates these rows; it never solves an
// orbit. To add one, append it to CURATED with daily rows from JPL Horizons
// (comets) or the discovery/AAVSO position (a nova doesn't move), run
// `npm test` (it checks the list) and deploy.

export type RareKind = 'comet' | 'nova';

export type EphemerisRow = {
  /** A UTC date, `YYYY-MM-DD`: the row is for 0h UT that day. */
  date: string;
  /** J2000 right ascension and declination, degrees. */
  ra: number;
  dec: number;
  /** Expected magnitude that day, when it changes (comets). */
  mag?: number;
};

export type RareEvent = {
  /** Stable and unique: `comet-c2020f3`, `nova-rsoph-2021`. */
  id: string;
  kind: RareKind;
  name: string;
  /** Expected magnitude, used when a row has none. */
  magnitude: number;
  /** A UTC date, `YYYY-MM-DD`: served until the end of that day. */
  validUntil: string;
  /** One plain sentence for the app, e.g. "Binoculars show the tail best." */
  note: string;
  ephemeris: EphemerisRow[];
};

/** What's live. Empty until there's something worth going out for. */
export const CURATED: RareEvent[] = [];

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const ID = /^[a-z0-9-]{3,64}$/;
// The app's own text check (test/data/invite_client_test.dart), so a
// name or note can always be shown and shared.
const TEXT = /^[\p{L}\p{N} .,;:'’()°%\-–—!?&/+]+$/u;

const isDate = (s: unknown): s is string => typeof s === 'string' && DATE.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));
const isNum = (n: unknown, lo: number, hi: number): n is number => typeof n === 'number' && Number.isFinite(n) && n >= lo && n <= hi;
const isText = (s: unknown, max: number): s is string => typeof s === 'string' && s.length > 0 && s.length <= max && TEXT.test(s);

/** Everything wrong with a list, or [] if it's fine to serve. */
export function problems(list: RareEvent[]): string[] {
  const out: string[] = [];
  const ids = new Set<string>();
  for (const e of list) {
    const at = typeof e.id === 'string' ? e.id : '?';
    if (typeof e.id !== 'string' || !ID.test(e.id)) out.push(`${at}: id`);
    if (ids.has(e.id)) out.push(`${at}: duplicate id`);
    ids.add(e.id);
    if (e.kind !== 'comet' && e.kind !== 'nova') out.push(`${at}: kind`);
    if (!isText(e.name, 60)) out.push(`${at}: name`);
    if (!isText(e.note, 200)) out.push(`${at}: note`);
    if (!isNum(e.magnitude, -10, 20)) out.push(`${at}: magnitude`);
    if (!isDate(e.validUntil)) out.push(`${at}: validUntil`);
    if (!Array.isArray(e.ephemeris) || e.ephemeris.length === 0) {
      out.push(`${at}: ephemeris`);
      continue;
    }
    let last = '';
    for (const r of e.ephemeris) {
      if (!isDate(r.date) || r.date <= last) out.push(`${at}: row ${r.date} date`);
      if (!isNum(r.ra, 0, 360) || r.ra === 360) out.push(`${at}: row ${r.date} ra`);
      if (!isNum(r.dec, -90, 90)) out.push(`${at}: row ${r.date} dec`);
      if (r.mag !== undefined && !isNum(r.mag, -10, 20)) out.push(`${at}: row ${r.date} mag`);
      last = typeof r.date === 'string' ? r.date : last;
    }
    // A comet moves: one row can't be interpolated. A nova stays put.
    if (e.kind === 'comet' && e.ephemeris.length < 2) out.push(`${at}: a comet needs daily rows`);
    if (isDate(e.validUntil) && e.validUntil > e.ephemeris[e.ephemeris.length - 1].date && e.kind === 'comet') {
      out.push(`${at}: valid past its last row`);
    }
  }
  return out;
}

/** The events still valid at [now]. */
export function live(list: RareEvent[], now: number): RareEvent[] {
  const today = new Date(now).toISOString().slice(0, 10);
  return list.filter((e) => e.validUntil >= today);
}
