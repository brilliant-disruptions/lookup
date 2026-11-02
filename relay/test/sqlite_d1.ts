// Just enough of D1's API over node:sqlite to run SqlStore's real SQL in tests.
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

class Stmt {
  constructor(private db: DatabaseSync, private sql: string, private args: unknown[] = []) {}
  bind(...args: unknown[]) {
    // D1's limit: catch queries that would fail in production.
    if (args.length > 100) throw new Error(`D1 allows 100 bound parameters, got ${args.length}`);
    return new Stmt(this.db, this.sql, args);
  }
  private s() {
    return this.db.prepare(this.sql);
  }
  async run() {
    const r = this.s().run(...(this.args as never[]));
    return { success: true, meta: { changes: Number(r.changes) } };
  }
  async all<T>() {
    return { success: true, results: this.s().all(...(this.args as never[])) as T[] };
  }
  async first<T>() {
    return (this.s().get(...(this.args as never[])) ?? null) as T | null;
  }
}

export function sqliteD1(): D1Database {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));
  return {
    prepare: (sql: string) => new Stmt(db, sql),
    batch: async (stmts: Stmt[]) => {
      const out = [];
      for (const s of stmts) out.push(await s.run());
      return out;
    },
  } as unknown as D1Database;
}
