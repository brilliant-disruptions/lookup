import { beforeEach, describe, expect, it } from 'vitest';
import { MET, minWait, nordic, placeKey, spread, sweepClouds, trim, type CloudsDeps } from '../src/met';
import { handle, type Deps } from '../src/relay';
import { SqlStore } from '../src/store';
import { sqliteD1 } from './sqlite_d1';

const T0 = Date.UTC(2026, 10, 27, 20, 7);
const MIN = 60 * 1000;

// A trimmed-down Locationforecast "complete" answer: two hourly steps, a
// six-hourly one (no fog, no probability: MET leaves them out that far
// ahead) and a last step with nothing after it.
const metAnswer = {
  type: 'Feature',
  properties: {
    meta: { updated_at: '2026-11-27T19:40:12Z', units: {} },
    timeseries: [
      {
        time: '2026-11-27T20:00:00Z',
        data: {
          instant: { details: { cloud_area_fraction: 12.5, cloud_area_fraction_low: 3.1, cloud_area_fraction_medium: 0, cloud_area_fraction_high: 9.4, fog_area_fraction: 0, air_temperature: 4 } },
          next_1_hours: { summary: { symbol_code: 'clearsky_night' }, details: { precipitation_amount: 0, probability_of_precipitation: 2 } },
          next_6_hours: { details: { precipitation_amount: 0 } },
        },
      },
      {
        time: '2026-11-27T21:00:00Z',
        data: {
          instant: { details: { cloud_area_fraction: 88, cloud_area_fraction_low: 80, cloud_area_fraction_medium: 20, cloud_area_fraction_high: 0, fog_area_fraction: 64.2 } },
          next_1_hours: { details: { precipitation_amount: 0.6, probability_of_precipitation: 71 } },
        },
      },
      {
        time: '2026-11-30T00:00:00Z',
        data: {
          instant: { details: { cloud_area_fraction: 40, cloud_area_fraction_low: 10, cloud_area_fraction_medium: 20, cloud_area_fraction_high: 30 } },
          next_6_hours: { details: { precipitation_amount: 1.2 } },
        },
      },
      { time: '2026-12-07T00:00:00Z', data: { instant: { details: { cloud_area_fraction: 100 } } } },
      { data: { instant: { details: { cloud_area_fraction: 5 } } } },
    ],
  },
};

type Call = { url: string; headers: Record<string, string> };

let now: number;
let db: D1Database;
let calls: Call[];
let reply: () => Response | Promise<Response>;
let deps: Deps;

const ok = (extra: Record<string, string> = {}) => () =>
  new Response(JSON.stringify(metAnswer), {
    status: 200,
    headers: { 'content-type': 'application/json', expires: new Date(now + 50 * MIN).toUTCString(), 'last-modified': 'Fri, 27 Nov 2026 19:40:12 GMT', ...extra },
  });

beforeEach(() => {
  now = T0;
  db = sqliteD1();
  calls = [];
  reply = ok();
  const clouds: CloudsDeps = {
    db,
    fetch: async (url, init) => {
      calls.push({ url, headers: { ...(init?.headers as Record<string, string>) } });
      return reply();
    },
  };
  deps = { store: new SqlStore(db), secret: 's', pushers: {}, now: () => now, later: () => {}, clouds };
});

const get = (q: string, ip = '203.0.113.9') =>
  handle(new Request(`https://relay.test/v1/clouds?${q}`, { headers: { 'cf-connecting-ip': ip } }), deps);

describe('placeKey', () => {
  it('rounds to two decimals and refuses what is not a place', () => {
    expect(placeKey('36.16589', '-86.78444')).toEqual({ key: '36.17,-86.78', lat: '36.17', lon: '-86.78' });
    expect(placeKey('-0.001', '0')?.key).toBe('0.00,0.00');
    expect(placeKey('91', '0')).toBeNull();
    expect(placeKey('10', '181')).toBeNull();
    expect(placeKey('1e2', '0')).toBeNull();
    expect(placeKey('abc', '0')).toBeNull();
    expect(placeKey(null, '0')).toBeNull();
  });
});

describe('how long a place waits', () => {
  it('30 minutes in the Nordic area, 3 hours anywhere else', () => {
    for (const [la, lo] of [[59.91, 10.75], [63.43, 10.4], [69.65, 18.96], [59.33, 18.07], [60.17, 24.94], [55.68, 12.57]]) {
      expect(nordic(la, lo), `${la},${lo}`).toBe(true);
      expect(minWait(la, lo)).toBe(30 * MIN);
    }
    for (const [la, lo] of [[36.17, -86.78], [51.51, -0.13], [78.22, 15.65], [-33.87, 151.21], [64.15, -21.94], [52.52, 13.4]]) {
      expect(nordic(la, lo), `${la},${lo}`).toBe(false);
      expect(minWait(la, lo)).toBe(3 * 60 * MIN);
    }
  });

  it('each place comes due a fixed few minutes later, not all at once', () => {
    const s = [...Array(200).keys()].map((i) => spread(`${(i / 100).toFixed(2)},1.00`));
    expect(spread('36.17,-86.78')).toBe(spread('36.17,-86.78'));
    for (const x of s) expect(x >= 0 && x < MET.spreadMs).toBe(true);
    // Spread over the ten minutes: every minute gets some.
    expect(new Set(s.map((x) => Math.floor(x / MIN))).size).toBe(10);
  });
});

describe('trim', () => {
  it('keeps clouds, fog and rain, hourly then six-hourly', () => {
    const b = trim(metAnswer, T0);
    expect(b.issued).toBe('2026-11-27T19:40:12Z');
    expect(b.fetched).toBe(new Date(T0).toISOString());
    expect(b.steps).toHaveLength(4); // the step without a time is dropped
    expect(b.steps[0]).toEqual({ t: '2026-11-27T20:00:00Z', hours: 1, cloud: 12.5, low: 3.1, mid: 0, high: 9.4, fog: 0, precipMm: 0, precipProb: 2 });
    expect(b.steps[1]).toMatchObject({ hours: 1, fog: 64.2, precipMm: 0.6, precipProb: 71 });
    expect(b.steps[2]).toEqual({ t: '2026-11-30T00:00:00Z', hours: 6, cloud: 40, low: 10, mid: 20, high: 30, fog: null, precipMm: 1.2, precipProb: null });
    expect(b.steps[3]).toMatchObject({ hours: 6, cloud: 100, low: null, precipMm: null });
    expect(JSON.stringify(b)).not.toContain('air_temperature');
  });

  it('survives an answer that is not a forecast', () => {
    expect(trim(null, T0).steps).toEqual([]);
    expect(trim({ properties: { timeseries: 'x' } }, T0).steps).toEqual([]);
  });
});

describe('GET /v1/clouds', () => {
  it('asks MET once, as LookUp, for a rough place, then serves its copy', async () => {
    const r = await get('lat=36.16589&lon=-86.78444');
    expect(r.status).toBe(200);
    expect(r.headers.get('cache-control')).toBe(`public, max-age=${MET.clientMaxAge}`);
    const body = (await r.json()) as { steps: unknown[]; stale?: boolean };
    expect(body.steps).toHaveLength(4);
    expect(body.stale).toBeUndefined();

    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe('https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=36.17&lon=-86.78');
    expect(calls[0].headers['user-agent']).toBe('LookUpRelay/1.0 (+https://brilliantdisruptions.com; hello@brilliantdisruptions.com)');
    expect(calls[0].headers['if-modified-since']).toBeUndefined();

    // Another phone nearby, inside Expires: no call to MET.
    now += 40 * MIN;
    expect((await get('lat=36.17&lon=-86.784')).status).toBe(200);
    expect(calls).toHaveLength(1);
  });

  it('never sends more than two decimals', async () => {
    for (const [la, lo] of [['51.123456', '-0.987654'], ['-33.8688', '151.2093'], ['0.005', '-0.004']]) {
      await get(`lat=${la}&lon=${lo}`);
    }
    for (const c of calls) {
      const u = new URL(c.url);
      for (const k of ['lat', 'lon']) expect(u.searchParams.get(k)).toMatch(/^-?\d{1,3}\.\d{2}$/);
    }
  });

  it('asks again only after Expires, with If-Modified-Since, and a 304 keeps the copy', async () => {
    await get('lat=60.39&lon=5.32');
    now += 50 * MIN + spread('60.39,5.32') - 1;
    await get('lat=60.39&lon=5.32');
    expect(calls).toHaveLength(1);
    now += 2;
    reply = () => new Response(null, { status: 304, headers: { expires: new Date(now + 40 * MIN).toUTCString() } });
    const r = await get('lat=60.39&lon=5.32');
    expect(calls).toHaveLength(2);
    expect(calls[1].headers['if-modified-since']).toBe('Fri, 27 Nov 2026 19:40:12 GMT');
    expect(r.status).toBe(200);
    const body = (await r.json()) as { steps: unknown[]; fetched: string };
    expect(body.steps).toHaveLength(4);
    expect(body.fetched).toBe(new Date(now).toISOString());

    // The 304's Expires holds too.
    now += 35 * MIN + spread('60.39,5.32');
    await get('lat=60.39&lon=5.32');
    expect(calls).toHaveLength(2);
  });

  // MET's FAQ: wait at least half the update interval. Bergen is in the
  // Nordic area (hourly), Nashville isn't (every 6 hours).
  for (const [name, lat, lon, wait] of [
    ['Bergen', '60.39', '5.32', 30 * MIN],
    ['Nashville', '36.17', '-86.78', 3 * 60 * MIN],
  ] as const) {
    it(`waits ${wait / MIN} minutes in ${name} even when Expires says sooner`, async () => {
      reply = ok({ expires: new Date(now + 2 * MIN).toUTCString() });
      await get(`lat=${lat}&lon=${lon}`);
      now += wait + spread(`${lat},${lon}`) - 1;
      await get(`lat=${lat}&lon=${lon}`);
      expect(calls).toHaveLength(1);
      now += 2;
      await get(`lat=${lat}&lon=${lon}`);
      expect(calls).toHaveLength(2);
    });
  }

  it(`keeps to ${MET.perSecond} calls to MET a second, everyone's together`, async () => {
    for (let i = 0; i < MET.perSecond + 5; i++) await get(`lat=${(i / 100).toFixed(2)}&lon=2.00`, `198.51.${i}.1`);
    expect(calls).toHaveLength(MET.perSecond);
    now += 1000;
    expect((await get('lat=50.00&lon=2.00', '192.0.2.1')).status).toBe(200);
    expect(calls).toHaveLength(MET.perSecond + 1);
  });

  it('a 429 stops every call to MET for 30 minutes and serves what it has', async () => {
    await get('lat=60.39&lon=5.32');
    now += 60 * MIN;
    reply = () => new Response('slow down', { status: 429 });
    const r = await get('lat=60.39&lon=5.32');
    expect(r.status).toBe(200);
    expect(((await r.json()) as { stale?: boolean }).stale).toBe(true);
    expect(r.headers.get('cache-control')).toBe('no-store');
    expect(calls).toHaveLength(2);

    // Other places too, and nothing to give them.
    reply = ok();
    expect((await get('lat=10.00&lon=10.00')).status).toBe(503);
    now += 29 * MIN;
    expect((await get('lat=60.39&lon=5.32')).status).toBe(200);
    expect(calls).toHaveLength(2);

    now += 2 * MIN;
    await get('lat=10.00&lon=10.00');
    expect(calls).toHaveLength(3);
  });

  it('a 403 pauses too', async () => {
    reply = () => new Response('forbidden', { status: 403 });
    expect((await get('lat=1&lon=1')).status).toBe(503);
    reply = ok();
    expect((await get('lat=2&lon=2')).status).toBe(503);
    expect(calls).toHaveLength(1);
  });

  it('after a failure, the place waits instead of retrying', async () => {
    reply = () => new Response('oops', { status: 500 });
    expect((await get('lat=1&lon=1')).status).toBe(502);
    expect((await get('lat=1&lon=1')).status).toBe(503);
    expect(calls).toHaveLength(1);
    reply = () => Promise.reject(new Error('network'));
    now += MET.failWaitMs + 1;
    expect((await get('lat=1&lon=1')).status).toBe(502);
    expect(calls).toHaveLength(2);
    reply = ok();
    now += MET.failWaitMs + 1;
    expect((await get('lat=1&lon=1')).status).toBe(200);
  });

  it('a 203 is served, and said', async () => {
    reply = () => new Response(JSON.stringify(metAnswer), { status: 203 });
    expect((await get('lat=1&lon=1')).status).toBe(200);
  });

  it('refuses what is not a place', async () => {
    expect((await get('lat=95&lon=1')).status).toBe(400);
    expect((await get('lon=1')).status).toBe(400);
    expect(calls).toHaveLength(0);
  });

  it('the cron forgets forecasts after two days, and spent counters', async () => {
    await get('lat=1&lon=1');
    expect((await sweepClouds(db, now + MET.keepMs - 1)).forecasts).toBe(0);
    expect((await sweepClouds(db, now + MET.keepMs + 1)).forecasts).toBe(1);
    const left = await db.prepare('SELECT COUNT(*) AS n FROM met_state').first<{ n: number }>();
    expect(left?.n).toBe(0);
  });
});
