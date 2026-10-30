import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
import 'package:lookup/domain/sky/landmarks.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/finder_firefly.dart';
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

  testWidgets('before a pass: the firefly flies the route, then star-hops via a landmark', (t) async {
    final record = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync())).single;
    final from = DateTime.utc(2026, 10, 20, 16);
    final pass = PassPredictor(latitude: 36.17, longitude: -86.78)
        .predict(record: record, type: SkyEventType.iss, from: from, to: from.add(const Duration(days: 21)), minPeakElevationDeg: 10)
        .firstWhere((e) => e.peakElevationDeg > 60);
    final open = pass.start.subtract(const Duration(minutes: 10));
    // Whichever bright thing is up then stands in as the landmark.
    final name = ['Jupiter', 'Saturn', 'Venus', 'Mars', 'the Moon']
        .firstWhere((n) => (landmarkDirection(n, null, open, 36.17, -86.78)?.altitudeDeg ?? -1) > 5);
    final ev = pass.copyWith(details: {
      ...pass.details,
      'landmarks': 'passing right by $name',
      'landmarkPoints': [
        {'name': name, 'f': 0.5, 'above': true, 'close': true},
      ],
    });
    final c = StreamController<List<double>>(sync: true);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        clockProvider.overrideWith((_) => Stream.value(open)),
      ],
      child: MaterialApp(home: FinderScreen(event: ev, orientationStream: c.stream, camera: false)),
    ));
    await t.pump();
    await t.pump();
    expect(find.text('Here\'s the route it will take.'), findsOneWidget);
    expect(find.text('Watch the route'), findsOneWidget);
    expect(find.byType(RouteMap), findsOneWidget);

    await t.pump(const Duration(seconds: 4));
    await t.pump();
    expect(find.textContaining('Start from'), findsOneWidget);

    await t.tap(find.text('Go straight to where it rises'));
    await t.pump();
    expect(find.textContaining('Point where it will rise'), findsOneWidget);

    // Tap the map to fly the route again.
    await t.tap(find.byType(RouteMap));
    await t.pump();
    await t.pump();
    expect(find.text('Here\'s the route it will take.'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });
}
