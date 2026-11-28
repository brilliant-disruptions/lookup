// LookUp's public pages: the privacy policy, support, and Terms (Apple's
// standard licence). The App Store listing and the app link here.
// Keep the policy in step with what the app actually sends
// (docs/seen-near-you.md › What leaves the phone).

export const SUPPORT_EMAIL = 'hello@brilliantdisruptions.com';
export const APPLE_EULA = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
const UPDATED = '27 November 2026';

const page = (title: string, body: string) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} · LookUp</title>
<style>
:root{color-scheme:dark}
body{margin:0;background:#04060B;color:#F4F6FA;font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,sans-serif}
main{max-width:680px;margin:0 auto;padding:48px 20px 80px}
h1{font-size:34px;line-height:1.15;margin:0 0 6px}
h2{font-size:19px;margin:32px 0 6px}
p,li{color:#C9CFDB}
.k{color:#C4F55E;font-weight:600;letter-spacing:.1em;text-transform:uppercase;font-size:12px}
.muted{color:#8A93A6;font-size:14px}
a{color:#5AA2FF}
code{background:#10141D;padding:1px 5px;border-radius:5px}
</style></head><body><main>${body}</main></body></html>`;

export function privacyPage(): string {
  return page('Privacy', `
<div class="k">LookUp</div>
<h1>Privacy</h1>
<p class="muted">Updated ${UPDATED}</p>
<p>LookUp works out your sky on your phone. There are no accounts, no ads, no analytics and no tracking, and no third-party SDKs. We don't sell or share anything about you.</p>

<h2>Your location</h2>
<p>LookUp asks for your location (or a town you pick) to work out what's over you. Your exact position stays on your phone. To fetch the weather, LookUp sends a rough version of it, rounded to about a kilometre, to our small server, with nothing that identifies you. Our server asks <a href="https://api.met.no/">MET Norway</a>, the Norwegian Meteorological Institute, for the forecast for that rough place; your phone never contacts MET Norway, so it never sees your IP address. Our server keeps each place's forecast for up to two days so it isn't asked twice, not linked to you or anyone. The same goes for other places you save, and for the darker spots LookUp suggests nearby. Searching for a town happens on your phone: what you type never leaves it.</p>

<h2>Photos</h2>
<p>Pictures you catch are saved to a LookUp album in your Photos. LookUp only reads its own album, and we recommend giving it Limited access. Each picture is saved with what it shows, when, the name of your place and a rough location (to about a kilometre), as any photo is; if you share a picture, those can go with it. Your pictures never leave your phone unless you share them.</p>

<h2>Sky data</h2>
<p>LookUp downloads satellite orbits (Celestrak), space weather (NOAA SWPC), rocket launches (The Space Devs) and a short list of rare sky events from our server. None of these requests carry your location.</p>

<h2>Seen near you, wake-ups and invites</h2>
<p>If you use these, LookUp's small server sees only:</p>
<ul>
<li><b>Aurora reports:</b> a half-degree square (about 55 km), the time and whether you saw it by eye or in the camera, with a random token that changes every day. Kept for an hour.</li>
<li><b>Wake-ups for aurora near you:</b> your phone's push address and the half-degree squares around you, never your position. Removed when you turn them off.</li>
<li><b>Invites you create:</b> what's in the invite (the sight, its time and your time zone, where to look and its picture, the cloud forecast, and the name of your place). Anyone with the link can see them. They're deleted two days after the event.</li>
</ul>
<p>The server doesn't keep IP addresses.</p>

<h2>Purchases</h2>
<p>LookUp+ is bought and managed through the App Store or Google Play. We never see your payment details.</p>

<h2>Children</h2>
<p>LookUp is for everyone and collects nothing that identifies anyone, including children.</p>

<h2>Emails to us</h2>
<p>If you email us (Settings › Help › Report a problem fills in your app version, your phone's system and whether you have LookUp+), we get your email address and what you write, and use them only to reply.</p>

<h2>Changes</h2>
<p>If LookUp ever starts collecting anything new, we'll update this page before that version comes out, say so in the app, and ask first for anything that needs your permission.</p>

<h2>Questions</h2>
<p>Write to <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>.</p>
<p class="muted">Brilliant Disruptions</p>`);
}

export function supportPage(): string {
  return page('Support', `
<div class="k">LookUp</div>
<h1>Help</h1>
<p>Something not right, or an idea? Write to <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>. In the app, Settings › Help › Report a problem fills in your app version for you.</p>

<h2>I didn't get an alert</h2>
<p>LookUp stays quiet when it's cloudy, when something is too low or too faint, and in your quiet hours. Check Settings › What to tell me about, and that notifications are on for LookUp in your phone's Settings.</p>

<h2>Pip points the wrong way</h2>
<p>Phone compasses drift. Move your phone in a slow figure of eight, away from metal and magnets, then try again.</p>

<h2>Photos</h2>
<p>Your catches go in a LookUp album in Photos. Choose <b>Limit Access</b> when asked: you don't need to pick any photos. On a new phone, Settings › Photos › Bring back my catches finds them again.</p>

<h2>LookUp+</h2>
<p>Manage or cancel in your App Store (or Google Play) subscriptions. Settings › LookUp+ › Restore purchases brings it back on a new phone.</p>

<p class="muted"><a href="/privacy">Privacy</a> · <a href="${APPLE_EULA}">Terms of Use</a></p>`);
}

/** The pages, or null for any other path. */
export function servePage(path: string): Response | null {
  const html = (s: string) =>
    new Response(s, { headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=3600' } });
  if (path === '/privacy' || path === '/privacy/') return html(privacyPage());
  if (path === '/support' || path === '/support/' || path === '/help') return html(supportPage());
  if (path === '/terms' || path === '/terms/') return Response.redirect(APPLE_EULA, 302);
  return null;
}
