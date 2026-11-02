import { beforeEach, describe, expect, it } from 'vitest';
import { cellOf, cellsNear, isCell, type Cell } from '../src/cells';
import type { Pusher, PushResult } from '../src/push';
import { RULES, handle, sweep, wakeNear, type Deps } from '../src/relay';
import { SqlStore, type Subscriber } from '../src/store';
import { sqliteD1 } from './sqlite_d1';

const T0 = Date.UTC(2026, 10, 2, 22, 0);

class FakePusher implements Pusher {
  sent: string[] = [];
  answer: PushResult = 'ok';
  async send(s: Subscriber) {
    this.sent.push(s.token);
    return this.answer;
  }
}

// Around Edinburgh, as in test/domain/seen_nearby_test.dart.
const glasgow = cellOf(55.86, -4.25);
const perth = cellOf(56.4, -3.43);
const borders = cellOf(55.6, -2.73);
const fife = cellOf(56.12, -3.16);
const edinburgh = cellOf(55.95, -3.19);
const london = cellOf(51.5, -0.12);

let now: number;
let store: SqlStore;
let apns: FakePusher;
let fcm: FakePusher;
let pending: Promise<unknown>[];
let deps: Deps;

beforeEach(() => {
  now = T0;
  store = new SqlStore(sqliteD1());
  apns = new FakePusher();
  fcm = new FakePusher();
  pending = [];
  deps = { store, secret: 'test-secret', pushers: { apns, fcm }, now: () => now, later: (p) => pending.push(p) };
});

const call = (method: string, path: string, body?: unknown, ip = '203.0.113.7') =>
  handle(
    new Request(`https://relay.test${path}`, {
      method,
      headers: { 'cf-connecting-ip': ip, 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    }),
    deps,
  );

const report = (cell: Cell, reporter: string, how = 'eye', ip?: string) => call('POST', '/v1/report', { cell, how, reporter }, ip);
const token = (n: string) => `${n}`.padEnd(64, 'x');
const settle = async () => {
  await Promise.all(pending);
  pending = [];
};

describe('cells', () => {
  it('match the app: half-degree centres, nothing finer accepted', () => {
    expect(cellOf(55.9533, -3.1883)).toEqual({ la: 55.75, lo: -3.25 });
    expect(isCell({ la: 55.75, lo: -3.25 })).toBe(true);
    expect(isCell({ la: 55.9533, lo: -3.1883 })).toBe(false);
    expect(isCell({ la: 95, lo: 0 })).toBe(false);
    expect(isCell('55.75,-3.25')).toBe(false);
    const near = cellsNear(edinburgh, 250);
    expect(near.length).toBeGreaterThan(20);
    expect(near.length).toBeLessThanOrEqual(RULES.maxCells);
    // As far north as the feature is offered (Tromsø), still within the limit.
    expect(cellsNear(cellOf(69.65, 18.96), 250).length).toBeLessThanOrEqual(RULES.maxCells);
  });
});

describe('reports', () => {
  it('are stored with a hashed reporter, never the token, and read back by cell', async () => {
    expect((await report(glasgow, token('alice'))).status).toBe(202);
    const res = await call('GET', `/v1/reports?cells=${glasgow.la},${glasgow.lo};${perth.la},${perth.lo}`);
    expect(res.status).toBe(200);
    const j = (await res.json()) as { reports: { la: number; lo: number; at: string; how: string; r: string }[] };
    expect(j.reports).toHaveLength(1);
    expect(j.reports[0]).toMatchObject({ la: glasgow.la, lo: glasgow.lo, how: 'eye', at: new Date(T0).toISOString() });
    expect(j.reports[0].r).not.toContain('alice');
    expect(j.reports[0].r).toMatch(/^[0-9a-f]{24}$/);
  });

  it('reject anything but a grid cell, a known "how" and a sane token', async () => {
    expect((await report({ la: 55.9533, lo: -3.1883 } as Cell, token('a'))).status).toBe(400);
    expect((await report(glasgow, token('a'), 'telescope')).status).toBe(400);
    expect((await report(glasgow, 'short')).status).toBe(400);
    expect((await call('POST', '/v1/report', 'not json')).status).toBe(400);
    expect((await call('GET', '/v1/reports?cells=55.9533,-3.18')).status).toBe(400);
    const many = Array.from({ length: RULES.maxCells + 1 }, (_, i) => `${0.25 + (i % 100) * 0.5},0.25`).join(';');
    expect((await call('GET', `/v1/reports?cells=${many}`)).status).toBe(400);
  });

  it('one per person per five minutes', async () => {
    expect((await report(glasgow, token('bob'))).status).toBe(202);
    expect((await report(glasgow, token('bob'))).status).toBe(429);
    now += 6 * 60 * 1000;
    expect((await report(glasgow, token('bob'))).status).toBe(202);
  });

  it('a network can\'t flood it', async () => {
    let last = 0;
    for (let i = 0; i <= RULES.ipLimit.n; i++) last = (await report(glasgow, token(`p${i}`), 'eye', '198.51.100.1')).status;
    expect(last).toBe(429);
    expect((await report(glasgow, token('fresh'), 'eye', '198.51.100.2')).status).toBe(202);
  });

  it('only the last twenty minutes are returned; the sweep forgets them after an hour', async () => {
    await report(glasgow, token('old'));
    now += 25 * 60 * 1000;
    await report(glasgow, token('new'));
    const j = (await (await call('GET', `/v1/reports?cells=${glasgow.la},${glasgow.lo}`)).json()) as { reports: unknown[] };
    expect(j.reports).toHaveLength(1);
    now += 50 * 60 * 1000;
    const swept = await sweep(store, now);
    expect(swept.reports).toBe(1);
  });
});

describe('waking phones', () => {
  const subscribe = (t: string, platform: 'apns' | 'fcm', cells: Cell[]) => call('POST', '/v1/subscribe', { token: t, platform, cells });

  beforeEach(async () => {
    expect((await subscribe(token('iphone-edinburgh'), 'apns', cellsNear(edinburgh, 250))).status).toBe(204);
    expect((await subscribe(token('android-edinburgh'), 'fcm', [edinburgh])).status).toBe(204);
    expect((await subscribe(token('android-london'), 'fcm', [london])).status).toBe(204);
  });

  it('nobody is woken until four people from two places report', async () => {
    await report(glasgow, token('a'));
    await report(glasgow, token('b'));
    await report(perth, token('c'));
    await settle();
    expect([...apns.sent, ...fcm.sent]).toHaveLength(0);
    await report(fife, token('d'));
    await settle();
    expect(apns.sent).toEqual([token('iphone-edinburgh')]);
    expect(fcm.sent).toEqual([token('android-edinburgh')]);
  });

  it('a crowd in one spot isn\'t enough', async () => {
    for (const n of ['a', 'b', 'c', 'd', 'e', 'f']) await report(glasgow, token(n), 'eye', `192.0.2.${n.charCodeAt(0)}`);
    await settle();
    expect([...apns.sent, ...fcm.sent]).toHaveLength(0);
  });

  it('each phone at most once per half hour; far-away phones never', async () => {
    for (const [c, n] of [[glasgow, 'a'], [perth, 'b'], [borders, 'c'], [fife, 'd']] as const) await report(c, token(n));
    await settle();
    expect(fcm.sent).toEqual([token('android-edinburgh')]);
    await report(edinburgh, token('e'));
    await settle();
    expect(fcm.sent).toHaveLength(1);
    now += 31 * 60 * 1000;
    for (const [c, n] of [[glasgow, 'f'], [perth, 'g'], [borders, 'h'], [fife, 'i']] as const) await report(c, token(n));
    await settle();
    expect(fcm.sent).toEqual([token('android-edinburgh'), token('android-edinburgh')]);
    expect(fcm.sent).not.toContain(token('android-london'));
  });

  it('tokens the push service says are gone are dropped', async () => {
    fcm.answer = 'gone';
    for (const [c, n] of [[glasgow, 'a'], [perth, 'b'], [borders, 'c'], [fife, 'd']] as const) await report(c, token(n));
    await settle();
    const left = (await store.toWake([edinburgh], now + 1)).map((s) => s.token);
    expect(left).not.toContain(token('android-edinburgh'));
    expect(left).toContain(token('iphone-edinburgh'));
  });

  it('unsubscribing stops it, and lapsed subscriptions are swept after 30 days', async () => {
    expect((await call('DELETE', '/v1/subscribe', { token: token('android-edinburgh') })).status).toBe(204);
    for (const [c, n] of [[glasgow, 'a'], [perth, 'b'], [borders, 'c'], [fife, 'd']] as const) await report(c, token(n));
    await settle();
    expect(fcm.sent).toHaveLength(0);
    now += 31 * 24 * 3600 * 1000;
    expect((await sweep(store, now)).subs).toBe(2);
  });

  it('the whole 250 km area can be asked for in one go, across the date line too', async () => {
    const res = await call('GET', `/v1/reports?cells=${cellsNear(edinburgh, 250).map((c) => `${c.la},${c.lo}`).join(';')}`);
    expect(res.status).toBe(200);
    const east = cellOf(65, 179.9), west = cellOf(65, -179.9);
    await report(west, token('dateline'));
    const j = (await (await call('GET', `/v1/reports?cells=${east.la},${east.lo};${west.la},${west.lo}`)).json()) as { reports: unknown[] };
    expect(j.reports).toHaveLength(1);
  });

  it('a wake with no reports around does nothing', async () => {
    expect(await wakeNear(edinburgh, deps)).toBe(0);
  });
});
