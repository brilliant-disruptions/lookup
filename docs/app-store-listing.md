# App Store listing

Paste-ready copy for App Store Connect. Character limits in brackets.

## Name and subtitle

- **Name** [30]: `LookUp: Sky Alerts`
- **Subtitle** [30]: `ISS, aurora & Starlink alerts`

## Promotional text [170]

> The space station is overhead in 8 minutes. LookUp taps you just in time,
> tells you exactly where to look, and stays quiet the rest of the week.

## Description

> Step outside right now.
>
> LookUp watches the sky over you and taps you ten minutes before something
> worth seeing: the International Space Station gliding overhead, a fresh
> Starlink train, a chance of aurora, a meteor shower's peak, a lunar
> eclipse, a rocket launch you can see from home.
>
> It only taps you when it's dark enough and clear enough to see it. The rest
> of the time it stays quiet.
>
> WHERE TO LOOK, IN PLAIN WORDS
> "Face west-southwest. It climbs high in the sky, then fades out to the
> east." A countdown, a compass and a sky finder that guides your phone onto
> it, with the pass drawn over the live camera.
>
> MORE THAN THE SPACE STATION
> • Starlink trains in the weeks after a launch
> • Aurora tonight, and live "aurora now" alerts
> • Meteor showers, with the Moon taken into account
> • Lunar eclipses and Moon–planet pairings
> • Night and twilight rocket launches visible from where you are
> • The brightest satellites crossing tonight: Hubble, BlueBirds, big rocket stages
> • For photographers: the space station crossing the Sun or Moon, with how
>   far to drive to stand in the path
>
> ON YOUR TERMS
> • Buttons right on the alert: Find it, Remind me in 5 min, Saw it!
> • Quiet hours, a nightly limit and "only when it's clear"
> • Saved places: home, the cabin, next week's trip
> • Add any event to your calendar
> • Night-vision red mode to keep your eyes dark-adapted
>
> REMEMBER WHAT YOU SAW
> A sky log with badges, your own photos and a shareable "your sky year"
> card.
>
> PRIVATE BY DESIGN
> Orbits are computed on your phone. Your rough location is only used to
> fetch the cloud forecast. No account, no tracking.
>
> LookUp+ adds live aurora alerts, Starlink trains, Tiangong and launch
> alerts.

## Keywords [100]

`space station,satellite tracker,northern lights,meteor shower,eclipse,night sky,stargazing,astronomy`

(100 characters. Don't repeat words already in the name or subtitle; Apple
indexes those anyway.)

## Category

- **Primary:** Weather (it's a "what's happening above you right now" app)
- **Secondary:** Education

## Age rating

4+. No objectionable content; answer "None" throughout.

## Screenshots

`test/screenshots/goldens/appstore/` holds seven captioned 1320 × 2868
images (6.9" iPhone, which App Store Connect scales for smaller phones):

1. Step outside right now. *(Now)*
2. Know exactly where to look. *(Look sheet)*
3. See its path over your sky. *(camera view)*
4. Catch the station crossing the Moon. *(transit)*
5. Hubble and friends, tonight. *(satellites)*
6. Every good night in one list. *(Upcoming)*
7. Remember what you saw. *(Log)*

Regenerate after UI changes:

```
flutter test --update-goldens --run-skipped --tags screenshots test/screenshots
```

A 15–30 s **app preview video** has to be recorded on a real phone (screen
recording of *Preview an alert* → finder works well).

## Review notes (for Apple)

> Sky events depend on location and date, so there may be nothing to see
> during review. Settings → "Preview an alert" plays a complete pass in fast
> forward, including the real notification and its buttons. Location is used
> only on the device to predict passes and to fetch a cloud forecast.
> Camera, Photos and Calendar are only requested when the user taps the
> camera view, Add your photo, or Add to calendar.

## App Privacy

See [`mac-checklist.md`](mac-checklist.md#app-store-connect-bits).
