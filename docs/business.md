# LookUp+: pricing, launch and measurement

How LookUp makes money, what to set up in the stores, what to measure from
day one, and when to market. The product side (what's free, what's
LookUp+) is in code at `lib/domain/plus/free_plan.dart`.

## The offer

**Free is the hook, and stays genuinely useful:** space station alerts
(cloud-checked), meteor showers, solar and lunar eclipses, planet pairings,
tonight's verdict, the sky map and finder, the log and share cards.

**LookUp+ is "never miss anything up there":**

| LookUp+ | Free |
|---|---|
| Every alert: live aurora (with wake-me), Starlink trains, Tiangong, rocket launches | Station, showers, eclipses, pairings |
| Where to go tonight: clearer, darker skies within a drive | Darker skies nudge only |
| Plan any of the next 14 nights | Tonight and the next two |
| As many saved places as you like | One (following the phone is always free) |
| Photo planning: the station crossing the Sun or Moon | — |

Where people meet it: the paywall opened on whatever they tapped (a Plus
alert, Where to go, a fourth night, a second place, a transit); after alerts
are switched on in onboarding when something Plus-only is coming; on You
caught it right after a sighting; the "you missed it" Week cards; and the
quiet "LookUp+ near you" card on Tonight (free only, "Not now" = a week).

## Prices (set in App Store Connect and Play Console)

Product ids are already in `PlusService`: `lookup_plus_yearly`,
`lookup_plus_monthly`, `lookup_plus_lifetime`.

| Product | Price (US) | Notes |
|---|---|---|
| Yearly | **$19.99–24.99** | The default and the one the paywall selects. 7-day free trial as an introductory offer, new subscribers only. Start at $24.99; test $19.99 later |
| Monthly | $3.99 | Mostly an anchor that makes yearly look cheap; expect it to churn in quiet ISS weeks |
| Lifetime | $59.99 | Non-consumable, ~2.5–3× yearly so it doesn't eat the subscription |

Benchmarks (Oct 2026): NASA Spot the Station is free; ISS Detector's extras
are a few dollars once; Aurora Forecast's alerts tier is ~$13/yr and its top
tier ~$25/yr; Sky Guide Pro is ~$9/mo, ~$60/yr.

Store setup:

- **One subscription group** ("LookUp+") holding yearly and monthly, so a
  person can move between them without double-paying.
- **Small Business Program** (Apple) and the 15% tier (Google) while under
  $1M a year: 15% instead of 30%.
- **Family Sharing** on: cheap goodwill, and a household shares a sky.
- Localised prices: use the stores' tier equivalents, then lower yearly in
  markets with lower purchasing power.

## Before launch: blockers for paid

1. **Time-sensitive notifications** on iOS (`docs/mac-checklist.md`):
   without the entitlement, Focus modes can silence the one thing people pay
   for.
2. **Receipt validation.** Entitlement is trusted from the store's purchase
   stream and cached on the phone (`plus_service.dart`). Fine for launch;
   before spending on ads, validate server-side. That means either a tiny
   serverless check (App Store Server API / Play Developer API) or a service
   like RevenueCat, both of which break today's "no backend, no third-party
   SDK" rule: decide deliberately.
3. **iOS widget and Live Activity** (Mac checklist): part of what LookUp+
   feels like on iPhone.

## Measure from day one

LookUp has no analytics by design. Without any, pricing and paywall changes
are guesses. Minimum, with no SDK:

- **App Store Connect → App Analytics:** impressions → page views → installs
  (the store page's conversion), by source; and **Subscriptions:** trial
  starts, trial → paid, renewal and refund rates, by plan.
- **Play Console → Statistics / Monetisation:** the same for Android.
- Weekly: installs, trial starts per install, trial → paid, month-2 and
  year-2 renewal. Healthy targets for a utility with a trial: 3–6% of
  installs start a trial, 40–60% of trials convert.

Worth deciding (it breaks the no-SDK rule): a privacy-first, aggregate-only
counter for four funnel steps (alerts on, first sighting, paywall seen,
trial started). Without it you can't tell *which* paywall moment converts.

## When to market: the sky does the PR

Sky apps spike when the sky is in the news. Have the store's promotional
text, a social post and a press note ready for each of these; set App Store
"In-App Events" for the big ones (they show on the store page and in search).

| When | What | Angle |
|---|---|---|
| Any G3+ geomagnetic storm | Aurora far south of normal | "LookUp+ tapped me the moment it started" — the live-aurora alert is the clearest LookUp+ demo there is |
| Dec 13–14 every year | Geminids | Free: "LookUp tells you when, and whether the Moon will spoil it" |
| Aug 12–13 every year | Perseids | Same |
| 6 Feb 2027 | Annular eclipse, South America | Ring of fire in Chile/Argentina |
| **2 Aug 2027** | **Total solar eclipse, Spain, North Africa, Egypt (6 min at Luxor)** | The biggest download moment in years. Free eclipse alert for exactly where you stand; Where to go (LookUp+) for the path of totality. Start the In-App Event and ASO ("solar eclipse") in spring 2027 |
| 26 Jan 2028 | Annular, Ecuador/Peru/Brazil, Spain at sunset | |
| 22 Jul 2028 | Total, Australia and New Zealand (Sydney ~3 min 49 s) | Southern-hemisphere push |
| Big crewed launches, ISS dockings | Station in the news | "See it with your own eyes tonight" |

Solar maximum has passed but aurora interest stays high into 2026–27: the
live-aurora alert is the strongest LookUp+ hook now, so lead with it.

## Rough maths (assumptions, not data)

Utility apps with a trial often convert 2–5% of installs to paid. At $20–25
a year, net ~$17–21 per subscriber after the 15% cut. 100,000 installs
≈ 2,000–5,000 subscribers ≈ $35k–100k a year. Installs, driven by sky
events and the share loops (share cards, Tell a friend, You weren't alone),
are the lever that matters most.
