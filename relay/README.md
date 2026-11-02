# LookUp relay (Seen near you)

The one server LookUp has: anonymous "I can see the aurora" reports, kept
for an hour, and wake-up pushes to phones nearby. Why and what it may hold:
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

## Test

```bash
cd relay
npm install
npm test            # vitest: the real SQL on node:sqlite, real JWT signing
npm run typecheck
```

## Deploy (once)

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
