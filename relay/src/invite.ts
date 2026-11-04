// "Look up with me" links. The app posts what's happening (what, when,
// where to look, the town it's near, the forecast and the "where to look"
// picture) and gets back a short link. The link is the invite:
//
//   /n/:code             the page: a countdown, where to look, Add to calendar,
//                        Add to Apple Wallet, Get LookUp. Its Open Graph tags
//                        make Messages (and WhatsApp, Slack …) show a big card.
//   /n/:code/card.png    the card's picture (the app's own "where to look" art)
//   /n/:code/invite.ics  the calendar event, with a reminder 10 minutes before
//   /n/:code/pass.pkpass the Wallet pass (when the pass certificate is set up)
//
// Kept until two days after it's over, then swept. No accounts, no
// positions: the town is whatever name the sender's app shows.

import { cloudWords, googleCalendarUrl, inviteIcs } from './ics';
import { buildPass, type PassConfig, type PassImages } from './pass';
import type { Store } from './store';

export type Invite = {
  type: string;
  title: string;
  start: string;
  end: string;
  look: string;
  /** "west-southwest": the short "face" for the Wallet pass. */
  face?: string;
  place?: string;
  clouds?: number;
  /** The sender's UTC offset, minutes, for "Tonight at 9:05 PM" in previews. */
  tz: number;
};

export type InviteDeps = {
  store: Store;
  now: () => number;
  /** Public address, e.g. https://lookup.app; otherwise the request's own. */
  site?: string;
  appStoreId?: string;
  pass?: PassConfig;
  defaultCard: Uint8Array;
  passImages: PassImages;
};

export const INVITE_RULES = {
  maxImage: 700_000,
  keepAfterMs: 2 * 24 * 3600 * 1000,
  maxAheadMs: 35 * 24 * 3600 * 1000,
  maxLengthMs: 12 * 3600 * 1000,
};

const TYPES = new Set([
  'iss', 'tiangong', 'starlinkTrain', 'auroraNow', 'auroraOutlook', 'meteorShower', 'lunarEclipse', 'solarEclipse',
  'planetPairing', 'rocketLaunch', 'issTransit', 'planetHighlight', 'skyObject', 'satellitePass',
]);
const TEXT = /^[\p{L}\p{N} .,;:'’()°%\-–—!?&/+]+$/u;
/** No links of any kind: this page only ever says what's up there. */
const LINKISH = /:\/\/|www\.|\b[a-z0-9-]+\.(com|net|org|io|app|co|ly|me|xyz|info|biz|link|click|us|uk|ru|cn)\b/i;
const ok = (s: unknown, max: number): s is string =>
  typeof s === 'string' && s.length > 0 && s.length <= max && TEXT.test(s) && !LINKISH.test(s);

/** Checks what the app sent; null when anything is off. */
export function parseInvite(b: Record<string, unknown>, now: number): Invite | null {
  if (typeof b.type !== 'string' || !TYPES.has(b.type)) return null;
  if (!ok(b.title, 60) || !ok(b.look, 700)) return null;
  if (b.face !== undefined && !ok(b.face, 40)) return null;
  if (b.place !== undefined && !ok(b.place, 48)) return null;
  if (b.clouds !== undefined && (typeof b.clouds !== 'number' || !Number.isInteger(b.clouds) || b.clouds < 0 || b.clouds > 100)) return null;
  if (typeof b.tz !== 'number' || !Number.isInteger(b.tz) || Math.abs(b.tz) > 14 * 60) return null;
  const start = typeof b.start === 'string' ? Date.parse(b.start) : NaN;
  const end = typeof b.end === 'string' ? Date.parse(b.end) : NaN;
  if (!isFinite(start) || !isFinite(end) || end < start || end - start > INVITE_RULES.maxLengthMs) return null;
  if (end < now || start > now + INVITE_RULES.maxAheadMs) return null;
  return {
    type: b.type,
    title: b.title,
    start: new Date(start).toISOString(),
    end: new Date(end).toISOString(),
    look: b.look,
    ...(b.face ? { face: b.face as string } : {}),
    ...(b.place ? { place: b.place as string } : {}),
    ...(b.clouds !== undefined ? { clouds: b.clouds as number } : {}),
    tz: b.tz,
  };
}

function pngFromBase64(s: unknown): Uint8Array | null | 'bad' {
  if (s === undefined || s === null) return null;
  if (typeof s !== 'string' || s.length > INVITE_RULES.maxImage * 1.4) return 'bad';
  let bin: string;
  try {
    bin = atob(s);
  } catch {
    return 'bad';
  }
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  const sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length > INVITE_RULES.maxImage || sig.some((b, i) => bytes[i] !== b)) return 'bad';
  return bytes;
}

const ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789'; // no l, o, 0, 1
function newCode(): string {
  const r = crypto.getRandomValues(new Uint8Array(10));
  return [...r].map((b) => ALPHABET[b % ALPHABET.length]).join('');
}

/** POST /v1/invites (body already parsed and rate-limited by the caller). */
export async function createInvite(b: Record<string, unknown>, base: string, deps: InviteDeps): Promise<Response> {
  const now = deps.now();
  const inv = parseInvite(b, now);
  const image = pngFromBase64(b.image);
  if (!inv || image === 'bad') return Response.json({ error: 'invite' }, { status: 400 });
  const code = newCode();
  await deps.store.addInvite(code, JSON.stringify(inv), image, Date.parse(inv.end) + INVITE_RULES.keepAfterMs, now);
  return Response.json({ url: `${base}/n/${code}`, code }, { status: 201 });
}

const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/** "Tonight at 9:05 PM", "Tomorrow at 5:41 AM", "Sat 7 Nov at 6:12 PM", in the sender's time. */
export function senderWhen(startIso: string, tz: number, now: number): string {
  const local = new Date(Date.parse(startIso) + tz * 60_000);
  const today = new Date(now + tz * 60_000);
  const h = local.getUTCHours(), m = local.getUTCMinutes();
  const time = `${h % 12 === 0 ? 12 : h % 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
  const day = (d: Date) => Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  const diff = Math.round((day(local) - day(today)) / 86_400_000);
  const evening = h >= 17 || h < 4;
  const word =
    diff === 0
      ? evening ? 'Tonight' : 'Today'
      : diff === 1 && h < 4
        ? 'Tonight'
        : diff === 1
          ? 'Tomorrow'
          : `${['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][local.getUTCDay()]} ${local.getUTCDate()} ${
              ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][local.getUTCMonth()]
            }`;
  return `${word} at ${time}`;
}

const TINT: Record<string, string> = {
  iss: '#5AA2FF', tiangong: '#5AA2FF', satellitePass: '#5AA2FF', starlinkTrain: '#A78BFA', auroraNow: '#3DD68C',
  auroraOutlook: '#3DD68C', meteorShower: '#FF9F5A', lunarEclipse: '#FF7A6B', solarEclipse: '#FF7A6B',
  rocketLaunch: '#FF7A6B', planetPairing: '#F5C76B', planetHighlight: '#F5C76B', skyObject: '#F5C76B', issTransit: '#52D1E8',
};

export function invitePage(code: string, inv: Invite, base: string, deps: Pick<InviteDeps, 'now' | 'appStoreId' | 'pass'>): string {
  const now = deps.now();
  const url = `${base}/n/${code}`;
  const when = senderWhen(inv.start, inv.tz, now);
  const title = `${inv.title} · ${when}`;
  const forecast = cloudWords(inv.clouds);
  const description = [inv.place ? `Near ${inv.place}.` : '', inv.look, forecast].filter(Boolean).join(' ');
  const over = Date.parse(inv.end) < now;
  const tint = TINT[inv.type] ?? '#5AA2FF';
  const store = deps.appStoreId ? `https://apps.apple.com/app/id${deps.appStoreId}` : null;
  const data = JSON.stringify({ start: inv.start, end: inv.end }).replace(/</g, '\\u003c');
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#04060B">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta property="og:site_name" content="LookUp">
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(url)}">
<meta property="og:image" content="${esc(`${url}/card.png`)}">
<meta property="og:image:width" content="1024">
<meta property="og:image:height" content="512">
<meta name="twitter:card" content="summary_large_image">
${deps.appStoreId ? `<meta name="apple-itunes-app" content="app-id=${esc(deps.appStoreId)}, app-argument=${esc(url)}">` : ''}
<style>
  :root { color-scheme: dark; --tint: ${tint}; --firefly: #C4F55E; --grey: #A0A8B8; --dim: #687083; --line: rgba(255,255,255,.09); }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; background: radial-gradient(120% 70% at 50% 0%, #0B1328 0%, #04060B 70%) #04060B;
    color: #F4F6FA; font: 16px/1.45 -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI", Roboto, sans-serif; -webkit-font-smoothing: antialiased; }
  main { max-width: 460px; margin: 0 auto; padding: max(28px, env(safe-area-inset-top)) 18px 40px; }
  .card { width: 100%; aspect-ratio: 2 / 1; border-radius: 22px; overflow: hidden; border: 1px solid var(--line); background: #0B1328; }
  .card img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .kicker { margin: 22px 0 4px; color: var(--tint); font-weight: 650; font-size: 14px; letter-spacing: -.01em; }
  h1 { margin: 0; font-size: 32px; line-height: 1.08; letter-spacing: -.025em; font-weight: 750; }
  .when { margin: 8px 0 0; font-size: 18px; color: #F4F6FA; font-variant-numeric: tabular-nums; }
  .count { margin: 18px 0 0; font-size: 44px; font-weight: 700; letter-spacing: -.03em; font-variant-numeric: tabular-nums; }
  .count small { font-size: 18px; color: var(--grey); font-weight: 600; margin-left: 2px; }
  .look { margin: 18px 0 0; padding: 16px 18px; border-radius: 18px; background: rgba(255,255,255,.06); border: 1px solid var(--line); }
  .look p { margin: 0; }
  .look .sky { margin-top: 8px; color: var(--grey); font-size: 14.5px; }
  .buttons { display: grid; gap: 10px; margin-top: 22px; }
  a.button { display: block; text-align: center; text-decoration: none; padding: 15px 18px; border-radius: 999px; font-weight: 650; font-size: 16.5px; }
  a.primary { background: #F4F6FA; color: #04060B; }
  a.secondary { background: rgba(255,255,255,.08); color: #F4F6FA; border: 1px solid var(--line); }
  a.link { text-align: center; color: var(--grey); font-size: 14.5px; padding: 4px; }
  a.wallet { background: #000; color: #fff; border: 1px solid rgba(255,255,255,.28); }
  .foot { margin-top: 26px; color: var(--dim); font-size: 13px; text-align: center; }
  .foot b { color: var(--grey); }
</style>
</head>
<body>
<main>
  <div class="card"><img src="${esc(`${url}/card.png`)}" alt="Where to look: ${esc(inv.look)}"></div>
  <p class="kicker">${over ? 'That one’s over' : 'Look up with me'}</p>
  <h1>${esc(inv.title)}</h1>
  <p class="when"><span id="when">${esc(when)}</span>${inv.place ? ` · near ${esc(inv.place)}` : ''}</p>
  ${over ? '' : '<p class="count" id="count" aria-live="polite"></p>'}
  <div class="look">
    <p>${esc(inv.look)}</p>
    ${forecast ? `<p class="sky">${esc(forecast)}</p>` : ''}
  </div>
  <div class="buttons">
    ${over ? '' : `<a class="button primary" href="${esc(`${url}/invite.ics`)}">Add to calendar</a>`}
    ${over ? '' : `<a class="link" href="${esc(googleCalendarUrl(inv, url))}" target="_blank" rel="noopener">Use Google Calendar instead</a>`}
    ${over || !deps.pass ? '' : `<a class="button wallet" href="${esc(`${url}/pass.pkpass`)}">Add to Apple Wallet</a>`}
    ${store ? `<a class="button secondary" href="${esc(store)}">Get LookUp: it taps you when it’s overhead</a>` : ''}
  </div>
  <p class="foot">Sent with <b>LookUp</b>. Times show in your own time zone.</p>
</main>
<script>
(function () {
  var d = ${data};
  var start = new Date(d.start), end = new Date(d.end);
  try {
    // In the reader's own time zone (the preview shows the sender's).
    var t = start.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    var day = start.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric' });
    document.getElementById('when').textContent = day + ' at ' + t;
  } catch (e) {}
  var c = document.getElementById('count');
  if (!c) return;
  function tick() {
    var now = new Date();
    var ms = start - now;
    if (now >= end) { c.textContent = 'That one’s over'; return; }
    if (ms <= 0) { c.innerHTML = 'Happening now <small>look up</small>'; return; }
    var s = Math.floor(ms / 1000), d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60), ss = s % 60;
    c.innerHTML = d > 0 ? 'in ' + d + '<small>d</small> ' + h + '<small>h</small>'
      : h > 0 ? 'in ' + h + '<small>h</small> ' + m + '<small>m</small>'
      : 'in ' + m + '<small>m</small> ' + String(ss).padStart(2, '0') + '<small>s</small>';
  }
  tick(); setInterval(tick, 1000);
})();
</script>
</body>
</html>`;
}

const notFound = (base: string, appStoreId?: string) =>
  new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex"><title>LookUp</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#04060B;color:#F4F6FA;font:16px/1.45 -apple-system,BlinkMacSystemFont,sans-serif;text-align:center;padding:24px}a{color:#5AA2FF}</style></head>
<body><div><h1 style="font-size:26px;margin:0 0 8px">This invite has gone</h1><p style="color:#A0A8B8;margin:0">It was for something that’s already over.</p>${
      appStoreId ? `<p><a href="https://apps.apple.com/app/id${esc(appStoreId)}">Get LookUp</a> to hear about the next one.</p>` : ''
    }</div></body></html>`,
    { status: 404, headers: { 'content-type': 'text/html; charset=utf-8' } },
  );

/** GET /n/:code[/card.png|/invite.ics|/pass.pkpass] */
export async function serveInvite(path: string, base: string, deps: InviteDeps): Promise<Response> {
  const m = /^\/n\/([a-z2-9]{10})(?:\/(card\.png|invite\.ics|pass\.pkpass))?\/?$/.exec(path);
  if (!m) return notFound(base, deps.appStoreId);
  const [, code, part] = m;
  const row = await deps.store.getInvite(code, deps.now());
  if (!row) return notFound(base, deps.appStoreId);
  const inv = JSON.parse(row.data) as Invite;
  const url = `${base}/n/${code}`;
  const cache = { 'cache-control': 'public, max-age=300' };
  switch (part) {
    case 'card.png': {
      const img = (await deps.store.inviteImage(code)) ?? deps.defaultCard;
      return new Response(img, { headers: { 'content-type': 'image/png', ...cache } });
    }
    case 'invite.ics':
      return new Response(inviteIcs(code, inv, url, deps.now()), {
        headers: { 'content-type': 'text/calendar; charset=utf-8', 'content-disposition': `inline; filename="lookup-${code}.ics"`, ...cache },
      });
    case 'pass.pkpass': {
      if (!deps.pass) return new Response('Wallet passes aren’t set up', { status: 404 });
      const pkpass = await buildPass(deps.pass, code, inv, url, deps.passImages);
      return new Response(pkpass, {
        headers: { 'content-type': 'application/vnd.apple.pkpass', 'content-disposition': `attachment; filename="lookup-${code}.pkpass"` },
      });
    }
    default:
      return new Response(invitePage(code, inv, base, deps), { headers: { 'content-type': 'text/html; charset=utf-8', ...cache } });
  }
}
