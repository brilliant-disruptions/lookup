import { describe, expect, it } from 'vitest';
import { ApnsPusher, FcmPusher } from '../src/push';

const pem = (der: ArrayBuffer, label: string) =>
  `-----BEGIN ${label}-----\n${Buffer.from(der).toString('base64').replace(/(.{64})/g, '$1\n')}\n-----END ${label}-----\n`;

const fromB64url = (s: string) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

type Call = { url: string; init: RequestInit };
const fakeFetch = (respond: (c: Call) => Response) => {
  const calls: Call[] = [];
  const f = (async (url: string, init: RequestInit) => {
    const c = { url: String(url), init };
    calls.push(c);
    return respond(c);
  }) as unknown as typeof fetch;
  return { f, calls };
};

describe('APNs', () => {
  it('sends a silent push with a valid ES256 token, and reports dead tokens', async () => {
    const pair = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify'])) as CryptoKeyPair;
    const p8 = pem((await crypto.subtle.exportKey('pkcs8', pair.privateKey)) as ArrayBuffer, 'PRIVATE KEY');
    let status = 200;
    const { f, calls } = fakeFetch(() => new Response(null, { status }));
    const p = new ApnsPusher({ keyP8: p8, keyId: 'KEY123', teamId: 'TEAM456', topic: 'com.brilliantdisruptions.lookup' }, f, () => 1_800_000_000_000);
    expect(await p.send({ token: 'abc', platform: 'apns', sandbox: false })).toBe('ok');
    const c = calls[0];
    expect(c.url).toBe('https://api.push.apple.com/3/device/abc');
    const h = c.init.headers as Record<string, string>;
    expect(h['apns-push-type']).toBe('background');
    expect(h['apns-topic']).toBe('com.brilliantdisruptions.lookup');
    expect(JSON.parse(String(c.init.body))).toEqual({ aps: { 'content-available': 1 }, lookup: 'aurora-crowd' });
    const [head, claims, sig] = h.authorization.replace('bearer ', '').split('.');
    expect(JSON.parse(fromB64url(head).toString())).toEqual({ alg: 'ES256', kid: 'KEY123' });
    expect(JSON.parse(fromB64url(claims).toString())).toEqual({ iss: 'TEAM456', iat: 1_800_000_000 });
    const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pair.publicKey, fromB64url(sig), new TextEncoder().encode(`${head}.${claims}`));
    expect(ok).toBe(true);
    expect(await p.send({ token: 'abc', platform: 'apns', sandbox: true })).toBe('ok');
    expect(calls[1].url).toContain('api.sandbox.push.apple.com');
    status = 410;
    expect(await p.send({ token: 'dead', platform: 'apns', sandbox: false })).toBe('gone');
  });
});

describe('FCM', () => {
  it('gets an access token with a valid RS256 assertion, sends a data message, reports dead tokens', async () => {
    const pair = (await crypto.subtle.generateKey(
      { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
      true,
      ['sign', 'verify'],
    )) as CryptoKeyPair;
    const key = pem((await crypto.subtle.exportKey('pkcs8', pair.privateKey)) as ArrayBuffer, 'PRIVATE KEY');
    let sendStatus = 200;
    const { f, calls } = fakeFetch((c) =>
      c.url.includes('oauth2')
        ? Response.json({ access_token: 'ya29.test', expires_in: 3600 })
        : new Response(sendStatus === 200 ? '{}' : '{"error":{"status":"NOT_FOUND"}}', { status: sendStatus }),
    );
    const p = new FcmPusher({ client_email: 'relay@lookup.iam.gserviceaccount.com', private_key: key, project_id: 'lookup-test' }, f, () => 1_800_000_000_000);
    expect(await p.send({ token: 'reg1', platform: 'fcm', sandbox: false })).toBe('ok');
    expect(await p.send({ token: 'reg2', platform: 'fcm', sandbox: false })).toBe('ok');
    expect(calls.filter((c) => c.url.includes('oauth2'))).toHaveLength(1); // token reused
    const assertion = new URLSearchParams(String(calls[0].init.body)).get('assertion')!;
    const [head, claims, sig] = assertion.split('.');
    expect(JSON.parse(fromB64url(claims).toString())).toMatchObject({
      iss: 'relay@lookup.iam.gserviceaccount.com',
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
    });
    expect(await crypto.subtle.verify('RSASSA-PKCS1-v1_5', pair.publicKey, fromB64url(sig), new TextEncoder().encode(`${head}.${claims}`))).toBe(true);
    const send = calls[1];
    expect(send.url).toBe('https://fcm.googleapis.com/v1/projects/lookup-test/messages:send');
    expect(JSON.parse(String(send.init.body))).toEqual({
      message: { token: 'reg1', data: { lookup: 'aurora-crowd' }, android: { priority: 'HIGH', ttl: '600s' } },
    });
    sendStatus = 404;
    expect(await p.send({ token: 'dead', platform: 'fcm', sandbox: false })).toBe('gone');
  });
});
