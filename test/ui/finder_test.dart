import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
import 'package:lookup/domain/sky/landmarks.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/finder_camera.dart';
import 'package:lookup/ui/finder_screen.dart';
import 'package:lookup/ui/pip/pip_aim.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
}

/// Someone who has already been shown the ring once.
class _Coached extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async =>
      const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, pipCoached: true);
}

void main() {
  // The first lock saves the coach mark as seen.
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
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

  Future<StreamController<List<double>>> pump(WidgetTester t, {bool coached = false, bool still = false}) async {
    final c = StreamController<List<double>>(sync: true);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(coached ? _Coached.new : _Settings.new),
        clockProvider.overrideWith((_) => Stream.value(now)),
      ],
      child: MaterialApp(
        builder: (context, child) =>
            still ? MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!) : child!,
        home: FinderScreen(event: event, orientationStream: c.stream),
      ),
    ));
    await t.pump();
    return c;
  }

  // The words go to VoiceOver, not the screen: Pip's live region carries
  // them, so a blind user hears each change as they turn.
  testWidgets('guides you onto the target, announcing each change to VoiceOver', (t) async {
    final c = await pump(t);
    // No reading yet: the compass words are all there is.
    expect(find.text('Look north, low on the horizon'), findsOneWidget);

    c.add(east);
    await t.pump();
    expect(find.bySemanticsLabel('Turn left'), findsOneWidget);
    expect(find.textContaining('Turn left'), findsNothing, reason: 'motion carries it on screen, not words');
    final live = t.getSemantics(find.byType(PipAim));
    expect(live.flagsCollection.isLiveRegion, isTrue);

    c.add(west);
    await t.pump();
    expect(find.bySemanticsLabel('Turn right'), findsOneWidget);

    c.add(north);
    await t.pump();
    expect(find.bySemanticsLabel('You\'re looking right at it'), findsOneWidget);
    // Unmount first so the finder cancels its subscription.
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });

  // Once you know the ring, the screen is the sky: the name and nothing
  // else to read (the clock joins it only in the countdown).
  testWidgets('after first use, at most two pieces of text on the main path', (t) async {
    final c = await pump(t, coached: true);
    c.add(east);
    await t.pump();
    expect(find.byType(Text).evaluate().length, lessThanOrEqualTo(2));
    expect(find.text('Bring the light into the ring'), findsNothing);
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });

  testWidgets('the ring hint shows until the first lock, then never again', (t) async {
    final c = await pump(t);
    c.add(east);
    await t.pump();
    expect(find.text('Bring the light into the ring'), findsOneWidget);
    c.add(north);
    await t.pump();
    await t.pump();
    expect(find.text('Bring the light into the ring'), findsNothing);
    c.add(east);
    await t.pump();
    expect(find.text('Bring the light into the ring'), findsNothing, reason: 'coached for good');
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });

  // Reduce Motion: Pip sits on its spot instead of flying, trailing and
  // hovering, so nothing on the finder keeps animating.
  testWidgets('with Reduce Motion, Pip holds still', (t) async {
    final c = await pump(t, coached: true, still: true);
    c.add(east);
    await t.pump();
    final aim = t.state(find.byType(PipAim)) as TickerProvider;
    expect(aim, isNotNull);
    expect(t.binding.transientCallbackCount, 0, reason: 'no ticker running');
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });

  // The finder is the camera view with a target in it: the constellation
  // pictures, and the one in the middle lighting up and twinkling, must come
  // with it, not just the bare stars.
  testWidgets('over the camera, the finder draws the constellation pictures and lights the middle one', (t) async {
    final c = StreamController<List<double>>(sync: true);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        clockProvider.overrideWith((_) => Stream.value(now)),
      ],
      child: MaterialApp(home: FinderScreen(event: event, orientationStream: c.stream, camera: true)),
    ));
    await t.pump();
    c.add(north);
    await t.pump();
    final sky = t
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<SkyOverlayPainter>()
        .single;
    expect(sky.glow, isNotNull, reason: 'pictures fade up as you turn onto them');
    expect(sky.onSpotlit, isNotNull, reason: 'the middle one is found and lit');
    expect(sky.twinkle, isNotNull, reason: 'its stars twinkle');
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });

  testWidgets('no numbers on the main screen; the name opens the Look sheet', (t) async {
    final c = await pump(t);
    c.add(east);
    await t.pump();
    expect(find.textContaining('°'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Shows where and when to look')), findsNothing,
        reason: 'the hint is a hint, not a label');
    final name = t.getSemantics(find.text('Rocket launch').first);
    expect(name.hint, 'Shows where and when to look');
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
    c.add(north);
    await t.pump();
    // First Pip flies the route, and only says so to VoiceOver.
    expect(find.bySemanticsLabel('Watch the route'), findsOneWidget);
    expect(find.byTooltip('Show the route again'), findsOneWidget);

    await t.pump(const Duration(seconds: 4));
    await t.pump();
    expect(find.bySemanticsLabel('Watch the route'), findsNothing);
    // Hopping via the landmark: the way out of it is a button, not words.
    await t.tap(find.byTooltip('Go straight to where it rises'));
    await t.pump();
    expect(find.byTooltip('Go straight to where it rises'), findsNothing);

    // The replay chip flies the route again.
    await t.tap(find.byTooltip('Show the route again'));
    await t.pump();
    await t.pump();
    expect(find.bySemanticsLabel('Watch the route'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pumpWidget(const SizedBox());
    unawaited(c.close());
  });
}
