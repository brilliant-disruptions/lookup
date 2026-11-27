// Clouds for the phones, from MET Norway's Locationforecast 2.0.
//
//   GET /v1/clouds?lat=36.17&lon=-86.78
//     → {issued, fetched, stale?, steps: [{t, hours, cloud, low, mid, high, fog, precipMm, precipProb}]}
//
// MET asks apps not to call it from phones but through a caching proxy, and
// sets rules for that proxy (https://api.met.no/doc/TermsOfService). This is
// the proxy, and every rule is kept here:
//
// - One fixed User-Agent naming the app and a contact, on every request.
// - Nothing is asked for again before the answer's Expires, nor within half
//   MET's update interval for the place: 30 minutes in the Nordic area
//   (updated hourly), 3 hours everywhere else (every 6 hours). After that,
//   If-Modified-Since with the stored Last-Modified; a 304 only pushes
//   Expires on. Each place's next ask is moved a few minutes by its own
//   name ([spread]), so places don't all come due as a model run lands.
// - At most 2 decimals of latitude and longitude (MET refuses 5+).
// - At most [MET.perSecond] calls a second, everyone's together (MET's
//   limit is 20 a second, all installs). Past it, phones get the copy we
//   have, or 503.
// - A 429 or 403 stops every call to MET for [MET.pauseMs]. Never a retry loop.
// - Only on demand: no prefetch, so no burst on the hour.
// - A 203 means the product is deprecated or beta: logged so we notice.
//
// Only a rough place (two decimals, about a kilometre) reaches MET, from
// Cloudflare: the phone's address never does. Rows are keyed by that place
// alone and swept after two days.
//
// The data is CC BY 4.0 (MET Norway). We change it (trimmed to clouds, fog
// and rain); the app's credits say so.

export const MET = {
  url: 'https://api.met.no/weatherapi/locationforecast/2.0/complete',
  userAgent: 'LookUpRelay/1.0 (+https://brilliantdisruptions.com; hello@brilliantdisruptions.com)',
  /** Never ask MET for the same place sooner than this, whatever Expires says:
   *  half its update interval (FAQ: hourly in the Nordic area, else 6-hourly). */
  minWaitNordicMs: 30 * 60 * 1000,
  minWaitMs: 3 * 3600 * 1000,
  /** Up to this much later again, by place, so places don't come due together. */
  spreadMs: 10 * 60 * 1000,
  /** After a 429 or 403, nobody's request reaches MET for this long. */
  pauseMs: 30 * 60 * 1000,
  /** Calls to MET a second, everyone's together: half of MET's 20. */
  perSecond: 10,
  /** After MET fails for a place (5xx, network), wait this long before asking again. */
  failWaitMs: 5 * 60 * 1000,
  /** One request at a time per place: a second one meanwhile gets the copy we have. */
  lockMs: 60 * 1000,
  /** Forecasts are deleted this long after they were last fetched. */
  keepMs: 2 * 24 * 3600 * 1000,
  /** What phones may cache an answer for. */
  clientMaxAge: 1800,
};

export type CloudsDeps = {
  db: D1Database;
  /** The Workers fetch, or a test's. */
  fetch: (input: string, init?: RequestInit) => Promise<Response>;
};

export type CloudStep = {
  /** ISO time the step starts. */
  t: string;
  /** How long the step stands for: 1 hour for the first ~2.5 days, then 6. */
  hours: number;
  /** Cloud cover, percent: total, low, middle and high. Null when MET leaves it out. */
  cloud: number | null;
  low: number | null;
  mid: number | null;
  high: number | null;
  /** Fog, percent; MET gives it for the first ~2.5 days only. */
  fog: number | null;
  /** Rain or snow over the step, mm, and its chance, percent (not everywhere). */
  precipMm: number | null;
  precipProb: number | null;
};

export type CloudsBody = { issued: string | null; fetched: string; steps: CloudStep[] };

type Row = { body: string; expires: number; last_modified: string | null; fetched_at: number };

const answer = (status: number, body: unknown, maxAge = 0) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json',
      'cache-control': maxAge > 0 ? `public, max-age=${maxAge}` : 'no-store',
    },
  });

/** A latitude or longitude as the phone sends it: a plain decimal number. */
const decimal = /^-?\d{1,3}(\.\d{1,8})?$/;

/** "36.17,-86.78": the place a forecast is kept and asked for under. Null if it isn't a place. */
export function placeKey(lat: string | null, lon: string | null): { key: string; lat: string; lon: string } | null {
  if (!lat || !lon || !decimal.test(lat) || !decimal.test(lon)) return null;
  const la = Number(lat);
  const lo = Number(lon);
  if (!(la >= -90 && la <= 90 && lo >= -180 && lo <= 180)) return null;
  const two = (v: number) => {
    const s = (Math.round(v * 100) / 100).toFixed(2);
    return s === '-0.00' ? '0.00' : s;
  };
  return { key: `${two(la)},${two(lo)}`, lat: two(la), lon: two(lo) };
}

/** Inside MET's Nordic area, where the forecast is updated hourly. Kept
 *  inside MET Nordic's domain on purpose: a place wrongly left out only
 *  waits longer. */
export function nordic(lat: number, lon: number): boolean {
  return lat >= 54.5 && lat <= 71.5 && lon >= 4 && lon <= 31.5;
}

/** How long a place waits before MET is asked about it again. */
export const minWait = (lat: number, lon: number) => (nordic(lat, lon) ? MET.minWaitNordicMs : MET.minWaitMs);

/** A fixed few minutes (under [MET.spreadMs]) for each place, from its key. */
export function spread(key: string): number {
  let h = 2166136261;
  for (let i = 0; i < key.length; i++) h = Math.imul(h ^ key.charCodeAt(i), 16777619);
  return (h >>> 0) % MET.spreadMs;
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/** MET's answer, cut down to what LookUp reads. Steps without a time are dropped. */
export function trim(met: unknown, fetched: number): CloudsBody {
  const props = (met as { properties?: { meta?: { updated_at?: unknown }; timeseries?: unknown } })?.properties;
  const series = Array.isArray(props?.timeseries) ? props.timeseries : [];
  const steps: CloudStep[] = [];
  for (const s of series as Array<Record<string, any>>) {
    const t = typeof s?.time === 'string' && !Number.isNaN(Date.parse(s.time)) ? s.time : null;
    if (!t) continue;
    const d = s.data ?? {};
    const now = d.instant?.details ?? {};
    const next = d.next_1_hours ? { h: 1, x: d.next_1_hours } : d.next_6_hours ? { h: 6, x: d.next_6_hours } : null;
    const nd = next?.x?.details ?? {};
    // A step with nothing after it (the last ones) stands for the 6 hours
    // the forecast steps by there.
    steps.push({
      t,
      hours: next?.h ?? 6,
      cloud: num(now.cloud_area_fraction),
      low: num(now.cloud_area_fraction_low),
      mid: num(now.cloud_area_fraction_medium),
      high: num(now.cloud_area_fraction_high),
      fog: num(now.fog_area_fraction),
      precipMm: num(nd.precipitation_amount),
      precipProb: num(nd.probability_of_precipitation),
    });
  }
  const issued = typeof props?.meta?.updated_at === 'string' ? props.meta.updated_at : null;
  return { issued, fetched: new Date(fetched).toISOString(), steps };
}

async function state(db: D1Database, key: string): Promise<number> {
  const r = await db.prepare('SELECT value FROM met_state WHERE key = ?').bind(key).first<{ value: number }>();
  return r?.value ?? 0;
}

async function setState(db: D1Database, key: string, value: number, until: number) {
  await db
    .prepare('INSERT INTO met_state (key, value, until) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, until = excluded.until')
    .bind(key, value, until)
    .run();
}

/** Takes the place's lock until `until`; false if someone else holds it. */
async function lock(db: D1Database, key: string, now: number, until: number): Promise<boolean> {
  const r = await db
    .prepare(
      'INSERT INTO met_state (key, value, until) VALUES (?, ?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value, until = excluded.until WHERE met_state.value <= ?',
    )
    .bind(`lock:${key}`, until, until, now)
    .run();
  return (r.meta?.changes ?? 0) > 0;
}

/** Counts a call to MET in this second; false (and not counted) if the second is full. */
async function spend(db: D1Database, now: number): Promise<boolean> {
  const w = Math.floor(now / 1000);
  const r = await db
    .prepare(
      'INSERT INTO met_state (key, value, until) VALUES (?, 1, ?) ON CONFLICT(key) DO UPDATE SET value = value + 1 WHERE met_state.value < ?',
    )
    .bind(`s:${w}`, (w + 2) * 1000, MET.perSecond)
    .run();
  return (r.meta?.changes ?? 0) > 0;
}

function served(row: Row, stale: boolean) {
  const body = JSON.parse(row.body) as CloudsBody;
  return answer(200, stale ? { ...body, stale: true } : body, stale ? 0 : MET.clientMaxAge);
}

/** What phones get when MET can't be asked: the copy we have, else 503. */
const fallback = (row: Row | null, why: string) =>
  row ? served(row, true) : answer(503, { error: why });

export async function serveClouds(url: URL, deps: CloudsDeps, now: number): Promise<Response> {
  const place = placeKey(url.searchParams.get('lat'), url.searchParams.get('lon'));
  if (!place) return answer(400, { error: 'lat and lon, please' });
  const db = deps.db;

  const row = await db
    .prepare('SELECT body, expires, last_modified, fetched_at FROM met_cache WHERE cell = ?')
    .bind(place.key)
    .first<Row>();
  if (row && row.expires > now) return served(row, false);

  if ((await state(db, 'pause')) > now) return fallback(row, 'paused');
  if (!(await lock(db, place.key, now, now + MET.lockMs))) return fallback(row, 'busy');
  if (!(await spend(db, now))) return fallback(row, 'busy');

  const headers: Record<string, string> = { 'user-agent': MET.userAgent, accept: 'application/json' };
  if (row?.last_modified) headers['if-modified-since'] = row.last_modified;

  let res: Response;
  try {
    res = await deps.fetch(`${MET.url}?lat=${place.lat}&lon=${place.lon}`, { headers });
  } catch {
    await setState(db, `lock:${place.key}`, now + MET.failWaitMs, now + MET.failWaitMs);
    return row ? served(row, true) : answer(502, { error: 'forecast unavailable' });
  }

  // "Expires" can't bring the next call sooner than half MET's update
  // interval here, and each place is moved on by its own few minutes.
  const expiresAt = () => {
    const e = Date.parse(res.headers.get('expires') ?? '');
    return Math.max(Number.isNaN(e) ? 0 : e, now + minWait(Number(place.lat), Number(place.lon))) + spread(place.key);
  };

  if (res.status === 429 || res.status === 403) {
    console.error(`MET Norway answered ${res.status}: pausing every call to it for ${MET.pauseMs / 60000} minutes`);
    await setState(db, 'pause', now + MET.pauseMs, now + MET.pauseMs);
    return fallback(row, 'paused');
  }

  if (res.status === 304 && row) {
    const lm = res.headers.get('last-modified') ?? row.last_modified;
    // Still the same forecast, checked just now.
    const body = { ...(JSON.parse(row.body) as CloudsBody), fetched: new Date(now).toISOString() };
    await db
      .prepare('UPDATE met_cache SET body = ?, expires = ?, last_modified = ?, fetched_at = ? WHERE cell = ?')
      .bind(JSON.stringify(body), expiresAt(), lm, now, place.key)
      .run();
    return answer(200, body, MET.clientMaxAge);
  }

  if (res.status === 200 || res.status === 203) {
    if (res.status === 203) console.warn('MET Norway answered 203: Locationforecast 2.0 is deprecated or beta; see api.met.no');
    let met: unknown;
    try {
      met = await res.json();
    } catch {
      met = null;
    }
    const body = trim(met, now);
    if (body.steps.length === 0) {
      await setState(db, `lock:${place.key}`, now + MET.failWaitMs, now + MET.failWaitMs);
      return row ? served(row, true) : answer(502, { error: 'forecast unavailable' });
    }
    await db
      .prepare(
        'INSERT INTO met_cache (cell, body, expires, last_modified, fetched_at) VALUES (?, ?, ?, ?, ?) ' +
          'ON CONFLICT(cell) DO UPDATE SET body = excluded.body, expires = excluded.expires, last_modified = excluded.last_modified, fetched_at = excluded.fetched_at',
      )
      .bind(place.key, JSON.stringify(body), expiresAt(), res.headers.get('last-modified'), now)
      .run();
    return answer(200, body, MET.clientMaxAge);
  }

  // 5xx, an unexpected 304, anything else: don't ask again for a while.
  console.warn(`MET Norway answered ${res.status} for a forecast`);
  await setState(db, `lock:${place.key}`, now + MET.failWaitMs, now + MET.failWaitMs);
  return row ? served(row, true) : answer(502, { error: 'forecast unavailable' });
}

/** The cron's cleanup: forecasts not fetched for two days, spent counters, old locks and pauses. */
export async function sweepClouds(db: D1Database, now: number) {
  const c = await db.prepare('DELETE FROM met_cache WHERE fetched_at < ?').bind(now - MET.keepMs).run();
  await db.prepare('DELETE FROM met_state WHERE until < ?').bind(now).run();
  return { forecasts: c.meta?.changes ?? 0 };
}
