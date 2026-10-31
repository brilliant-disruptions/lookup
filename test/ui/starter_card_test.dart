import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/night_plan.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/tonight.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/state/plan_state.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/starter_card.dart';
import 'package:lookup/ui/theme.dart';

final _now = DateTime.now().toUtc();

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
}

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(
    events: [
      SkyEvent(
        id: 'iss:a',
        type: SkyEventType.iss,
        start: _now.add(const Duration(days: 1)),
        peak: _now.add(const Duration(days: 1, minutes: 2)),
        end: _now.add(const Duration(days: 1, minutes: 4)),
        peakElevationDeg: 60,
        riseAzimuthDeg: 247,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 100,
      ),
    ],
    aurora: null,
    lastRefresh: _now,
    errors: const [],
  );
  @override
  Future<void> refresh({bool force = false}) async {}
}

final _night = NightPlan(
  window: null,
  outlook: null,
  planets: [
    PlanetTonight(
      planet: Planet.jupiter,
      magnitude: -2.5,
      elongationDeg: 120,
      evening: true,
      sighting: SkySighting(best: _now.add(const Duration(hours: 3)), altDeg: 50, azDeg: 135, verdict: Seeability.great),
    ),
  ],
  moon: const MoonTonight(phase: MoonPhase.newMoon, illumination: 0, waxing: true),
  constellations: const [],
  showpieces: [
    ShowpieceTonight(
      showpieces.firstWhere((s) => s.id == 'm45'),
      SkySighting(best: _now.add(const Duration(hours: 4)), altDeg: 60, azDeg: 90, verdict: Seeability.good),
    ),
  ],
  darkness: SkyDarkness.suburbs,
);

Future<void> _mount(WidgetTester t, List<Sighting> log) async {
  t.view.physicalSize = const Size(1179, 3000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        homeProvider.overrideWith(_Home.new),
        skyLogProvider.overrideWith((_) async => SkyLog.from(log)),
        nightsAheadProvider.overrideWith((_) async => [_night]),
        skyCatalogProvider.overrideWith((_) async => SkyCatalog(stars: const [], constellations: const [])),
        alertsEnabledProvider.overrideWith((_) async => true),
      ],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: const Scaffold(body: Column(children: [StarterSkyCard()])),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('a new user gets three things to find, with tonight\'s flagged', (t) async {
    await _mount(t, const []);
    expect(find.text('Three sights to start with'), findsOneWidget);
    expect(find.text('ISS flyover'), findsOneWidget);
    expect(find.text('Jupiter'), findsOneWidget);
    expect(find.text('The Pleiades'), findsOneWidget);
    expect(find.text('Tonight'), findsNWidgets(2)); // Jupiter and the Pleiades are tonight
  });

  testWidgets('ticks off what is seen', (t) async {
    await _mount(t, [Sighting(eventId: 'iss:old', seen: true, at: _now.subtract(const Duration(days: 3)), type: SkyEventType.iss)]);
    expect(find.text('One down, two to go'), findsOneWidget);
    expect(find.text('Seen'), findsOneWidget);
  });

  testWidgets('gone once all three are seen', (t) async {
    await _mount(t, [
      Sighting(eventId: 'iss:old', seen: true, at: _now.subtract(const Duration(days: 3)), type: SkyEventType.iss),
      Sighting(eventId: 'obj:planet:jupiter', seen: true, at: _now.subtract(const Duration(days: 2))),
      Sighting(eventId: 'obj:m45', seen: true, at: _now.subtract(const Duration(days: 1))),
    ]);
    expect(find.byType(Card), findsNothing);
    expect(find.text('Your first three'), findsNothing);
  });
}
