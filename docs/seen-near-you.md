# Seen near you: live aurora confirmed by other LookUp users

Status: **spec + on-phone rules done** (`lib/domain/aurora/seen_nearby.dart`,
`test/domain/seen_nearby_test.dart`); **decisions made** (bottom).
**Relay, reporting UI and alert not built yet.**

## Why

The Kp forecast is a poor guide at mid latitudes. In the big storms of May
and October 2024 most people found out from social media, an hour late.
What people want is "it's out *now*, near *me*". The only way to know that
is people who are looking. Every LookUp user who taps *I can see it* makes
the alert better for everyone near them. A forecast-only app can't copy
that.

It's also the clearest LookUp+ moment: live aurora is already Plus-only
(`SkyEventType.auroraNow`).

## What people see

1. **Reporting.** When aurora is possible tonight (the existing outlook), Tonight
   shows **I can see it** with a choice: *By eye* / *Only on my camera*.
   *Saw it!* on an aurora alert counts too. One tap, no typing, no account.
2. **The alert.** "Aurora being seen 60 km north of you" / "5 people in the
   last 20 minutes, 3 by eye. Get away from lights and face north, low in
   the sky. A phone camera shows colour your eyes may miss."
3. **On Tonight**, while it lasts, the same line replaces the aurora outlook card.

No map of reports and no counts by town. Just "near you", in words.

## The rules (on the phone, tested)

`crowdConfirms()` says yes only when **all** of these hold:

| Rule | Default | Why |
|---|---|---|
| Dark where you are | `isDark` | Same as every other alert |
| Not cloudy where you are | ≤ 60% | Never send people out into cloud |
| The model finds it plausible here | Kp ≥ needed − 1.5 | **Reports alone never alert.** The crowd can confirm what the model calls a little short, not overrule it |
| Different people | ≥ 4 | One person tapping twenty times counts once |
| From more than one place | ≥ 2 cells | No single crowd or prank |
| Close enough | ≤ 250 km | Your sky, not the region's |
| Not mostly nearer the pole than you | ≤ 1.5° geomagnetic | Aurora seen further north says little about yours |
| Recent | all within 20 min, one within 10 | It's still happening |

Change any of these only with a test in `test/domain/` (CLAUDE.md: a
false alarm is the one thing this app must never do).

## What leaves the phone

A report: `{cell, time, by eye|camera, reporter}`.

- **cell**: the centre of a half-degree square (~55 km), from `reportCell()`.
  Never a position.
- **reporter**: a random token per install, rotated every day, used only to
  count people once. No account, no device id, no IP kept by the relay.

Asking for reports sends the list of cells near you (`cellsNear()`, about 35
cells): again no position.

The privacy label changes from "Data not collected" to "Coarse location,
not linked to you" (App Store) and the matching Play data-safety entry.

## The relay (the server)

Small on purpose. Two endpoints, memory measured in megabytes.

- `POST /report`: rate limited per token (1 / 5 min) and per IP. Checked
  with **App Attest** (iOS) and **Play Integrity** (Android) so scripts
  can't flood it. Kept for 1 hour, then deleted.
- `GET /reports?cells=…`: the last 30 minutes for those cells.
- **Push:** when a cell's count crosses the threshold, the relay wakes
  phones that have opted in for the surrounding cells. The phone then runs
  `crowdConfirms()` with its own Kp and cloud data and decides whether to
  alert. The server never decides.

Hosting options: a Cloudflare Worker with Durable Objects, or a tiny Cloud
Run service. Either is a few dollars a month at launch scale.

## Decisions (made 2 Nov 2026)

1. **A server, for this one feature only.** The relay above, holding
   nothing but anonymous half-degree reports for an hour. Everything else
   stays on the phone. CLAUDE.md's "no backend" rule gets this one written
   exception (still to be added to CLAUDE.md).

2. **Waking a closed phone: each platform's own push.**
   - **iPhone:** the relay talks to Apple's push service (APNs) directly,
     over HTTP/2 with a token key. iOS needs no SDK for this.
   - **Android:** Firebase Cloud Messaging, data messages only, with
     Firebase Analytics left out and auto-init off until someone turns the
     feature on. This is the one third-party SDK; it also needs a CLAUDE.md
     exception.

   Why not "FCM with no SDK" as first suggested: an Android phone can't
   *receive* pushes without the FCM client library. Why not polling: at
   night an idle Android phone sits in Doze and defers background work for
   up to an hour, too late for an aurora.

   The push only *wakes* the phone. The phone runs `crowdConfirms()` with
   its own Kp and cloud data, so the server never decides who gets alerted.

3. **Reporting is free; the alert is LookUp+.** Anyone can tap *I can see
   it*, since more reporters make better alerts. The "being seen near you"
   alert is LookUp+, like aurora-now today.

4. **Switched on by geomagnetic latitude, not by country:** wherever the
   aurora is plausible at Kp 6 or less (`kpNeededAt() ≤ 6`, about 52°
   geomagnetic). That covers the UK and Ireland, Scandinavia, Iceland,
   Canada, Alaska and the northern US states. Tasmania and New Zealand's
   South Island need about Kp 6.7, so they come with the first widening.
   Elsewhere the *I can
   see it* row doesn't show and the forecast-only alert carries on
   unchanged. Widen it once the numbers below say it works.

Also before launch:

- **Privacy labels:** "Coarse location, not linked to you" on both stores.
- **Privacy policy:** a paragraph on the reports and the push token.
- **Opt-in:** it's off until people turn on *Seen near you*, at the first
  aurora outlook or in Settings. Turning it on asks for push and explains
  what's shared.

## Build order

1. Relay: the two endpoints, attestation, a 1-hour lifetime, rate limits.
2. `data/aurora_reports_client.dart`, and an *I can see it* row on
   Tonight's aurora card.
3. Push wake-up, then `crowdConfirms()`, then an `auroraNow` alert through
   `AlertPlanner` with its own stable id. A test shows it respects quiet
   hours' aurora override and the nightly cap.
4. A "Seen near you" line on Tonight.
5. Measure before widening: alerts sent per storm, and how many people
   answered *Did you see it?* with yes.
