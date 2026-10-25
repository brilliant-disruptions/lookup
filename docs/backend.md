# LookUp backend (Supabase)

The app works with no backend. Turning it on adds four things:

| Function | What it does | Needs |
|---|---|---|
| `orbits` | One cached bundle (ISS, Tiangong, train-phase Starlinks, launches), refreshed every 2 hours for everyone. Phones download ~50 KB instead of 4.7 MB, and Celestrak gets one request every 2 hours instead of one per phone. | nothing |
| `aurora-watch` | Every 10 min: reads NOAA, applies the app's own aurora rules per device, pushes "Aurora now" once per 3-hour window. The only way that alert is timely on iOS. | `FCM_SERVICE_ACCOUNT` |
| `register-device` | Stores a push token with a rounded location (0.1°, ~10 km). No account. | nothing |
| `verify-receipt` | Confirms LookUp+ purchases with Apple / Google directly. | `APPLE_IAP_KEY`, `PLAY_SERVICE_ACCOUNT` |
| `track` | Anonymous, allow-listed product events for the spec's success metrics. View `metrics_daily`. | nothing |

Code: `supabase/functions/`, schema: `supabase/migrations/`, tests: `cd supabase && deno task test`.

## Why it isn't deployed yet

The Brilliant Disruptions Supabase org is on the free plan with two active
projects (woven-together, jarvis), the free-plan limit. Pick one:

- pause a project you're not using (CanvasRoute and claudewatch are already inactive), or
- upgrade the org (Pro, $25/mo, unlimited projects), or
- reuse an existing project (the tables don't collide with anything).

## Deploy (≈15 minutes)

```bash
npm i -g supabase
supabase login
cd supabase
supabase link --project-ref <ref>        # new or existing project
supabase db push                          # creates tables, view, prune function
supabase functions deploy orbits register-device aurora-watch track verify-receipt
```

Then in the SQL editor: store the service-role key in Vault and run
`supabase/cron.sql` (replace `<PROJECT_REF>`).

### Secrets

```bash
# Firebase project → Project settings → Service accounts → Generate key (JSON)
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat firebase-sa.json)"

# App Store Connect → Users and Access → Integrations → In-App Purchase key (.p8)
supabase secrets set APPLE_IAP_KEY='{"issuerId":"…","keyId":"…","bundleId":"com.brilliantdisruptions.lookup","privateKey":"-----BEGIN PRIVATE KEY-----\n…\n-----END PRIVATE KEY-----"}'

# Play Console → Setup → API access → service account with "View financial data"
supabase secrets set PLAY_SERVICE_ACCOUNT="$(cat play-sa.json)"
```

Functions without their secret answer `501` (receipts) or skip sending
(aurora-watch reports `wouldSend`), so you can deploy before every key exists.

### Point the app at it

Add to the Flutter build (Xcode Cloud: Environment variables → passed as
`--dart-define` in `ci_post_clone.sh`; locally on the command line):

```bash
flutter build ios \
  --dart-define=LOOKUP_SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=LOOKUP_SUPABASE_ANON_KEY=<anon key> \
  --dart-define=LOOKUP_FIREBASE_API_KEY=… \
  --dart-define=LOOKUP_FIREBASE_SENDER_ID=… \
  --dart-define=LOOKUP_FIREBASE_PROJECT_ID=… \
  --dart-define=LOOKUP_FIREBASE_APP_ID_IOS=… \
  --dart-define=LOOKUP_FIREBASE_APP_ID_ANDROID=… \
  --dart-define=LOOKUP_SENTRY_DSN=…
```

Each group is independent: omit Firebase and push stays off; omit Sentry and
crash reporting stays off.

### iOS push (one time)

1. Firebase console → add an iOS app with bundle id `com.brilliantdisruptions.lookup`; upload your APNs auth key (.p8) under Cloud Messaging.
2. Xcode → Runner → Signing & Capabilities → **+ Push Notifications** (adds the `aps-environment` entitlement). Commit the entitlements file.
3. Rebuild with the Firebase defines above.

Android needs only the Firebase defines.
