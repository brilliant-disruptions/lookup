import { describe, expect, it } from 'vitest';
import { CURATED, problems, type RareEvent } from '../src/rare_events';
import { handle, type Deps } from '../src/relay';
import { SqlStore } from '../src/store';
import { sqliteD1 } from './sqlite_d1';

// Comet NEOWISE (C/2020 F3), July 2020: RA/Dec from JPL Horizons
// (astrometric ICRF, 0h UT). Horizons' magnitude model had it near 7; the
// eye saw about 2, which is why a person curates the magnitudes.
const neowise: RareEvent = {
  id: 'comet-c2020f3',
  kind: 'comet',
  name: 'Comet NEOWISE',
  magnitude: 2.5,
  validUntil: '2020-07-14',
  note: 'Low in the north-west after dusk. Binoculars show the tail best.',
  ephemeris: [
    { date: '2020-07-12', ra: 104.09823, dec: 43.26226, mag: 2.2 },
    { date: '2020-07-13', ra: 107.44571, dec: 44.54155, mag: 2.4 },
    { date: '2020-07-14', ra: 111.2086, dec: 45.68422, mag: 2.6 },
  ],
};

// Nova RS Ophiuchi, August 2021 (AAVSO: 17h50m13.2s, −06°42′28″). It doesn't move.
const rsOph: RareEvent = {
  id: 'nova-rsoph-2021',
  kind: 'nova',
  name: 'RS Ophiuchi',
  magnitude: 4.8,
  validUntil: '2021-08-20',
  note: 'A star that wasn\'t there last week, in Ophiuchus.',
  ephemeris: [{ date: '2021-08-09', ra: 267.555, dec: -6.70778 }],
};

const deps = (now: number, rareEvents: RareEvent[]): Deps => ({
  store: new SqlStore(sqliteD1()),
  secret: 'test-secret',
  pushers: {},
  now: () => now,
  later: () => {},
  rareEvents,
});

const get = (d: Deps, method = 'GET') => handle(new Request('https://relay.test/v1/rare-events', { method }), d);

describe('rare events', () => {
  it('the curated list is always fit to serve', () => {
    // CI runs this before every deploy: a typo in CURATED fails here, not on phones.
    expect(problems(CURATED)).toEqual([]);
    expect(problems([neowise, rsOph])).toEqual([]);
  });

  it('serves what is still valid, to the end of its last day', async () => {
    const res = await get(deps(Date.UTC(2020, 6, 14, 23, 59), [neowise, rsOph]));
    expect(res.status).toBe(200);
    expect(res.headers.get('cache-control')).toBe('public, max-age=3600');
    const j = (await res.json()) as { now: string; events: RareEvent[] };
    expect(j.now).toBe('2020-07-14T23:59:00.000Z');
    expect(j.events.map((e) => e.id)).toEqual(['comet-c2020f3', 'nova-rsoph-2021']);
    expect(j.events[0]).toEqual(neowise);
  });

  it('drops an event the day after it expires, so a faded comet is never pushed', async () => {
    const j = (await (await get(deps(Date.UTC(2020, 6, 15), [neowise, rsOph]))).json()) as { events: RareEvent[] };
    expect(j.events.map((e) => e.id)).toEqual(['nova-rsoph-2021']);
    const later = (await (await get(deps(Date.UTC(2021, 7, 21), [neowise, rsOph]))).json()) as { events: RareEvent[] };
    expect(later.events).toEqual([]);
  });

  it('is read-only', async () => {
    expect((await get(deps(Date.UTC(2020, 6, 13), [neowise]), 'POST')).status).toBe(404);
  });

  it('catches the mistakes a person makes copying rows', () => {
    const bad = (patch: Partial<RareEvent>) => problems([{ ...neowise, ...patch }]);
    expect(bad({ kind: 'asteroid' as never })).toEqual(['comet-c2020f3: kind']);
    expect(bad({ id: 'Comet NEOWISE' })).toEqual(['Comet NEOWISE: id']);
    expect(bad({ validUntil: '14 July' })).toEqual(['comet-c2020f3: validUntil']);
    expect(bad({ name: 'NEOWISE <b>' })).toEqual(['comet-c2020f3: name']);
    // A slipped digit, rows out of order, a comet with one row.
    const [a, b, c] = neowise.ephemeris;
    expect(bad({ ephemeris: [{ ...a, ra: 404.09823 }, b, c] })).toEqual(['comet-c2020f3: row 2020-07-12 ra']);
    expect(bad({ ephemeris: [a, c, b], validUntil: '2020-07-13' })).toEqual([
      'comet-c2020f3: row 2020-07-13 date',
    ]);
    expect(bad({ ephemeris: [a], validUntil: '2020-07-12' })).toEqual(['comet-c2020f3: a comet needs daily rows']);
    // Valid after the rows run out would leave the phone guessing where it is.
    expect(bad({ validUntil: '2020-07-20' })).toEqual(['comet-c2020f3: valid past its last row']);
    expect(problems([neowise, neowise])).toEqual(['comet-c2020f3: duplicate id']);
  });
});
