import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/finder_screen.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
}

void main() {
  final now = DateTime.utc(2026, 10, 25, 23);
  // A target due north on the horizon (declination at Nashville is ~-4°).
  final event = SkyEvent(
    id: 'launch:test',
    type: SkyEventType.rocketLaunch,
    start: now.add(const Duration(minutes: 5)),
    peak: now.add(const Duration(minutes: 7)),
    end: now.add(const Duration(minutes: 11)),
    peakElevationDeg: 0,
    riseAzimuthDeg: 0,
    peakAzimuthDeg: 0,
    setAzimuthDeg: 0,
    details: const {'label': 'Rocket launch', 'name': 'Test', 'distanceKm': 100},
  );
  // Upright, back camera facing magnetic north / east.
  const north = [1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0];
  const east = [0.0, 0.0, -1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0];
  const west = [0.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0];

  Future<StreamController<List<double>>> pump(WidgetTester t) async {
    final c = StreamController<List<double>>(sync: true);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        clockProvider.overrideWith((_) => Stream.value(now)),
      ],
      child: MaterialApp(home: FinderScreen(event: event, orientationStream: c.stream)),
    ));
    await t.pump();
    return c;
  }

  testWidgets('guides you onto the target and confirms when you are on it', (t) async {
    final c = await pump(t);
    expect(find.text('Hold your phone up toward the sky'), findsOneWidget);

    c.add(east);
    await t.pump();
    expect(find.textContaining('Turn left'), findsOneWidget);

    c.add(west);
    await t.pump();
    expect(find.textContaining('Turn right'), findsOneWidget);

    c.add(north);
    await t.pump();
    expect(find.text('You\'re looking right at it'), findsOneWidget);
    // Unmount first so the finder cancels its subscription.
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });

  testWidgets('hold it there and it hands off to your eyes, in red', (t) async {
    final c = await pump(t);
    c.add(north);
    await t.pump();
    expect(find.text('Lower your phone.'), findsNothing);
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Lower your phone.'), findsOneWidget);
    expect(find.textContaining('It buzzes when it appears'), findsOneWidget);

    await t.tap(find.text('Back to the finder'));
    await t.pump();
    expect(find.text('Lower your phone.'), findsNothing);
    // Still pointing at it: no second hand-off until you leave and come back.
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Lower your phone.'), findsNothing);
    c.add(east);
    await t.pump();
    c.add(north);
    await t.pump(); // sees it's back on target
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Lower your phone.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });

  testWidgets('words on the main screen, numbers only behind Details', (t) async {
    final c = await pump(t);
    c.add(east);
    await t.pump();
    expect(find.textContaining('°'), findsNothing);
    expect(find.textContaining('Look north'), findsOneWidget);
    await t.tap(find.textContaining('Details'));
    await t.pump();
    expect(find.textContaining('°'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });

  testWidgets('leaving the target early cancels the hand-off', (t) async {
    final c = await pump(t);
    c.add(north);
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    c.add(east);
    await t.pump(); // sees it's left the target
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Lower your phone.'), findsNothing);
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });
}
