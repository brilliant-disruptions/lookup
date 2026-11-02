// Cloudflare Worker entry. Behaviour lives in relay.ts.

import { ApnsPusher, FcmPusher, type Pusher } from './push';
import { handle, sweep } from './relay';
import { SqlStore } from './store';
import type { Platform } from './store';

export interface Env {
  DB: D1Database;
  /** `wrangler secret put RELAY_SECRET`: any long random string. */
  RELAY_SECRET: string;
  /** Optional: iPhone pushes (`wrangler secret put …`). */
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_TOPIC?: string;
  /** Optional: Android pushes, the Firebase service-account JSON. */
  FCM_SERVICE_ACCOUNT?: string;
}

let cached: { env: Env; pushers: Partial<Record<Platform, Pusher>> } | undefined;

function pushersFor(env: Env): Partial<Record<Platform, Pusher>> {
  if (cached?.env === env) return cached.pushers;
  const pushers: Partial<Record<Platform, Pusher>> = {};
  if (env.APNS_KEY_P8 && env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_TOPIC) {
    pushers.apns = new ApnsPusher({ keyP8: env.APNS_KEY_P8, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC });
  }
  if (env.FCM_SERVICE_ACCOUNT) {
    try {
      pushers.fcm = new FcmPusher(JSON.parse(env.FCM_SERVICE_ACCOUNT));
    } catch {
      // Misconfigured: Android simply isn't woken.
    }
  }
  cached = { env, pushers };
  return pushers;
}

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (!env.RELAY_SECRET) return new Response('RELAY_SECRET not set', { status: 500 });
    return handle(req, {
      store: new SqlStore(env.DB),
      secret: env.RELAY_SECRET,
      pushers: pushersFor(env),
      now: Date.now,
      later: (p) => ctx.waitUntil(p),
    });
  },

  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(sweep(new SqlStore(env.DB), Date.now()));
  },
} satisfies ExportedHandler<Env>;
