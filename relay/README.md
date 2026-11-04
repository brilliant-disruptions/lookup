# LookUp relay

The one server LookUp has. It does two things:

- **Seen near you:** anonymous "I can see the aurora" reports, kept for an
  hour, and wake-up pushes to phones nearby.
- **"Look up with me" links:** invites that unfurl into a card in Messages,
  with **Get reminders** (on to the App Store / Google Play) and **Add to Apple Wallet**. See
  [Invite links](#invite-links) below.

For Seen near you: Why and what it may hold:
[`docs/seen-near-you.md`](../docs/seen-near-you.md). The rules that decide
whether a phone *alerts* run on the phone
(`lib/domain/aurora/seen_nearby.dart`). The relay only stores and wakes.

A Cloudflare Worker with a D1 (SQLite) database. Pure TypeScript, no
dependencies at runtime.

| | |
|---|---|
| `src/relay.ts` | Routes, validation, rate limits, the wake-up rule |
| `src/store.ts` | The SQL (D1) |
| `src/push.ts` | APNs (token auth, ES256) and FCM HTTP v1 (service account, RS256) |
| `src/cells.ts` | Half-degree cells, same as the app's `reportCell` / `cellsNear` |
| `src/invite.ts` | Invite links: create, the page, the card picture |
| `src/ics.ts`, `src/pass.ts`, `src/zip.ts` | The calendar file; the Wallet pass (signed with node-forge, zipped) |
| `src/assets.ts` | Wallet icons and the default card, made by `tool/make_assets.py` |
| `schema.sql` | Tables |

## API

```
POST   /v1/report     {cell: {la, lo}, how: "eye"|"camera", reporter}      → 202
GET    /v1/reports?cells=la,lo;la,lo…                                       → {now, reports: [{la, lo, at, how, r}]}
POST   /v1/subscribe  {token, platform: "apns"|"fcm", sandbox?, cells: […]} → 204
DELETE /v1/subscribe  {token}                                               → 204
GET    /v1/health
```

- **Cells** must be half-degree centres (`55.75,-3.25`). Anything finer is
  refused, so a position can't be sent even by mistake.
- **Reporter tokens and IP addresses** are never stored. Each is replaced by
  an HMAC salted with `RELAY_SECRET` and today's date. The `r` that GET
  returns is that hash, so the app can count people once.
- **Rate limits:**
  - one report per person per 5 minutes;
  - 30 reports or subscriptions per network per hour;
  - 240 reads per network per hour.
- **Wake-up:** when a report makes it 4+ people from 2+ cells within
  250 km in the last 20 minutes, every phone subscribed to a cell in that
  area gets a silent push, at most once per 30 minutes. The push carries no
  text and no data: just `{lookup: "aurora-crowd"}`.
- **Cleanup:** every 10 minutes (cron), reports and limits older than an
  hour are deleted, along with subscriptions the app hasn't renewed in 30
  days. Tokens Apple or Google call dead are dropped at once.

## Invite links

When this build of the app knows the relay (`LOOKUP_RELAY_URL`), **Tell a
friend** / **Send the invite** sends a link instead of a bare picture:

```
POST /v1/invites  {type, title, start, end, look, face?, place?, clouds?, tz, image?}  → 201 {url, code}
GET  /n/:code              the page (Open Graph tags → the card in Messages, WhatsApp, Slack…)
GET  /n/:code/card.png     the app's "where to look" picture, or the default card
GET  /n/:code/get          Get reminders: redirects to the App Store or Google Play for this phone
GET  /n/:code/invite.ics   the event, with a reminder 10 minutes before (not linked from the page any more)
GET  /n/:code/pass.pkpass  an Apple Wallet event pass (only once set up, below)
```

- **What's stored:** what, when, where to look in words, the town name the
  sender's app shows, the forecast and the picture. It's kept until two
  days after the event, then the 10-minute sweep deletes it.
- **What's refused:** links of any kind, markup, unknown event kinds, past
  events and events more than 35 days away.
- **Rate limit:** 30 invites per network per hour.
- **Without the relay:** the app sends the poster and a calendar file, as
  it always could.

Optional settings (`npx wrangler secret put …`, or `[vars]` in `wrangler.toml`):

| Setting | What it does |
|---|---|
| `SITE_URL` | The address links use, e.g. `https://lookup.app` (a custom domain on the Worker). Defaults to the Worker's own `workers.dev` address |
| `APP_STORE_ID` | LookUp's numeric App Store id: where **Get reminders** goes on iPhone, and Safari's app banner |
| `PLAY_PACKAGE` | `com.brilliantdisruptions.lookup`, once the app is live on Google Play: where **Get reminders** goes on Android |

Until a store is set, **Get reminders** opens a short "LookUp is coming soon" page.

### Apple Wallet (optional)

1. In the Apple Developer portal, go to Identifiers → **+** → **Pass Type
   IDs** and create one, e.g. `pass.com.brilliantdisruptions.lookup.invite`.
2. Create its certificate (it asks for a CSR from Keychain Access), and
   download the `.cer`. Export the certificate *with its private key* from
   Keychain as `pass.p12`.
3. Download Apple's **WWDR G4** intermediate from
   https://www.apple.com/certificateauthority/.
4. Convert them to PEM:
   ```bash
   openssl pkcs12 -in pass.p12 -clcerts -nokeys -out pass-cert.pem -legacy
   openssl pkcs12 -in pass.p12 -nocerts -nodes -out pass-key.pem -legacy
   openssl x509 -inform der -in AppleWWDRCAG4.cer -out wwdr.pem
   ```
5. Set the secrets:
   ```bash
   npx wrangler secret put PASS_TYPE_ID     # pass.com.brilliantdisruptions.lookup.invite
   npx wrangler secret put PASS_TEAM_ID     # your 10-character team id
   npx wrangler secret put PASS_CERT_PEM < pass-cert.pem
   npx wrangler secret put PASS_KEY_PEM  < pass-key.pem
   npx wrangler secret put PASS_WWDR_PEM < wwdr.pem
   ```

The **Add to Apple Wallet** button appears on invite pages from then on. The
pass shows what and when on the front, the direction to face, the town and
the forecast. Where to look is on the back. It comes up on the lock screen
from 15 minutes before and voids itself an hour after. Apple's guidelines
want the official "Add to Apple Wallet" badge artwork on web pages: swap
it in for the plain button once you've downloaded it from Apple's Wallet
marketing page.

## Test

```bash
cd relay
npm install
npm test            # vitest: the real SQL on node:sqlite, real JWT signing
npm run typecheck
```

## Deploy (once)

**Deployed:** `https://lookup-relay.brilliant-disruptions.workers.dev`, on the
Brilliant Disruptions Cloudflare account (D1 `lookup-relay`; its id is in
`wrangler.toml`). Xcode Cloud builds point at it (`ios/ci_scripts/ci_post_clone.sh`).
To redeploy after changing `src/`: `npm test && npm run deploy`. From a Claude
cloud session, the Cloudflare token comes from the environment's network
secret for `api.cloudflare.com`; set `CLOUDFLARE_API_TOKEN` to any placeholder
and `CLOUDFLARE_ACCOUNT_ID` to the account id.

From scratch:

You need a Cloudflare account (the free plan is enough to start).

```bash
cd relay
npx wrangler login
npx wrangler d1 create lookup-relay        # paste the database_id into wrangler.toml
npm run db:init                            # creates the tables
npx wrangler secret put RELAY_SECRET       # any long random string, e.g. `openssl rand -hex 32`
npm run deploy                             # prints https://lookup-relay.<you>.workers.dev
```

Then build the app with the relay's address:

```bash
flutter build apk --release --dart-define=LOOKUP_RELAY_URL=https://lookup-relay.<you>.workers.dev
```

Without `LOOKUP_RELAY_URL`, *Seen near you* is hidden in the app, so
builds without it behave exactly as before.

### Pushes (optional, each platform on its own)

**iPhone (APNs):** in the Apple Developer portal, Keys → **+** → Apple Push
Notifications service. Download the `.p8` file once, then:

```bash
npx wrangler secret put APNS_KEY_P8      # paste the whole .p8 file, BEGIN/END lines included
npx wrangler secret put APNS_KEY_ID      # the key's 10-character id
npx wrangler secret put APNS_TEAM_ID     # your team id
npx wrangler secret put APNS_TOPIC       # com.brilliantdisruptions.lookup
```

**Android (FCM):**
1. Create a Firebase project.
2. Add the Android app `com.brilliantdisruptions.lookup`.
3. Under Project settings → Service accounts → **Generate new private key**:

```bash
npx wrangler secret put FCM_SERVICE_ACCOUNT   # paste the whole JSON file
```

Without these, reports and reads work and phones simply aren't woken. The
app still checks for reports whenever it refreshes.

## Costs

Under 100 people reporting at a time and a few thousand subscribers, this
fits Cloudflare's free tier. Worker requests, D1 reads and writes, and the
cron run are all well inside its daily limits.
