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
3. **Check the widgets and the Dynamic Island** (written from Linux and
   only `swiftc -parse`d, so expect a few compile fixes). Pip is the light
   (`PipLight`, `PipFound` in `ios/LookUpWidgets/LookUpWidgets.swift`), the
   pass is a little arc labelled in words (`PassArc`), never degrees.
   - Home Screen: small, medium (with the arc) and large (the next three);
     Lock Screen: inline, circular, rectangular. The small one turns into
     "It's up" at rise on its own (timeline entries at each rise and set).
   - Live Activity: compact is Pip and the countdown; long-press shows the
     arc with Pip where it rises; minimal is Pip. At rise the app's
     `update` call lights the island up once with the LookUp chime
     (`AlertConfiguration` in `AppDelegate.swift`), and a bar shows how far
     along the pass is. Keep both `LookUpActivityAttributes` structs
     identical if a field is added.
   - The pass without the app: the activity starts stale-dated at the rise,
     so iOS redraws it then and it flips to "It's up" with the app closed.
     Then a **Saw it** button (iOS 17, `SawItIntent.swift`, in both
     targets) leaves the event in the app group. **Change it before
     shipping:** a sighting now goes in the Log only when it's caught with
     Pip in the camera, so the app clears that list without logging
     (`lib/services/lock_screen_catches.dart`). Make the button "Catch it"
     and have it open the app (a `Link`/`widgetURL` to the camera, the same
     as the alert's *Catch it*), then drop the intent.
   - Any button on the heads-up alert now starts the countdown too.
   - Smart Stack: the widget scores itself relevant from an hour before a
     pass until it sets. StandBy uses the small widget.
   - Mockups: the "Island and widgets" and "An even better pass" rows on
     the design canvas.

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
  notification: *Find it*, *Remind me in 5 min*, and on the go-now alert
  *Catch it*, which opens LookUp straight into the camera with Pip.
- **From the review fixes, check on a phone:**
  - The app stays upright when the phone is turned on its side.
  - The screen doesn't dim or lock while Pip is guiding in the camera or
    waiting for a pass in the finder.
  - Deny camera access, then open the camera: the message offers
    *Open Settings*, and it goes to LookUp's page in Settings.
  - *Pause all alerts* (Settings › Alerts) takes every planned alert off,
    and turning it off puts them back.
  - The paywall's *Restore purchases* says what it found ("No LookUp+
    found…" on an account without it).
  - The Week tab shows the whole week with no swiping on a small iPhone.
  - Leaving Catch it after a finished picture (Done, ✕ or a swipe back)
    asks before throwing it away.
- **New in this round, check on a phone:**
  - *Report a problem* (Settings › Help) opens Mail with the version filled
    in; *Privacy Policy* and *Terms of Use* open in Safari, also from the
    paywall and the onboarding offer, which shows the store's yearly price.
  - The rating prompt: in a development build iOS shows it every time, in
    TestFlight never; just check it appears after closing a caught-it
    screen once you have 3 catches and the app is 3 days old (or shorten
    `ReviewAsk.settleIn` for the test).
  - *Your week ahead* arrives Sunday at 5:40 PM, and turning it off in
    Settings › Alerts cancels it.
  - **Bring back my catches:** on a second iPhone signed in to the same
    iCloud Photos, install, choose Limit Access, and tap *Bring back my
    catches from Photos* in Settings › Photos. **Check whether the LookUp
    album made on the first phone is visible under Limited access** (Apple
    lets an app read albums it made; on a new install it may count as a
    different app's album). If it isn't, the sheet should suggest choosing
    the album's photos in the Limited picker, or Full access just for the
    restore: tell me and I'll change the words.
- **Saving to Photos (the LookUp album).** On a fresh install, catch the
  Moon or a planet (point until Pip lands, tap Pip). LookUp's own sheet
  should come first, recommending *Limit Access…*; then iOS asks. Check:
  - Choose **Limit Access…** and pick **no photos**. If iOS won't let you
    finish with none, change the sheet's line "You don't need to pick any
    photos" (`ui/keep_catch.dart`) and `NSPhotoLibraryUsageDescription`.
  - The picture lands in Photos in a **LookUp** album, with its caption,
    the right date and a place on the Photos map.
  - The Log shows it, and Settings › Photos says "Limited, as recommended".
    This is the assumption the whole design rests on: under Limited access
    LookUp can still read the pictures it saved (and its own album). If the
    Log shows "isn't in your Photos any more" for a fresh catch, it can't:
    `DevicePhotoLibrary.save` then keeps LookUp's full copy (it checks with
    `AssetEntity.fromId` straight after saving), but tell me.
  - Delete the picture in Photos: the Log keeps the catch and says so.
  - Choose **Don't Allow** (reset with Settings › General › Transfer or
    Reset › Reset Location & Privacy): catches still reach the Log; nothing
    else prompts. `photo_manager` and `gal` resolve through SPM with no
    remote packages.
  - A Pro camera timelapse lands in the LookUp album too.
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

In order, before the first submission:

1. **Deploy the relay** (`cd relay && npm run deploy`, see `relay/README.md`)
   so the privacy and support pages are live, then open
   `…workers.dev/privacy` and `/support` in a browser.
2. **Agreements:** sign the *Paid Applications* agreement and add banking
   and tax details (subscriptions can't be tested in TestFlight without it).
3. **Subscriptions:** a subscription group *LookUp+* with
   `lookup_plus_monthly` ($4.99) and `lookup_plus_yearly` ($29.99, with a
   7-day free trial as its introductory offer). No lifetime purchase. Ids
   must match `PlusProducts` exactly.
   Give each a review screenshot (the paywall) and a description.
4. **App information:** Privacy Policy URL and Support URL from
   [`app-store-listing.md`](app-store-listing.md#links); keep Apple's
   standard EULA and add the Terms of Use line to the end of the
   description.
5. **App Privacy:** two answers, both used for *App Functionality*,
   **not** linked to the user, **not** used for tracking:
   - *Location → Coarse Location* (coordinates rounded to about a kilometre
     go to Open-Meteo for the cloud forecast; Seen near you sends only
     half-degree squares);
   - *Identifiers → Device ID* (the push address, sent to the relay only if
     aurora wake-ups are on).

   Photos never leave the phone, so they aren't "collected". Everything
   else: *Data Not Collected*. Must match
   `ios/Runner/PrivacyInfo.xcprivacy` and the privacy page
   (`relay/src/pages.ts`); change all three together.
6. **Listing copy and the ten screenshots:** see
   [`app-store-listing.md`](app-store-listing.md) (screenshots in
   `test/screenshots/goldens/appstore/`).
7. **Review notes:** say the camera and Photos are used only for catching
   sky pictures into the LookUp album, and that LookUp+ can be tested with
   the sandbox products.

- **Privacy manifest.** The app's own Swift reads `UserDefaults`
  (`LookUpIntents.swift`, the widget's app group), which Apple counts as a
  "required reason" API.
  - `ios/Runner/PrivacyInfo.xcprivacy` **is in the Runner target** (added
    to the project file from Linux, the same four entries as
    `lookup_chime.wav`, and never opened in Xcode: if it shows red in the
    navigator or isn't under *Copy Bundle Resources*, remove the reference
    and drag the file in again with **Runner** ticked). It declares *User
    Defaults* with reasons **CA92.1** (the app's own settings) and
    **1C8F.1** (the app group), no tracking, and two kinds of data
    collected, both for app functionality and not linked to the user:
    coarse location and the device ID (the push address). That must say
    the same as the App Privacy answers above; change both together.
  - When the widget extension exists, drag
    `ios/LookUpWidgets/PrivacyInfo.xcprivacy` into it and tick the
    extension under *Target Membership* (*User Defaults*, reason
    **1C8F.1**, the app group; nothing collected).

  Without them App Store Connect warns on upload (ITMS-91053). The plugins
  ship their own.

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

## Pro camera: timelapse video on iPhone

`ios/Runner/LookUpTimelapse.swift` encodes a timelapse's kept frames into an
H.264 .mp4 (AVAssetWriter) on the `lookup/timelapse` channel, the same
contract as `android/.../LookUpTimelapse.kt` (which CI compiles). It was
written on Linux and only syntax-checked (`swiftc -parse`), so it is **not in
the Runner target**. Until it is, an iPhone timelapse saves its trail picture
(every frame's brightest) instead of a video.

On a Mac:

1. Add `LookUpTimelapse.swift` to the Runner target and build (⌘B).
2. Register it in `AppDelegate.swift`'s `didInitializeImplicitFlutterEngine`,
   next to `LookUpCapture`:
   ```swift
   if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LookUpTimelapse") {
     LookUpTimelapse.register(with: registrar)
   }
   ```
3. On a device: Explore → the Moon → *Photograph it* → *Timelapse* →
   *Start the timelapse* → *Start now*, wait a minute, *Stop*. Check a clip
   lands in Photos, upright, with the dark sky not crushed to black.

## Pro camera: first checks on a phone

The Pro camera (LookUp+, `lib/ui/pro_camera_screen.dart`) drives the same
native capture as Catch it. On the first device build, for each of the Moon,
a planet and a dark-sky star field:

- the detail line shows a real shutter and ISO (not "Auto exposure");
- pointing at the Moon, the frames start too bright or too dark and LookUp
  corrects them within a few seconds, saying so;
- *Take it* counts down three seconds, then counts frames, and the picture
  lands in Photos and the Log;
- the zoom lens is chosen for the Moon and planets where the phone has one.

