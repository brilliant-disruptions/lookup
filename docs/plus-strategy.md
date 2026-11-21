# LookUp+: where it's offered, and why

Free is the hook and has to stay great: it earns the reviews and the word of
mouth. LookUp+ sells **never missing it**, **going further** and **taking it
home**, and it's offered at the moments someone already wants more, never in
the way of the sky.

## What's free, always

- Space station alerts (cloud-checked), meteor showers, lunar and solar
  eclipses (free on purpose: the glasses line), planet pairings, full Moon
  rising, novae.
- Pip's catch, the Log and badges, "Can I see it?", Home, Week, Explore
  tonight.
- Home-screen widgets and Live Activities: a widget is a billboard on their
  phone.
- The year card and share cards: they're the growth loop.
- The "LookUp" caption on every photo is part of free: each shared catch says
  where it came from.

## What's LookUp+

| What | Where it's asked for | Code |
| --- | --- | --- |
| Every other alert: Starlink trains, Tiangong, live aurora, comets, launches, occultations | Week rows ("Alert with LookUp+"), the soft asks below | `SkyEventType.plusOnly` |
| Where to go tonight | Its button | `PlusFeature.whereToGo` |
| Planning past 3 nights, more than 1 saved place | When they reach for the 4th night / 2nd place | `FreePlan.canPlanNight`, `canAddPlace` |
| ISS crossing the Sun or Moon | Its row | `PlusFeature.transits` |
| The Pro camera and timelapses | Its buttons; one line after a catch | `PlusFeature.camera` |
| The sky through history past a week either side of now; 4 of the 7 famous nights | Explore's Day steps and "Any night" (marked LookUp+). Not listed in the offer or the paywall's perks | `FreePlan.canVisit`, `canVisitFamous` |
| Turning the photo caption off | Settings → Caption on photos | `PlusFeature.noCaption` |

Reaching a limit someone chose to try (a later night, an old night, a second
place) is always answered with the paywall. That's a **limit ask**, not
pestering.

The full list as people read it lives in one place, `lib/ui/plus_perks.dart`:
the paywall shows it a line each, and the onboarding offer shows the alerts
they picked first and the rest as a grid. Change it there and both follow.

## Soft asks: one budget

A soft ask is LookUp offering LookUp+ without being asked. They share one
budget (`lib/domain/plus/nudges.dart`):

- never on LookUp+;
- **one per app session**: whichever showed first keeps the slot;
- **none in the first two days** after setting up, except a storm;
- **two "Not now"s** (or closing the offer without a trial) and soft asks stop
  for good. Limit asks still answer.

| Soft ask | When | Its own cadence |
| --- | --- | --- |
| **Storm tonight** (Home) | The aurora outlook could reach them and forecast Kp ≥ 5 (G1) | Time-critical: first on Home, allowed in the first two days |
| **You missed it** (Home) | A Plus-only sight went over them last night under a clear sky (≤ 20% cloud; unknown cloud never counts) | Once per sight, at most weekly |
| **LookUp+ near you** (Home) | Real Plus-only taps are coming this month | Every 3 days at most; "Not now" hides it a week |
| **A sight coming** (after a catch) | A dated Plus-only sight is coming | — |
| **Pro camera line** (after a catch) | Not the first catch, not a pass | Weekly; gone after two "Not now"s |

Home shows at most one (storm, then missed it, then near you). Never a pop-up,
never in the camera or during a live event.

## The one-time offer

At the end of onboarding, after the alerts question, once, never to LookUp+:
the real Plus-only taps coming over them this month (or what LookUp+ adds,
before those are known), "Try 7 days free", and "Not now" (which counts as a
decline). Most subscription apps start about half their trials on day one;
this is that moment, and it's the only time LookUp asks first.

## Trust

- The paywall leads with what brought them: the event, the feature, a storm,
  the sight they missed.
- Trial timeline: today every alert is on; **day 5 LookUp reminds them**
  (`trial_reminder.dart`, a quiet notification, not the sky chime); day 7 it
  renews; cancel before then and they're not charged.
- Starting LookUp+ re-plans alerts at once, so a trial started during a storm
  taps them for the aurora that night.

## Store settings (not in code)

- **Family Sharing:** turn it on for the subscriptions in App Store Connect
  (and Google Play's family library where offered). "One LookUp+ for the whole
  family" fits an app made for kids and parents.
- **Seasonal offers:** the free events bring installs. Time promotional
  offers / offer codes to them: Perseids (12–13 Aug), Geminids (13–14 Dec),
  lunar eclipses, and aurora season around the equinoxes.

## What we can't see

With no analytics and no backend, there's no telling which ask converts.
App Store Connect and Play Console show trials and conversions overall, not
by trigger. Counting anonymous "paywall opened from X" tallies through the
relay would answer it, but that's a policy decision: everything else stays on
the phone.
