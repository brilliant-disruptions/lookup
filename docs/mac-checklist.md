# Mac checklist (one sitting, ~30 minutes)

Everything else is in the repo and builds on Xcode Cloud as is. These steps
need Xcode because they change signing/capabilities or add native targets
that can't be compiled or verified on Linux.

Start with `git pull`, then open **`ios/Runner.xcworkspace`** (not the
`.xcodeproj`).

## 1. Alerts that break through Focus (most important)

LookUp marks every alert *time-sensitive*, but iOS only honours that when the
app has the capability. Without it, someone in Sleep or Do Not Disturb
misses the space station.

1. Select the **Runner** target → **Signing & Capabilities**.
2. **+ Capability** → **Time Sensitive Notifications**.

3. **+ Capability** → **Push Notifications** (Seen near you wake-ups:
   the relay nudges the phone when people nearby see the aurora; see
   `lib/services/push_service.dart`). Push is already ticked on the App ID
   and the APNs key is on the relay. Leave *Broadcast* off. The
   *Remote notifications* background mode is already in `Info.plist`.

Xcode creates `ios/Runner/Runner.entitlements` (with `aps-environment` and
the time-sensitive key) and registers the capabilities with your App ID
(automatic signing). Commit that file and the `project.pbxproj` change.
Until then, wake-ups quietly stay off: the app asks iOS for a push
address, iOS declines, and nothing else changes.

## 2. Home-screen widget and Live Activity

1. Runner target → **+ Capability** → **App Groups** → add
   `group.com.brilliantdisruptions.lookup`.
2. Follow [`ios-widgets.md`](ios-widgets.md) to add the widget extension
   (sources are already in `ios/LookUpWidgets/`). Give the extension the same
   App Group.
3. **Pip on the Lock Screen (not built yet: needs Xcode to compile).** The
   Live Activity and widgets should carry the same firefly as the app and the
   alerts: glow `#C4F55E`, core `#F4FFD9`, drawn as in `paintFirefly`
   (`lib/ui/kit/firefly_mark.dart`): a soft glow, a smaller bright ring, and a
   core. In SwiftUI, three stacked `Circle()`s with `.blur` (radius 16/5/0 at
   scale 1) in `ios/LookUpWidgets/`. The Live Activity shows Pip blinking
   (`.symbolEffect`-style opacity pulse, 2.5 Hz) in the last minute before
   it rises, and still once it's up. Keep the text factual ("ISS in 2 min ·
   look west-southwest"); Pip is the only flourish. Keep both
   `LookUpActivityAttributes` structs identical if a field is added.

## 3. "Hey Siri, when's the next pass in LookUp?"

1. Drag `ios/Runner/LookUpIntents.swift` into the **Runner** group in the
   project navigator. Tick **Runner** under *Target Membership*; leave
   *Copy items if needed* unticked (it's already in place).
2. Build (⌘B). No extra capability is needed for App Shortcuts.

The phrases appear in the Shortcuts app after the first launch. Siri answers
from what the app last worked out, so open LookUp once after installing.

## 4. Check on a real phone

Run on a device (⌘R) and try:

- **Alert buttons.** Settings → *Preview an alert*. Long-press the
  notification: *Find it*, *Remind me in 5 min*, *Saw it!*. Lock the phone
  and press *Saw it!*: the Log tab should show it next time you open the app.
- **Chime.** The preview alert should play the two-note LookUp chime, not
  the default tri-tone (`lookup_chime.wav` is already in *Copy Bundle
  Resources*).
- **Camera view.** Open any event → *Find it in the sky* → camera icon.
  Allow camera access; the path should sit roughly where the satellite will
  be (compasses are good to 5–10°; wave the phone in a figure-8 if it's off).
- **Add to calendar, photos, Places search, Directions** on a transit.
- **Look up now:** open the app on Tonight within two minutes of a real pass. The takeover
  should open once; turning the phone should swing the arrow and the words; at rise it
  buzzes and opens the finder. (Android: the heads-up should tick down on the lock screen.)
- **Tell a friend:** on a real heads-up, press *Tell a friend*: the app should open on the
  invite poster with "…in 10 minutes" in the text.
- **Red after sunset:** open the app after sunset: every screen should be red, with a one-line
  note; Settings › Night vision off brings the colours back; by day it's never red.
- **Alert picture:** Settings → *Preview an alert*. Long-press the
  notification (iOS) or expand it (Android): the "where to look" picture should
  show the path and "appears here". If it's missing, the alert text must still
  arrive (that fallback is tested, the picture itself only on a device).

- **LookUp+ comes and goes with the subscription** (sandbox Apple ID, or a
  StoreKit configuration file in Xcode; a sandbox month lasts five minutes).
  None of this could be run on Linux, only against a stand-in for the store:
  - Buy monthly: the paywall closes and Plus-only alerts appear.
  - Let it lapse (cancel in Settings › App Store › Sandbox Account, wait for
    the period to end), then relaunch: LookUp+ should still be on. A few
    days later (`PlusGrant.doubt`; shorten it for the test) it should be
    off, and *Restore purchases* should bring nothing back.
  - Resubscribe: back on at the next launch, with no tap on Restore.
  - Refund (Xcode › Debug › StoreKit › Manage Transactions › Refund) with
    the app open: off within seconds.
  - Launching must never show an Apple ID sign-in sheet.
  - Leave the phone alone overnight with a renewing sandbox subscription and
    check the Plus-only alerts are still planned in the morning (the
    background refresh reads the renewal).

## 5. Commit and push

```
git add ios/
git commit -m "Enable time-sensitive alerts, app group, widgets and Siri"
git push
```

Xcode Cloud picks it up and the next TestFlight build has all of it.

## App Store Connect bits

- **App Privacy:** *Location → Coarse Location*, used for *App
  Functionality*, **not** linked to the user, **not** used for tracking.
  (Your rough coordinates go to Open-Meteo for the cloud forecast; nothing
  else leaves the phone.) Everything else: *Data Not Collected*.
- **Listing copy and screenshots:** see [`app-store-listing.md`](app-store-listing.md).

- **Privacy manifest.** The app's own Swift reads `UserDefaults`
  (`LookUpIntents.swift`, the widget's app group), which Apple counts as a
  "required reason" API. Add `PrivacyInfo.xcprivacy` to the Runner target
  and to the widget extension (File › New › App Privacy), with *User
  Defaults* and reason **CA92.1** (the app's own settings) for Runner and
  **1C8F.1** (app group) for the widget. Without it App Store Connect warns
  on upload (ITMS-91053). The plugins ship their own.

## Still to build: App Attest for Seen near you

Anyone can post an aurora report to the relay today; nothing proves it came
from a real install. The phone is safe against that (reports never raise an
alert by themselves, and a wake-up is an ordinary refresh), but a script can
still wake phones in an area every half hour and put its own "N people, X km
north" wording on an alert the model raises anyway. The fix is App Attest:
`DCAppAttestService` in the app to make a key and sign each report, and the
relay checking the attestation and counting keys, not tokens, as people. It
needs Swift compiled against the iOS SDK and the App Attest capability, so
it waits for a Mac (`docs/seen-near-you.md`, build order step 1).

## Catch it: manual long exposures on iPhone

`ios/Runner/LookUpCapture.swift` is **in the Runner target** and registered
in `AppDelegate.swift`. It was added from Linux: checked line by line against
the AVFoundation and Flutter APIs and with `swiftc -parse`, but never
compiled against the iOS SDK. If Xcode Cloud fails on it, the fix is usually
a one-liner. To back it out instead, revert the commit that added it; Catch
it then falls back to the camera plugin.

On the first Mac or TestFlight build:

1. Build (⌘B) and check there are no warnings in `LookUpCapture.swift`.
2. Try *Photograph it* → *Try a practice run first*, then a real pass from
   a dark spot. Check:
   - the detail line under the plan shows a shutter (e.g. "1 s · ISO 1600"),
     not "Auto exposure";
   - frames arrive about once per shutter;
   - the picture is upright, both with the phone upright and on its side.
