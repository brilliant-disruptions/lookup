import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/night_plan.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/tonight.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/verdict_card.dart';
import 'package:lookup/ui/theme.dart';

final now = DateTime.now().toUtc();

SkyEvent ev(String id, Duration fromNow, {int? clouds}) => SkyEvent(
  id: id,
  type: SkyEventType.iss,
  start: now.add(fromNow),
  peak: now.add(fromNow + const Duration(minutes: 2)),
  end: now.add(fromNow + const Duration(minutes: 4)),
  peakElevationDeg: 62,
  riseAzimuthDeg: 247,
  peakAzimuthDeg: 180,
  setAzimuthDeg: 95,
  cloudCoverPercent: clouds,
  details: const {'brightness': 'brighter than any star'},
);

/// Tonight starts in an hour and lasts ten, with [covers] cloud hour by hour.
NightPlan night(List<int> covers, {bool saturn = false}) {
  final start = now.add(const Duration(hours: 1));
  final end = start.add(Duration(hours: covers.length));
  final hour = DateTime.utc(start.year, start.month, start.day, start.hour);
  return NightPlan(
    window: (start: start, end: end),
    outlook: NightOutlook.from(
      start: start,
      end: end,
      weather: CloudForecast(
        latitude: 36.17,
        longitude: -86.78,
        fetchedAt: now,
        hourly: [
          for (var i = -1; i <= covers.length; i++)
            CloudSample(
              time: hour.add(Duration(hours: i)),
              coverPercent: covers[i.clamp(0, covers.length - 1)],
            ),
        ],
      ),
    ),
    planets: [
      if (saturn)
        PlanetTonight(
          planet: Planet.saturn,
          magnitude: 0.6,
          elongationDeg: 120,
          evening: true,
          sighting: SkySighting(best: start.add(const Duration(hours: 1)), altDeg: 40, azDeg: 135, verdict: Seeability.great),
        ),
    ],
    moon: const MoonTonight(phase: MoonPhase.newMoon, illumination: 0, waxing: true),
    constellations: const [],
    showpieces: const [],
    darkness: SkyDarkness.suburbs,
  );
}

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, isPlus: true);
}

Future<void> mount(WidgetTester t, List<SkyEvent> events, NightPlan plan) async {
  t.view.physicalSize = const Size(1179, 3000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        clockProvider.overrideWith((_) => Stream.value(now)),
        tonightSkyProvider.overrideWith((_) async => plan),
      ],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: VerdictCard(
              home: HomeData(events: events, aurora: null, lastRefresh: now, errors: const []),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a clear pass tonight: go, with where to look and the countdown', (t) async {
    await mount(t, [ev('iss:1', const Duration(hours: 3), clouds: 5)], night(List.filled(10, 5)));
    expect(find.textContaining('Go out at'), findsOneWidget);
    expect(find.textContaining('ISS flyover. Brighter than any star'), findsOneWidget);
    expect(find.text('Where to look'), findsOneWidget);
    expect(find.text('Clear all night'), findsOneWidget);
    expect(find.textContaining('ISS '), findsWidgets); // marked on the strip
  });

  testWidgets('clouded out: stay in, what is missed, and the next good night', (t) async {
    await mount(t, [
      ev('iss:1', const Duration(hours: 3), clouds: 95),
      ev('iss:2', const Duration(days: 2), clouds: 10),
    ], night(List.filled(10, 95)));
    expect(find.text('Stay in tonight.'), findsOneWidget);
    expect(find.textContaining('Cloud is forecast over the ISS flyover'), findsOneWidget);
    expect(find.textContaining('Next good night: ISS flyover'), findsOneWidget);
    expect(find.text('Where to look'), findsNothing); // never sends them out into cloud
  });

  testWidgets('nothing passes over but Saturn is up on a clear night', (t) async {
    await mount(t, [ev('iss:2', const Duration(days: 2), clouds: 10)], night(List.filled(10, 5), saturn: true));
    expect(find.text('A clear night for Saturn.'), findsOneWidget);
    expect(find.text('Find Saturn'), findsOneWidget);
    expect(find.textContaining('Next good night'), findsOneWidget);
  });
}
