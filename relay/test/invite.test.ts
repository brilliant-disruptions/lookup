import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import forge from 'node-forge';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { defaultCard, passImages } from '../src/assets';
import { inviteIcs } from '../src/ics';
import { INVITE_RULES, senderWhen, type Invite } from '../src/invite';
import type { PassConfig } from '../src/pass';
import { handle, sweep, type Deps } from '../src/relay';
import { SqlStore } from '../src/store';
import { sqliteD1 } from './sqlite_d1';

const NOW = Date.UTC(2026, 10, 3, 1, 0); // 7 PM in Nashville (CST, UTC−6)
const START = new Date(NOW + 2 * 3600 * 1000 + 5 * 60 * 1000).toISOString(); // 9:05 PM local
const END = new Date(Date.parse(START) + 4 * 60 * 1000).toISOString();
const PNG = Buffer.from(defaultCard).toString('base64');

const good = {
  type: 'iss',
  title: 'ISS flyover',
  start: START,
  end: END,
  look: 'Face west-southwest. It appears there and climbs high in the sky before fading out toward the east.',
  face: 'west-southwest',
  place: 'Nashville',
  clouds: 8,
  tz: -360,
};

let now: number;
let store: SqlStore;
let deps: Deps;

function make(pass?: PassConfig, appStoreId?: string, playPackage?: string): Deps {
  return {
    store,
    secret: 's',
    pushers: {},
    now: () => now,
    later: () => {},
    invites: { site: 'https://lookup.test', appStoreId, playPackage, pass, defaultCard, passImages },
  };
}

beforeEach(() => {
  now = NOW;
  store = new SqlStore(sqliteD1());
  deps = make();
});

const post = (body: unknown, ip = '203.0.113.9') =>
  handle(new Request('https://relay.test/v1/invites', { method: 'POST', headers: { 'cf-connecting-ip': ip }, body: JSON.stringify(body) }), deps);
const get = (path: string) => handle(new Request(`https://relay.test${path}`), deps);
const create = async (extra: Record<string, unknown> = {}) => {
  const res = await post({ ...good, ...extra });
  expect(res.status).toBe(201);
  return (await res.json()) as { url: string; code: string };
};

describe('creating an invite', () => {
  it('returns a short link on the public address', async () => {
    const { url, code } = await create({ image: PNG });
    expect(code).toMatch(/^[a-z2-9]{10}$/);
    expect(url).toBe(`https://lookup.test/n/${code}`);
  });

  it('refuses anything odd: unknown kinds, markup, past or far-off times, bad pictures', async () => {
    for (const bad of [
      { type: 'party' },
      { title: '<script>alert(1)</script>' },
      { look: 'x'.repeat(701) },
      { place: 'Visit http://spam.example' },
      { look: 'Free prizes at www.example.com' },
      { title: 'Go to example.com/win' },
      { start: new Date(NOW - 3600e3).toISOString(), end: new Date(NOW - 3000e3).toISOString() },
      { start: new Date(NOW + 40 * 86400e3).toISOString(), end: new Date(NOW + 40 * 86400e3 + 60e3).toISOString() },
      { end: new Date(Date.parse(START) + 13 * 3600e3).toISOString() },
      { clouds: 140 },
      { tz: 2000 },
      { image: Buffer.from('not a png').toString('base64') },
    ]) {
      expect((await post({ ...good, ...bad })).status, JSON.stringify(bad)).toBe(400);
    }
  });

  it('a network can make a few dozen an hour, not a flood', async () => {
    let last = 0;
    for (let i = 0; i < 32; i++) last = (await post(good, '198.51.100.4')).status;
    expect(last).toBe(429);
  });
});

describe('the page', () => {
  it('unfurls in Messages: title with the sender\'s time, where to look, the card picture', async () => {
    const { code } = await create({ image: PNG });
    const res = await get(`/n/${code}`);
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toContain('text/html');
    const html = await res.text();
    expect(html).toContain('<meta property="og:title" content="ISS flyover · Tonight at 9:05 PM">');
    expect(html).toContain('og:description" content="Near Nashville. Face west-southwest.');
    expect(html).toContain('Clear skies forecast.');
    expect(html).toContain(`og:image" content="https://lookup.test/n/${code}/card.png"`);
    expect(html).toContain('name="robots" content="noindex"');
    expect(html).toContain('Get reminders');
    expect(html).toContain(`href="https://lookup.test/n/${code}/get"`);
    expect(html).not.toContain('Add to calendar');
    expect(html).not.toContain('invite.ics');
    expect(html).not.toContain('calendar.google.com');
    // No Wallet button or App Store banner until they're set up.
    expect(html).not.toContain('pass.pkpass');
    expect(html).not.toContain('apple-itunes-app');
  });

  it('offers Wallet and the App Store once they\'re set up', async () => {
    deps = make(await testPass(), '6739000000');
    const { code } = await create();
    const html = await (await get(`/n/${code}`)).text();
    expect(html).toContain('Add to Apple Wallet');
    expect(html).toContain('<meta name="apple-itunes-app" content="app-id=6739000000');
  });

  it('Get reminders: App Store on iPhone, Google Play on Android, "coming soon" until a store is set up', async () => {
    const { code } = await create();
    const ask = (ua: string) => handle(new Request(`https://relay.test/n/${code}/get`, { headers: { 'user-agent': ua } }), deps);
    const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)';
    const ANDROID = 'Mozilla/5.0 (Linux; Android 15; Pixel 9)';
    let res = await ask(IPHONE);
    expect(res.status).toBe(200);
    expect(await res.text()).toContain('LookUp is coming soon');
    expect(res.headers.get('cache-control')).toBe('no-store');

    deps = make(undefined, '6739000000');
    res = await ask(IPHONE);
    expect(res.status).toBe(302);
    expect(res.headers.get('location')).toBe('https://apps.apple.com/app/id6739000000');
    expect((await ask(ANDROID)).headers.get('location')).toBe('https://apps.apple.com/app/id6739000000'); // only store there is

    deps = make(undefined, '6739000000', 'com.brilliantdisruptions.lookup');
    expect((await ask(ANDROID)).headers.get('location')).toBe('https://play.google.com/store/apps/details?id=com.brilliantdisruptions.lookup');
    expect((await ask(IPHONE)).headers.get('location')).toBe('https://apps.apple.com/app/id6739000000');
    expect((await ask('Mozilla/5.0 (Macintosh)')).headers.get('location')).toBe('https://apps.apple.com/app/id6739000000');
  });

  it('after it\'s over: no countdown or buttons; after two days the link has gone', async () => {
    const { code } = await create();
    now = Date.parse(END) + 60e3;
    const html = await (await get(`/n/${code}`)).text();
    expect(html).toContain('That one’s over');
    expect(html).not.toContain('invite.ics"');
    now = Date.parse(END) + INVITE_RULES.keepAfterMs + 60e3;
    expect((await get(`/n/${code}`)).status).toBe(404);
    expect((await sweep(store, now)).invites).toBe(1);
  });

  it('the card is the sender\'s picture, or the default', async () => {
    const withPic = await create({ image: PNG });
    const res = await get(`/n/${withPic.code}/card.png`);
    expect(res.headers.get('content-type')).toBe('image/png');
    expect(Buffer.from(await res.arrayBuffer()).equals(Buffer.from(defaultCard))).toBe(true);
    const without = await create();
    expect((await get(`/n/${without.code}/card.png`)).status).toBe(200);
    expect((await get('/n/zzzzzzzzzz')).status).toBe(404);
    expect((await get('/n/../etc')).status).toBe(404);
  });
});

describe('the calendar file', () => {
  it('is one event with a 10-minute reminder, escaped and folded as calendars expect', async () => {
    const { code } = await create();
    const res = await get(`/n/${code}/invite.ics`);
    expect(res.headers.get('content-type')).toContain('text/calendar');
    const ics = await res.text();
    const lines = ics.split('\r\n');
    expect(lines[0]).toBe('BEGIN:VCALENDAR');
    expect(ics).toContain(`DTSTART:${START.replace(/[-:]/g, '').replace(/\.\d{3}/, '')}`);
    expect(ics).toContain('TRIGGER:-PT10M');
    expect(ics).toContain('SUMMARY:ISS flyover: look up');
    for (const l of lines) expect(new TextEncoder().encode(l).length).toBeLessThanOrEqual(75);
    // Commas escaped in text, lines folded with a leading space.
    expect(ics.replace(/\r\n /g, '')).toContain('Face west-southwest. It appears there and climbs high in the sky');
    expect(inviteIcs('x', { ...(good as Invite), look: 'A, B; C' }, 'u', NOW)).toContain('A\\, B\; C');
  });
});

describe('when', () => {
  it('reads like a person: tonight, tomorrow, or the day', () => {
    expect(senderWhen(START, -360, NOW)).toBe('Tonight at 9:05 PM');
    expect(senderWhen(new Date(NOW + 18 * 3600e3).toISOString(), -360, NOW)).toBe('Tomorrow at 1:00 PM');
    // Small hours count as tonight; from 4 AM it's tomorrow morning.
    expect(senderWhen(new Date(NOW + 6 * 3600e3).toISOString(), -360, NOW)).toBe('Tonight at 1:00 AM');
    expect(senderWhen(new Date(NOW + 9 * 3600e3).toISOString(), -360, NOW)).toBe('Tomorrow at 4:00 AM');
    expect(senderWhen(new Date(NOW + 4 * 86400e3).toISOString(), -360, NOW)).toBe('Fri 6 Nov at 7:00 PM');
  });
});

// A throwaway CA, WWDR stand-in and pass certificate, to check the pass the
// way Apple does: the signature over manifest.json, the manifest's hashes.
let passCfg: PassConfig | undefined;
async function testPass(): Promise<PassConfig> {
  if (passCfg) return passCfg;
  const mk = (subject: string, issuer: forge.pki.Certificate | null, issuerKey: forge.pki.rsa.PrivateKey | null) => {
    const keys = forge.pki.rsa.generateKeyPair(2048);
    const c = forge.pki.createCertificate();
    c.publicKey = keys.publicKey;
    c.serialNumber = String(Math.floor(Math.random() * 1e9));
    c.validity.notBefore = new Date(Date.now() - 86400e3);
    c.validity.notAfter = new Date(Date.now() + 365 * 86400e3);
    c.setSubject([{ name: 'commonName', value: subject }]);
    c.setIssuer(issuer ? issuer.subject.attributes : [{ name: 'commonName', value: subject }]);
    if (!issuer) c.setExtensions([{ name: 'basicConstraints', cA: true }]);
    c.sign(issuerKey ?? keys.privateKey, forge.md.sha256.create());
    return { c, k: keys.privateKey };
  };
  const wwdr = mk('Test WWDR', null, null);
  const pass = mk('Pass Type ID: pass.app.lookup.invite', wwdr.c, wwdr.k);
  passCfg = {
    passTypeId: 'pass.app.lookup.invite',
    teamId: 'TEAM123456',
    certPem: forge.pki.certificateToPem(pass.c),
    keyPem: forge.pki.privateKeyToPem(pass.k),
    wwdrPem: forge.pki.certificateToPem(wwdr.c),
  };
  return passCfg;
}

describe('the Wallet pass', () => {
  beforeAll(async () => {
    await testPass();
  }, 60_000);

  it('is a signed .pkpass: pass.json, icons, manifest of SHA-1s, detached PKCS#7 over the manifest', async () => {
    deps = make(await testPass());
    const { code } = await create();
    const res = await get(`/n/${code}/pass.pkpass`);
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toBe('application/vnd.apple.pkpass');
    const dir = mkdtempSync(join(tmpdir(), 'pkpass-'));
    const file = join(dir, 'p.pkpass');
    writeFileSync(file, Buffer.from(await res.arrayBuffer()));
    const listing = execFileSync('unzip', ['-l', file]).toString();
    for (const f of ['pass.json', 'icon.png', 'icon@2x.png', 'logo.png', 'manifest.json', 'signature']) expect(listing).toContain(f);
    execFileSync('unzip', ['-q', file, '-d', join(dir, 'x')]);
    const x = (f: string) => join(dir, 'x', f);
    const manifest = JSON.parse(execFileSync('cat', [x('manifest.json')]).toString()) as Record<string, string>;
    for (const [name, sha] of Object.entries(manifest)) {
      expect(execFileSync('openssl', ['sha1', '-r', x(name)]).toString().split(' ')[0]).toBe(sha);
    }
    writeFileSync(join(dir, 'ca.pem'), (await testPass()).wwdrPem);
    // Throws (and fails the test) unless the signature checks out.
    execFileSync('openssl', ['smime', '-verify', '-binary', '-inform', 'DER', '-in', x('signature'), '-content', x('manifest.json'), '-CAfile', join(dir, 'ca.pem'), '-purpose', 'any', '-out', '/dev/null'], { stdio: 'pipe' });
    const pass = JSON.parse(execFileSync('cat', [x('pass.json')]).toString());
    expect(pass).toMatchObject({
      passTypeIdentifier: 'pass.app.lookup.invite',
      teamIdentifier: 'TEAM123456',
      serialNumber: code,
      relevantDate: START,
      eventTicket: { primaryFields: [{ value: 'ISS flyover' }] },
    });
    expect(pass.eventTicket.secondaryFields.find((f: { key: string }) => f.key === 'face').value).toBe('west-southwest');
  }, 60_000);

  it('isn\'t offered without the certificate', async () => {
    const { code } = await create();
    expect((await get(`/n/${code}/pass.pkpass`)).status).toBe(404);
  });
});
