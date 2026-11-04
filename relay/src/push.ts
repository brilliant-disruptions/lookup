// Waking phones: Apple's push service directly (iPhone) and Firebase Cloud
// Messaging HTTP v1 (Android). Both carry no message text and no data about
// anyone: just "check the sky". The phone decides whether to alert
// (crowdConfirms in lib/domain/aurora/seen_nearby.dart).

import type { Subscriber } from './store';

export type PushResult = 'ok' | 'gone' | 'failed';

export interface Pusher {
  send(sub: Subscriber): Promise<PushResult>;
}

const enc = new TextEncoder();

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === 'string' ? enc.encode(data) : new Uint8Array(data);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function pemBody(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

async function signJwt(header: object, claims: object, key: CryptoKey, alg: string | { name: string; hash?: string }): Promise<string> {
  const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const sig = await crypto.subtle.sign(alg, key, enc.encode(input));
  return `${input}.${b64url(sig)}`;
}

export type ApnsConfig = { keyP8: string; keyId: string; teamId: string; topic: string };

/** Silent background pushes straight to APNs (token auth, ES256). */
export class ApnsPusher implements Pusher {
  private jwt?: { token: string; at: number };
  private key?: CryptoKey;

  constructor(
    private cfg: ApnsConfig,
    private fetcher: typeof fetch = (input, init) => fetch(input, init), // a bare `fetch` held as a method throws "Illegal invocation" on Workers
    private now: () => number = Date.now,
  ) {}

  private async token(): Promise<string> {
    const t = this.now();
    // Apple wants a fresh token at most hourly and at least every 20 minutes.
    if (this.jwt && t - this.jwt.at < 40 * 60 * 1000) return this.jwt.token;
    this.key ??= await crypto.subtle.importKey('pkcs8', pemBody(this.cfg.keyP8), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
    const token = await signJwt(
      { alg: 'ES256', kid: this.cfg.keyId },
      { iss: this.cfg.teamId, iat: Math.floor(t / 1000) },
      this.key,
      { name: 'ECDSA', hash: 'SHA-256' },
    );
    this.jwt = { token, at: t };
    return token;
  }

  async send(sub: Subscriber): Promise<PushResult> {
    const host = sub.sandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    try {
      const res = await this.fetcher(`https://${host}/3/device/${encodeURIComponent(sub.token)}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${await this.token()}`,
          'apns-topic': this.cfg.topic,
          'apns-push-type': 'background',
          'apns-priority': '5',
          'apns-expiration': String(Math.floor(this.now() / 1000) + 600),
        },
        body: JSON.stringify({ aps: { 'content-available': 1 }, lookup: 'aurora-crowd' }),
      });
      if (res.ok) return 'ok';
      // Apple's answer, for the Worker's logs (never the token or the key).
      const reason = ((await res.json().catch(() => ({}))) as { reason?: string }).reason;
      // Only the status and Apple's reason: never echo configuration, which
      // may hold a mis-pasted key.
      console.warn(`apns ${res.status} ${reason ?? ''}`.trim());
      if (res.status === 410) return 'gone';
      if (res.status === 400 && (reason === 'BadDeviceToken' || reason === 'DeviceTokenNotForTopic')) return 'gone';
      return 'failed';
    } catch (e) {
      console.warn(`apns error: ${e instanceof Error ? e.message : 'unknown'}`);
      return 'failed';
    }
  }
}

export type FcmServiceAccount = { client_email: string; private_key: string; project_id: string };

/** High-priority data messages through FCM HTTP v1 (service account, RS256). */
export class FcmPusher implements Pusher {
  private access?: { token: string; until: number };
  private key?: CryptoKey;

  constructor(
    private sa: FcmServiceAccount,
    private fetcher: typeof fetch = (input, init) => fetch(input, init), // a bare `fetch` held as a method throws "Illegal invocation" on Workers
    private now: () => number = Date.now,
  ) {}

  private async accessToken(): Promise<string> {
    const t = this.now();
    if (this.access && t < this.access.until) return this.access.token;
    this.key ??= await crypto.subtle.importKey(
      'pkcs8',
      pemBody(this.sa.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const iat = Math.floor(t / 1000);
    const assertion = await signJwt(
      { alg: 'RS256', typ: 'JWT' },
      {
        iss: this.sa.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat,
        exp: iat + 3600,
      },
      this.key,
      { name: 'RSASSA-PKCS1-v1_5' },
    );
    const res = await this.fetcher('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${assertion}`,
    });
    if (!res.ok) throw new Error(`token ${res.status}`);
    const j = (await res.json()) as { access_token: string; expires_in?: number };
    this.access = { token: j.access_token, until: t + ((j.expires_in ?? 3600) - 300) * 1000 };
    return j.access_token;
  }

  async send(sub: Subscriber): Promise<PushResult> {
    try {
      const res = await this.fetcher(`https://fcm.googleapis.com/v1/projects/${this.sa.project_id}/messages:send`, {
        method: 'POST',
        headers: { authorization: `Bearer ${await this.accessToken()}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          message: { token: sub.token, data: { lookup: 'aurora-crowd' }, android: { priority: 'HIGH', ttl: '600s' } },
        }),
      });
      if (res.ok) return 'ok';
      if (res.status === 404) return 'gone'; // UNREGISTERED
      if (res.status === 400) {
        const body = (await res.json().catch(() => ({}))) as { error?: { status?: string } };
        if (body.error?.status === 'INVALID_ARGUMENT') return 'gone';
      }
      return 'failed';
    } catch {
      return 'failed';
    }
  }
}
