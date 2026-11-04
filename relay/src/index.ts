// Cloudflare Worker entry. Behaviour lives in relay.ts.

import { defaultCard, passImages } from './assets';
import type { PassConfig } from './pass';
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
  /** Optional: the public address for invite links (default: this Worker's own). */
  SITE_URL?: string;
  /** Optional: LookUp's numeric App Store id, for "Get LookUp" and Safari's banner. */
  APP_STORE_ID?: string;
  /** Optional: Apple Wallet passes for invites (README.md › Wallet). */
  PASS_TYPE_ID?: string;
  PASS_TEAM_ID?: string;
  PASS_CERT_PEM?: string;
  PASS_KEY_PEM?: string;
  PASS_KEY_PASSWORD?: string;
  PASS_WWDR_PEM?: string;
}

function passConfig(env: Env): PassConfig | undefined {
  if (!env.PASS_TYPE_ID || !env.PASS_TEAM_ID || !env.PASS_CERT_PEM || !env.PASS_KEY_PEM || !env.PASS_WWDR_PEM) return undefined;
  return {
    passTypeId: env.PASS_TYPE_ID,
    teamId: env.PASS_TEAM_ID,
    certPem: env.PASS_CERT_PEM,
    keyPem: env.PASS_KEY_PEM,
    keyPassword: env.PASS_KEY_PASSWORD,
    wwdrPem: env.PASS_WWDR_PEM,
  };
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
      invites: {
        site: env.SITE_URL?.replace(/\/$/, ''),
        appStoreId: env.APP_STORE_ID,
        pass: passConfig(env),
        defaultCard,
        passImages,
      },
    });
  },

  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(sweep(new SqlStore(env.DB), Date.now()));
  },
} satisfies ExportedHandler<Env>;
