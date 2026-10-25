# iOS widget + Live Activity setup (one time, in Xcode)

Android's home-screen widget is fully wired in the repo. iOS needs a widget
extension target, which can only be created in Xcode. The Swift is written;
this is ~5 minutes of clicking.

1. Open `ios/Runner.xcworkspace`. **File → New → Target… → Widget Extension.**
   - Product name: `LookUpWidgets`
   - Check **Include Live Activity**. Uncheck *Include Configuration App Intent*.
   - Activate the scheme when asked.
2. Delete the Swift files Xcode generated in the new `LookUpWidgets` group, then
   drag in `ios/LookUpWidgets/LookUpWidgets.swift` and
   `ios/LookUpWidgets/LookUpActivityAttributes.swift` (target: **LookUpWidgets** only).
3. **App Group** on both targets: select *Runner* → Signing & Capabilities →
   **+ Capability → App Groups** → add `group.com.brilliantdisruptions.lookup`.
   Repeat for *LookUpWidgets* with the same group.
4. Set the extension's deployment target to iOS 16.2 or later (Live Activities).
   The app stays on iOS 15; the channel no-ops below 16.2.
5. Build and run once on a device. Long-press the home screen → **+** → LookUp.
6. Commit the `project.pbxproj`, the new `LookUpWidgets` folder contents and the
   two `.entitlements` files Xcode creates. Xcode Cloud picks them up.

`Info.plist` already has `NSSupportsLiveActivities = YES`, and
`AppDelegate.swift` already exposes the `lookup/live_activity` channel the app
uses to start a Lock Screen countdown when you open an event within 30 minutes
of its start.

**Keep the two `LookUpActivityAttributes` structs identical** (the one in
`AppDelegate.swift` and the one in the extension). If they drift, the Live
Activity starts but shows nothing.
