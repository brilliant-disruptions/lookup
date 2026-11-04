// The relay's behaviour, free of the Workers runtime so tests can drive it.
//
//   POST   /v1/report     {cell: {la, lo}, how: 'eye'|'camera', reporter}
//   GET    /v1/reports?cells=la,lo;la,lo…        → {now, reports: [{la, lo, at, how, r}]}
//   POST   /v1/subscribe  {token, platform: 'apns'|'fcm', sandbox?, cells: [{la, lo}…]}
//   DELETE /v1/subscribe  {token}
//
// It stores and forwards. It never decides who sees an aurora: a wake-up
// push only tells phones nearby to look, and each phone runs crowdConfirms()
// with its own Kp and cloud (lib/domain/aurora/seen_nearby.dart).

import { cellKey, cellsNear, distanceKm, isCell, type Cell } from './cells';
import type { Pusher } from './push';
import { createInvite, serveInvite, type InviteDeps } from './invite';
import type { How, Platform, Store, StoredReport } from './store';

export const RULES = {
  /** Reports are kept this long, then deleted. */
  keepMs: 60 * 60 * 1000,
  /** What GET returns and what a wake-up counts. */
  windowMs: 20 * 60 * 1000,
  radiusKm: 250,
  /** Wake phones when this many people from this many cells report nearby. */
  wakeReporters: 4,
  wakeCells: 2,
  /** A phone is woken at most this often. */
  quietMs: 30 * 60 * 1000,
  /** One report per person per 5 minutes; 30 per hour per network. */
  reporterLimit: { n: 1, ms: 5 * 60 * 1000 },
  ipLimit: { n: 30, ms: 60 * 60 * 1000 },
  readLimit: { n: 240, ms: 60 * 60 * 1000 },
  /** The app asks for every cell within 250 km: up to ~170 that far north. */
  maxCells: 240,
  maxBody: 16384,
  /** An invite carries its card picture. */
  maxInviteBody: 1_100_000,
  inviteLimit: { n: 30, ms: 60 * 60 * 1000 },
  subsDays: 30,
};

export type Deps = {
  store: Store;
  /** Server-side secret: salts every hash, so nothing stored links to an install or a network. */
  secret: string;
  pushers: Partial<Record<Platform, Pusher>>;
  now: () => number;
  /** Background work after the response (ctx.waitUntil on Workers). */
  later: (p: Promise<unknown>) => void;
  /** "Look up with me" links; absent, the routes 404. */
  invites?: Omit<InviteDeps, 'store' | 'now'>;
};

const json = (status: number, body: unknown) =>
  new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });

/** HMAC of a value with today's date: the same person hashes the same all day, differently tomorrow. */
export async function dailyHash(secret: string, value: string, now: number): Promise<string> {
  const day = new Date(now).toISOString().slice(0, 10);
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${day}:${value}`)));
  return [...sig.slice(0, 12)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function body(req: Request, max: number = RULES.maxBody): Promise<Record<string, unknown> | null> {
  const text = await req.text();
  if (text.length > max) return null;
  try {
    const v = JSON.parse(text);
    return typeof v === 'object' && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

function cellsParam(s: string | null): Cell[] | null {
  if (!s) return null;
  const parts = s.split(';');
  if (parts.length > RULES.maxCells) return null;
  const out: Cell[] = [];
  for (const p of parts) {
    const [la, lo] = p.split(',').map(Number);
    const c = { la, lo };
    if (!isCell(c)) return null;
    out.push(c);
  }
  return out;
}

function cellsBody(v: unknown): Cell[] | null {
  if (!Array.isArray(v) || v.length === 0 || v.length > RULES.maxCells) return null;
  return v.every(isCell) ? (v as Cell[]).map((c) => ({ la: c.la, lo: c.lo })) : null;
}

const validToken = (t: unknown, min: number, max: number): t is string =>
  typeof t === 'string' && t.length >= min && t.length <= max && /^[A-Za-z0-9_:\-.]+$/.test(t);

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const url = new URL(req.url);
  const now = deps.now();
  const ip = req.headers.get('cf-connecting-ip') ?? 'unknown';
  const net = `ip:${await dailyHash(deps.secret, ip, now)}`;

  if (url.pathname === '/v1/health') return json(200, { ok: true });

  // "Look up with me" links.
  if (deps.invites) {
    const inv = { ...deps.invites, store: deps.store, now: deps.now };
    const base = deps.invites.site ?? url.origin;
    if (url.pathname.startsWith('/n/') && req.method === 'GET') return serveInvite(url.pathname, base, inv, req.headers.get('user-agent') ?? '');
    if (url.pathname === '/v1/invites' && req.method === 'POST') {
      if ((await deps.store.hit(`invite:${net}`, now, RULES.inviteLimit.ms)) > RULES.inviteLimit.n) return json(429, { error: 'slow down' });
      const b = await body(req, RULES.maxInviteBody);
      if (!b) return json(400, { error: 'invite' });
      return createInvite(b, base, inv);
    }
  }

  if (url.pathname === '/v1/reports' && req.method === 'GET') {
    if ((await deps.store.hit(`read:${net}`, now, RULES.readLimit.ms)) > RULES.readLimit.n) return json(429, { error: 'slow down' });
    const cells = cellsParam(url.searchParams.get('cells'));
    if (!cells) return json(400, { error: 'cells' });
    const rows = await deps.store.reportsIn(cells, now - RULES.windowMs);
    return json(200, {
      now: new Date(now).toISOString(),
      reports: rows.map((r) => ({ la: r.la, lo: r.lo, at: new Date(r.at).toISOString(), how: r.how, r: r.reporter })),
    });
  }

  if (url.pathname === '/v1/report' && req.method === 'POST') {
    const b = await body(req);
    if (!b || !isCell(b.cell) || (b.how !== 'eye' && b.how !== 'camera') || !validToken(b.reporter, 16, 64)) {
      return json(400, { error: 'report' });
    }
    const reporter = await dailyHash(deps.secret, b.reporter, now);
    if ((await deps.store.hit(`report:${net}`, now, RULES.ipLimit.ms)) > RULES.ipLimit.n) return json(429, { error: 'slow down' });
    if ((await deps.store.hit(`r:${reporter}`, now, RULES.reporterLimit.ms)) > RULES.reporterLimit.n) {
      return json(429, { error: 'already reported' });
    }
    const cell = b.cell as Cell;
    await deps.store.addReport({ la: cell.la, lo: cell.lo, at: now, how: b.how as How, reporter });
    deps.later(wakeNear(cell, deps));
    return json(202, null);
  }

  if (url.pathname === '/v1/subscribe' && (req.method === 'POST' || req.method === 'DELETE')) {
    const b = await body(req);
    if (!b || !validToken(b.token, 32, 4096)) return json(400, { error: 'token' });
    if ((await deps.store.hit(`sub:${net}`, now, RULES.ipLimit.ms)) > RULES.ipLimit.n) return json(429, { error: 'slow down' });
    if (req.method === 'DELETE') {
      await deps.store.unsubscribe(b.token);
      return json(204, null);
    }
    const cells = cellsBody(b.cells);
    if (!cells || (b.platform !== 'apns' && b.platform !== 'fcm')) return json(400, { error: 'subscription' });
    await deps.store.subscribe({ token: b.token, platform: b.platform, sandbox: b.sandbox === true }, cells, now);
    return json(204, null);
  }

  return json(404, { error: 'not found' });
}

/** Enough people near this cell, from more than one place, to be worth a look? */
export function worthWaking(cell: Cell, reports: StoredReport[]): boolean {
  const people = new Set<string>();
  const cells = new Set<string>();
  for (const r of reports) {
    if (distanceKm(cell.la, cell.lo, r.la, r.lo) > RULES.radiusKm) continue;
    people.add(r.reporter);
    cells.add(cellKey(r));
  }
  return people.size >= RULES.wakeReporters && cells.size >= RULES.wakeCells;
}

/** After a report: if it tips the area over, wake the phones watching it. */
export async function wakeNear(cell: Cell, deps: Deps): Promise<number> {
  const now = deps.now();
  const area = cellsNear(cell, RULES.radiusKm);
  const reports = await deps.store.reportsIn(area, now - RULES.windowMs);
  if (!worthWaking(cell, reports)) return 0;
  const subs = await deps.store.toWake(area, now - RULES.quietMs);
  if (subs.length === 0) return 0;
  await deps.store.markWoken(
    subs.map((s) => s.token),
    now,
  );
  let sent = 0;
  for (const s of subs) {
    const p = deps.pushers[s.platform];
    if (!p) continue;
    const r = await p.send(s);
    if (r === 'ok') sent++;
    if (r === 'gone') await deps.store.unsubscribe(s.token);
  }
  return sent;
}

/** Every ten minutes: forget old reports, limits and lapsed subscriptions. */
export const sweep = (store: Store, now: number) => store.sweep(now - RULES.keepMs, now - RULES.subsDays * 24 * 3600 * 1000, now);
