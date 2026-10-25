# LookUp — notes for agents

- **Keep `lib/domain/` pure Dart.** No Flutter, no plugins, no `dart:io`. Everything there must be unit-testable with `flutter test` and no device.
- **Alerts are the product.** Any change to `AlertPlanner`, `PassPredictor` thresholds, cloud gating or quiet hours needs a test in `test/domain/`. A false alarm is the one thing this app must never do.
- **Never show azimuth/elevation numbers on the main path.** Use `domain/sky/direction.dart` words. Numbers live behind the Look sheet's detail line.
- **Data etiquette.** Celestrak: at most once a day per feed. SWPC: ≥ 30 min. Open-Meteo: ≥ 6 h and non-commercial until billing ships.
- **Fixtures** in `test/fixtures/` are real Celestrak records from 2026-10-20; tests pin times near that epoch. Don't "fix" a test by widening tolerances — check the sky first (ISS visibility comes in ~2-week cycles; some weeks genuinely have none).
- Run before pushing: `flutter analyze && flutter test`.
- Spec: `brilliant-disruptions/app-ideas/look_up_now/spec.md`.
- **Backend** lives in `supabase/` (Deno edge functions). Shared logic in `supabase/functions/_shared/` must stay in sync with the Dart domain (aurora rules, train detector). Run `cd supabase && deno task test` and `deno lint functions/`.
- **iOS native code** (`ios/Runner/AppDelegate.swift`, `ios/LookUpWidgets/`) can't be compiled on Linux; at least run `swiftc -parse` on edited files. The two `LookUpActivityAttributes` structs must stay identical.
- **Optional services** (backend, Firebase push, Sentry) are off unless their `--dart-define`s are set. Never make them required.
