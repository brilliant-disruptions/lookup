import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/look_up_now_screen.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(onboarded: true);
}

/// A device→world rotation with the camera level, facing [az] (true north).
List<double> facing(double az) {
  final a = az * math.pi / 180;
  return [0, 0, -math.sin(a), 0, 0, -math.cos(a), 0, 0, 0];
}

void main() {
  final now = DateTime.utc(2026, 11, 6, 3, 3, 13);
  final e = SkyEvent(
    id: 'iss:1',
    type: SkyEventType.iss,
    start: DateTime.utc(2026, 11, 6, 3, 5),
    peak: DateTime.utc(2026, 11, 6, 3, 7),
    end: DateTime.utc(2026, 11, 6, 3, 9),
    peakElevationDeg: 62,
    riseAzimuthDeg: 247,
    peakAzimuthDeg: 180,
    setAzimuthDeg: 95,
    details: const {'brightness': 'brighter than any star'},
  );

  Future<StreamController<List<double>>> mount(WidgetTester t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final rotation = StreamController<List<double>>();
    addTearDown(rotation.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_Settings.new), clockProvider.overrideWith((_) => Stream.value(now))],
        child: MaterialApp(
          theme: buildLookUpTheme(),
          home: LookUpNowScreen(event: e, orientationStream: rotation.stream),
        ),
      ),
    );
    await t.pump();
    return rotation;
  }

  testWidgets('counts down in seconds and says where it appears', (t) async {
    await mount(t);
    expect(find.text('1:47'), findsOneWidget);
    expect(find.text('Face west-southwest'), findsOneWidget); // no compass reading yet
    expect(find.textContaining('It appears in the west-southwest and climbs high in the sky'), findsOneWidget);
  });

  testWidgets('the arrow talks you round as the phone turns', (t) async {
    final rotation = await mount(t);
    rotation.add(facing(180)); // facing south; it appears WSW, to the right
    await t.pump();
    await t.pump();
    expect(find.text('Turn right'), findsOneWidget);
    for (var i = 0; i < 30; i++) {
      rotation.add(facing(250)); // the needle eases round
      await t.pump();
    }
    expect(find.text('You\'re facing it'), findsOneWidget);
  });
}
