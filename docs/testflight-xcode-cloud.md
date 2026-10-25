# TestFlight via Xcode Cloud

One-time setup to get LookUp building in Xcode Cloud and landing in TestFlight on every push to `master`.

What the repo already provides:

- `ios/ci_scripts/ci_post_clone.sh` installs Flutter, runs `flutter pub get`, writes `Generated.xcconfig` with `CI_BUILD_NUMBER` as the build number, and runs `pod install`.
- `ios/Podfile` (iOS 15.0) and the Pods includes in `ios/Flutter/*.xcconfig`.
- `ITSAppUsesNonExemptEncryption = NO` in `Info.plist`, so TestFlight doesn't ask the export-compliance question on each build.
- Bundle ID `com.brilliantdisruptions.lookup`, shared `Runner` scheme, display name "LookUp".

## 1. Register the bundle ID

developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → **+** → App IDs → App.

- Description: `LookUp`
- Bundle ID (explicit): `com.brilliantdisruptions.lookup`
- Capabilities: leave defaults. In-App Purchase is on for every App ID. No push entitlement is needed (alerts are local notifications).

## 2. Create the app in App Store Connect

appstoreconnect.apple.com → Apps → **+** → New App.

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `LookUp: Sky Alerts` (store names are globally unique; plain "LookUp" is likely taken) |
| Primary language | English (U.S.) |
| Bundle ID | `com.brilliantdisruptions.lookup` |
| SKU | `lookup-ios-001` |
| User access | Full access |

The on-device name stays "LookUp"; it comes from `CFBundleDisplayName`, not the store name.

## 3. One local pass in Xcode (on a Mac)

```bash
git clone https://github.com/michaeljwilt/lookup && cd lookup
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace          # the workspace, not the .xcodeproj
```

In Xcode: Runner target → **Signing & Capabilities** → check *Automatically manage signing*, pick your **Team**. Do this for the `Release` and `Profile` configurations too (the "All" tab covers them). Optionally add the **In-App Purchase** and **Background Modes** (Background fetch, Background processing) capabilities here so they show up in the UI; `Info.plist` already declares the modes.

Build once to a simulator (`⌘R`) to confirm it compiles, then commit the `project.pbxproj` change that sets `DEVELOPMENT_TEAM` and push it. Xcode Cloud needs that team ID in the repo.

## 4. Create the Xcode Cloud workflow

In Xcode with `Runner.xcworkspace` open: **Product → Xcode Cloud → Create Workflow…**

1. Select the **Runner** app, Next.
2. Edit the default workflow:
   - **General**: name it `TestFlight`.
   - **Environment**: Xcode – Latest Release, macOS – Latest Release.
   - **Start Conditions**: Branch Changes → `master`. Remove the pull-request condition if you don't want PR builds.
   - **Actions**: delete *Build*, add **Archive** → Platform iOS, Scheme `Runner`, Distribution preparation **TestFlight (Internal Testing Only)**.
   - **Post-Actions**: **TestFlight Internal Testing** → add your internal group (create one in App Store Connect → TestFlight → Internal Testing first, e.g. "Founders").
3. **Grant access to the source code**: Xcode opens GitHub to install the *Xcode Cloud* GitHub app on `michaeljwilt/lookup`. Approve it for that repo.
4. Confirm the App Store Connect app record when asked (it should find the one from step 2), then **Start Build**.

The first build takes 15–25 minutes; most of that is cloning Flutter and `pod install`. Watch it under the Report navigator (`⌘9`) → Cloud, or App Store Connect → Xcode Cloud.

## 5. Install

When the build finishes processing (another 5–15 minutes), internal testers get an email. Install the **TestFlight** app on the iPhone, sign in with the Apple ID that's in the internal group, and install LookUp.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `ci_post_clone.sh: Permission denied` | The script lost its executable bit: `git update-index --chmod=+x ios/ci_scripts/ci_post_clone.sh` |
| `Generated.xcconfig must exist` during `pod install` | `flutter pub get` didn't run; check the post-clone log for the Flutter clone step |
| `No signing certificate` / `requires a development team` | Step 3 wasn't committed; `DEVELOPMENT_TEAM` must be in `project.pbxproj` |
| "Redundant binary upload" / duplicate build number | The build number comes from `CI_BUILD_NUMBER`; don't hard-code `--build-number` elsewhere |
| Build is stuck "Missing Compliance" | `ITSAppUsesNonExemptEncryption` is missing from `Info.plist` |

## Before external TestFlight or the App Store

- Create the three IAP products (`lookup_plus_monthly`, `lookup_plus_yearly`, `lookup_plus_lifetime`) and a subscription group; sign the Paid Applications agreement.
- Add a privacy policy URL and the App Privacy answers (location: coarse, not linked to identity, not used for tracking).
- External testers need a Beta App Review; internal testers (up to 100 team members) don't.
