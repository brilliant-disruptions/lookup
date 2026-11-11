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

/**
 * What's live. Today's app skips anything fainter than mag 5, so these two
 * are for the coming time-lapse feature: a camera can catch them, an eye
 * can't. Rows and magnitudes are JPL Horizons predictions (astrometric
 * ICRF, 0h UT), kept only on days it has them at mag 9 or brighter and at
 * least 35° from the Sun; comet forecasts can miss by magnitudes either way.
 */
export const CURATED: RareEvent[] = [
  {
    id: 'comet-45p-2027',
    kind: 'comet',
    name: 'Comet 45P/Honda–Mrkos–Pajdušáková',
    magnitude: 8.5,
    validUntil: '2027-08-22',
    note: 'Low in the east before dawn, in Gemini. A camera on a tripod can catch it.',
    ephemeris: [
      { date: '2027-08-15', ra: 102.73243, dec: 19.28403, mag: 8.9 },
      { date: '2027-08-16', ra: 104.47854, dec: 19.29446, mag: 8.8 },
      { date: '2027-08-17', ra: 106.19356, dec: 19.2875, mag: 8.7 },
      { date: '2027-08-18', ra: 107.87918, dec: 19.26387, mag: 8.7 },
      { date: '2027-08-19', ra: 109.5371, dec: 19.22421, mag: 8.6 },
      { date: '2027-08-20', ra: 111.16895, dec: 19.16911, mag: 8.5 },
      { date: '2027-08-21', ra: 112.7763, dec: 19.09907, mag: 8.4 },
      { date: '2027-08-22', ra: 114.36064, dec: 19.01457, mag: 8.4 },
    ],
  },
  {
    id: 'comet-c2026o1',
    kind: 'comet',
    name: 'Comet PANSTARRS (C/2026 O1)',
    magnitude: 8.7,
    validUntil: '2027-07-14',
    note: 'A southern-sky comet, climbing north through July. A camera on a tripod can catch it.',
    ephemeris: [
      { date: '2027-06-06', ra: 64.74395, dec: -75.51165, mag: 9.0 },
      { date: '2027-06-07', ra: 71.90983, dec: -75.70814, mag: 8.9 },
      { date: '2027-06-08', ra: 79.27733, dec: -75.69539, mag: 8.9 },
      { date: '2027-06-09', ra: 86.62528, dec: -75.4645, mag: 8.9 },
      { date: '2027-06-10', ra: 93.73595, dec: -75.01782, mag: 8.8 },
      { date: '2027-06-11', ra: 100.43202, dec: -74.36798, mag: 8.8 },
      { date: '2027-06-12', ra: 106.59781, dec: -73.53512, mag: 8.8 },
      { date: '2027-06-13', ra: 112.18068, dec: -72.54339, mag: 8.7 },
      { date: '2027-06-14', ra: 117.17871, dec: -71.41795, mag: 8.7 },
      { date: '2027-06-15', ra: 121.6235, dec: -70.1829, mag: 8.7 },
      { date: '2027-06-16', ra: 125.56465, dec: -68.86018, mag: 8.7 },
      { date: '2027-06-17', ra: 129.0585, dec: -67.4691, mag: 8.7 },
      { date: '2027-06-18', ra: 132.1611, dec: -66.02641, mag: 8.6 },
      { date: '2027-06-19', ra: 134.92448, dec: -64.54648, mag: 8.6 },
      { date: '2027-06-20', ra: 137.39505, dec: -63.04161, mag: 8.6 },
      { date: '2027-06-21', ra: 139.61321, dec: -61.52226, mag: 8.6 },
      { date: '2027-06-22', ra: 141.61365, dec: -59.99737, mag: 8.6 },
      { date: '2027-06-23', ra: 143.42594, dec: -58.47456, mag: 8.6 },
      { date: '2027-06-24', ra: 145.07513, dec: -56.96029, mag: 8.6 },
      { date: '2027-06-25', ra: 146.5825, dec: -55.46004, mag: 8.6 },
      { date: '2027-06-26', ra: 147.96607, dec: -53.97842, mag: 8.6 },
      { date: '2027-06-27', ra: 149.24116, dec: -52.51928, mag: 8.6 },
      { date: '2027-06-28', ra: 150.42084, dec: -51.08581, mag: 8.6 },
      { date: '2027-06-29', ra: 151.51625, dec: -49.6806, mag: 8.7 },
      { date: '2027-06-30', ra: 152.53698, dec: -48.30573, mag: 8.7 },
      { date: '2027-07-01', ra: 153.49126, dec: -46.96282, mag: 8.7 },
      { date: '2027-07-02', ra: 154.3862, dec: -45.65308, mag: 8.7 },
      { date: '2027-07-03', ra: 155.22797, dec: -44.37736, mag: 8.7 },
      { date: '2027-07-04', ra: 156.02193, dec: -43.13621, mag: 8.7 },
      { date: '2027-07-05', ra: 156.77277, dec: -41.92991, mag: 8.8 },
      { date: '2027-07-06', ra: 157.48457, dec: -40.75849, mag: 8.8 },
      { date: '2027-07-07', ra: 158.16095, dec: -39.6218, mag: 8.8 },
      { date: '2027-07-08', ra: 158.80508, dec: -38.51949, mag: 8.8 },
      { date: '2027-07-09', ra: 159.41977, dec: -37.45111, mag: 8.9 },
      { date: '2027-07-10', ra: 160.00752, dec: -36.41605, mag: 8.9 },
      { date: '2027-07-11', ra: 160.57057, dec: -35.41363, mag: 8.9 },
      { date: '2027-07-12', ra: 161.11091, dec: -34.4431, mag: 8.9 },
      { date: '2027-07-13', ra: 161.63033, dec: -33.50364, mag: 9.0 },
      { date: '2027-07-14', ra: 162.13046, dec: -32.5944, mag: 9.0 },
    ],
  },
];

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
