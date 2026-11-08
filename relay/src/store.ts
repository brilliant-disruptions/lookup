// Everything the relay keeps, behind one interface: D1 in production, and
// the same SQL on node:sqlite in tests (test/sqlite_d1.ts).

import { cellKey, type Cell } from './cells';

export type How = 'eye' | 'camera';
export type Platform = 'apns' | 'fcm';

export type StoredReport = { la: number; lo: number; at: number; how: How; reporter: string };
export type Subscriber = { token: string; platform: Platform; sandbox: boolean };

export interface Store {
  addReport(r: StoredReport): Promise<void>;
  reportsIn(cells: Cell[], since: number): Promise<StoredReport[]>;
  /** Counts a hit on a rate-limit key; returns how many in the window. */
  hit(key: string, now: number, windowMs: number): Promise<number>;
  subscribe(s: Subscriber, cells: Cell[], now: number): Promise<void>;
  unsubscribe(token: string): Promise<void>;
  /** Subscribers to any of these cells not woken since `quietSince`. */
  toWake(cells: Cell[], quietSince: number): Promise<Subscriber[]>;
  markWoken(tokens: string[], now: number): Promise<void>;
  /** Drops reports and limits older than `before`, subscriptions not renewed since `subsBefore`, and expired invites. */
  sweep(before: number, subsBefore: number, now?: number): Promise<{ reports: number; subs: number; invites?: number }>;
  addInvite(code: string, data: string, image: Uint8Array | null, expires: number, now: number): Promise<void>;
  /** The invite's JSON, unless it has expired. */
  getInvite(code: string, now: number): Promise<{ data: string } | null>;
  inviteImage(code: string): Promise<Uint8Array | null>;
  /** Counts an invite page view or "Get reminders" tap for the day. */
  tally(what: 'view' | 'get', now: number): Promise<void>;
  /** Totals since `sinceDay` (YYYY-MM-DD, inclusive). */
  tallies(sinceDay: string): Promise<{ view: number; get: number }>;
}

/** The SQL store. Works on D1 and on anything with D1's prepare/bind API. */
export class SqlStore implements Store {
  constructor(private db: D1Database) {}

  async addReport(r: StoredReport) {
    await this.db
      .prepare('INSERT INTO reports (la, lo, at, how, reporter) VALUES (?, ?, ?, ?, ?)')
      .bind(r.la, r.lo, r.at, r.how, r.reporter)
      .run();
  }

  async reportsIn(cells: Cell[], since: number) {
    if (cells.length === 0) return [];
    // D1 allows 100 bound parameters a query: ask for the cells' bounding
    // box, then keep only the cells asked for.
    const box = bbox(cells);
    const want = new Set(cells.map(cellKey));
    const { results } = await this.db
      .prepare('SELECT la, lo, at, how, reporter FROM reports WHERE at >= ? AND la BETWEEN ? AND ? AND lo BETWEEN ? AND ? ORDER BY at DESC LIMIT 5000')
      .bind(since, box.laMin, box.laMax, box.loMin, box.loMax)
      .all<StoredReport>();
    return (results ?? []).filter((r) => want.has(cellKey(r)));
  }

  async hit(key: string, now: number, windowMs: number) {
    await this.db.prepare('INSERT INTO limits (key, at) VALUES (?, ?)').bind(key, now).run();
    const row = await this.db
      .prepare('SELECT COUNT(*) AS n FROM limits WHERE key = ? AND at > ?')
      .bind(key, now - windowMs)
      .first<{ n: number }>();
    return row?.n ?? 0;
  }

  async subscribe(s: Subscriber, cells: Cell[], now: number) {
    await this.db.batch([
      this.db
        .prepare(
          'INSERT INTO subs (token, platform, sandbox, updated, woken) VALUES (?, ?, ?, ?, 0) ' +
            'ON CONFLICT(token) DO UPDATE SET platform = excluded.platform, sandbox = excluded.sandbox, updated = excluded.updated',
        )
        .bind(s.token, s.platform, s.sandbox ? 1 : 0, now),
      this.db.prepare('DELETE FROM sub_cells WHERE token = ?').bind(s.token),
      ...cells.map((c) => this.db.prepare('INSERT INTO sub_cells (token, la, lo) VALUES (?, ?, ?)').bind(s.token, c.la, c.lo)),
    ]);
  }

  async unsubscribe(token: string) {
    await this.db.batch([
      this.db.prepare('DELETE FROM sub_cells WHERE token = ?').bind(token),
      this.db.prepare('DELETE FROM subs WHERE token = ?').bind(token),
    ]);
  }

  async toWake(cells: Cell[], quietSince: number) {
    if (cells.length === 0) return [];
    const box = bbox(cells);
    const want = new Set(cells.map(cellKey));
    const { results } = await this.db
      .prepare(
        'SELECT s.token AS token, s.platform AS platform, s.sandbox AS sandbox, c.la AS la, c.lo AS lo FROM subs s ' +
          'JOIN sub_cells c ON c.token = s.token WHERE s.woken < ? AND c.la BETWEEN ? AND ? AND c.lo BETWEEN ? AND ?',
      )
      .bind(quietSince, box.laMin, box.laMax, box.loMin, box.loMax)
      .all<{ token: string; platform: Platform; sandbox: number; la: number; lo: number }>();
    const out = new Map<string, Subscriber>();
    for (const r of results ?? []) {
      if (want.has(cellKey(r))) out.set(r.token, { token: r.token, platform: r.platform, sandbox: r.sandbox === 1 });
    }
    return [...out.values()];
  }

  async markWoken(tokens: string[], now: number) {
    if (tokens.length === 0) return;
    await this.db.batch(tokens.map((t) => this.db.prepare('UPDATE subs SET woken = ? WHERE token = ?').bind(now, t)));
  }

  async addInvite(code: string, data: string, image: Uint8Array | null, expires: number, now: number) {
    await this.db
      .prepare('INSERT INTO invites (code, data, image, created, expires) VALUES (?, ?, ?, ?, ?)')
      .bind(code, data, image, now, expires)
      .run();
  }

  async getInvite(code: string, now: number) {
    return this.db.prepare('SELECT data FROM invites WHERE code = ? AND expires > ?').bind(code, now).first<{ data: string }>();
  }

  async inviteImage(code: string) {
    const row = await this.db.prepare('SELECT image FROM invites WHERE code = ?').bind(code).first<{ image: ArrayBuffer | Uint8Array | number[] | null }>();
    const img = row?.image;
    if (!img) return null;
    return img instanceof Uint8Array ? img : new Uint8Array(img as ArrayBuffer);
  }

  async tally(what: 'view' | 'get', now: number) {
    const day = new Date(now).toISOString().slice(0, 10);
    await this.db
      .prepare('INSERT INTO invite_tally (day, what, n) VALUES (?, ?, 1) ON CONFLICT (day, what) DO UPDATE SET n = n + 1')
      .bind(day, what)
      .run();
  }

  async tallies(sinceDay: string) {
    const rows = await this.db
      .prepare('SELECT what, SUM(n) AS n FROM invite_tally WHERE day >= ? GROUP BY what')
      .bind(sinceDay)
      .all<{ what: string; n: number }>();
    const out = { view: 0, get: 0 };
    for (const r of rows.results ?? []) if (r.what === 'view' || r.what === 'get') out[r.what] = r.n;
    return out;
  }

  async sweep(before: number, subsBefore: number, now = before) {
    const inv = await this.db.prepare('DELETE FROM invites WHERE expires < ?').bind(now).run();
    const r = await this.db.prepare('DELETE FROM reports WHERE at < ?').bind(before).run();
    await this.db.prepare('DELETE FROM limits WHERE at < ?').bind(before).run();
    const old = await this.db.prepare('SELECT token FROM subs WHERE updated < ?').bind(subsBefore).all<{ token: string }>();
    for (const { token } of old.results ?? []) await this.unsubscribe(token);
    return { reports: r.meta?.changes ?? 0, subs: old.results?.length ?? 0, invites: inv.meta?.changes ?? 0 };
  }
}

/** The cells' bounding box; across the date line, all longitudes. */
function bbox(cells: Cell[]) {
  const las = cells.map((c) => c.la);
  const los = cells.map((c) => c.lo);
  const loMin = Math.min(...los);
  const loMax = Math.max(...los);
  const wraps = loMax - loMin > 180;
  return { laMin: Math.min(...las), laMax: Math.max(...las), loMin: wraps ? -180 : loMin, loMax: wraps ? 180 : loMax };
}
