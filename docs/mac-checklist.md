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

Xcode creates `ios/Runner/Runner.entitlements` and registers the capability
with your App ID (automatic signing). Commit that file and the
`project.pbxproj` change.

## 2. Home-screen widget and Live Activity

1. Runner target → **+ Capability** → **App Groups** → add
   `group.com.brilliantdisruptions.lookup`.
2. Follow [`ios-widgets.md`](ios-widgets.md) to add the widget extension
   (sources are already in `ios/LookUpWidgets/`). Give the extension the same
   App Group.

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
