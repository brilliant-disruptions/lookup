# LookUp — notes for agents

- **Keep `lib/domain/` pure Dart.** No Flutter, no plugins, no `dart:io`. Everything there must be unit-testable with `flutter test` and no device.
- **Alerts are the product.** Any change to `AlertPlanner`, `PassPredictor` thresholds, cloud gating or quiet hours needs a test in `test/domain/`. A false alarm is the one thing this app must never do.
- **Never show azimuth/elevation numbers on the main path.** Use `domain/sky/direction.dart` words. Numbers live behind the Look sheet's detail line.
- **Data etiquette.** Celestrak: at most once a day per feed. SWPC: ≥ 30 min. Open-Meteo: ≥ 6 h and non-commercial until billing ships.
- **Fixtures** in `test/fixtures/` are real Celestrak records from 2026-10-20; tests pin times near that epoch. Don't "fix" a test by widening tolerances — check the sky first (ISS visibility comes in ~2-week cycles; some weeks genuinely have none).
- Run before pushing: `flutter analyze && flutter test`.
- Spec: `brilliant-disruptions/app-ideas/look_up_now/spec.md`.
- **iOS native code** (`ios/Runner/AppDelegate.swift`, `ios/LookUpWidgets/`) can't be compiled on Linux; at least run `swiftc -parse` on edited files. The two `LookUpActivityAttributes` structs must stay identical.
- **No backend, no third-party SDKs.** Everything runs on the phone.
- **The fixed sky** (`lib/domain/sky/catalog.dart`, `assets/sky/`) is J2000 data from d3-celestial (BSD-3; keep `assets/sky/LICENSE-d3-celestial.txt`). Planet maths is Schlyter's; tests pin oppositions and elongations to published dates, so don't loosen them.
- **"Can I see it?"** lives in `domain/sky/visibility.dart`. It must never say "Easy to see" through cloud, rain, fog or a washed-out sky: weather and moonlight checks come before the positive verdicts.
- **Not everything is pushed.** `SkyEventType.pushes` is false for the aurora outlook, ISS transits and satellites-tonight; `AlertPlanner` must never schedule those (test pins it). Transits last under a second and are for planning.
- **Native bits waiting on a Mac** are listed in `docs/mac-checklist.md` (time-sensitive capability, app group, widget extension, `ios/Runner/LookUpIntents.swift` not yet in the Runner target). Don't add uncompiled Swift to a target from Linux: it breaks Xcode Cloud.
- **Notification sound:** Android fixes a channel's sound at creation, so changing `lookup_chime` means a new channel id in `NotificationService`.
- **iOS plugins resolve through Swift Package Manager.** Xcode Cloud disables automatic package resolution, so a plugin that pulls a *remote* Swift package (e.g. sentry_flutter → sentry-cocoa) breaks the build unless `ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` is generated on a Mac and committed. Check new iOS plugins' `Package.swift` for `url:` dependencies before adding them.
- **Sky glow map** (`assets/sky/skyglow.bin.gz`, `domain/sky/skyglow.dart`) is an estimate from NASA Black Marble + Natural Earth, rebuilt with `tool/skyglow/`. Keep `assets/sky/SOURCES-skyglow.txt`, never suggest a spot over water, and don't loosen `darkSkySqm`/`citySkySqm` (see `tool/skyglow/README.md`).
- **LookUp+ split** (README): seeing is free, the tap is Plus. Free keeps ISS taps incl. go-now, one saved place, 3 nights of planning. Never ask on first run, during the tour, while a pass is live or under red light (`domain/plus/upgrade_moments.dart`). Saved places beyond the free one are grandfathered, never removed.
- **Standing taps** (favourites at their best, Milky Way nights) must have a real clear forecast, never outrank a fleeting event, and keep their spacing (tests in `test/domain/standing_alerts_test.dart`). Milky Way checks fetch saved places' clouds only for LookUp+, at most every 6 h per place.
