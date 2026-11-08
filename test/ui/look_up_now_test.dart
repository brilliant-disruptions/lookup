import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/look_up_now_screen.dart';
import 'package:lookup/ui/pip/pip_aim.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(onboarded: true);
}

/// A device→world rotation, phone upright, back camera facing [az].
List<double> facing(double az) {
  final a = az * math.pi / 180;
  return [math.cos(a), 0, -math.sin(a), -math.sin(a), 0, -math.cos(a), 0, 1, 0];
}

void main() {
  // The first lock saves the coach mark as seen.
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
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

  Future<StreamController<List<double>>> mount(WidgetTester t, {Stream<DateTime>? clock, NavigatorObserver? nav}) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final rotation = StreamController<List<double>>(sync: true);
    addTearDown(rotation.close);
    await t.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWith(_Settings.new), clockProvider.overrideWith((_) => clock ?? Stream.value(now))],
        child: MaterialApp(
          theme: buildLookUpTheme(),
          navigatorObservers: [?nav],
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
    // No compass reading yet: the compass words.
    expect(find.text('Look west-southwest, low on the horizon'), findsOneWidget);
  });

  testWidgets('Pip talks you round to where it rises, out loud for VoiceOver', (t) async {
    final rotation = await mount(t);
    rotation.add(facing(180)); // facing south; it appears WSW, to the right
    await t.pump();
    expect(t.widget<PipAim>(find.byType(PipAim)).mode, PipMode.countdown);
    expect(find.bySemanticsLabel(RegExp('^Turn right')), findsOneWidget);
    rotation.add(facing(250));
    await t.pump();
    expect(find.bySemanticsLabel('You\'re looking right at it'), findsOneWidget);
  });

  // The countdown is the finder waiting: when it comes up, the same screen
  // carries on. A new route would drop you mid-turn.
  testWidgets('countdown turns into the finder in place, with no new route', (t) async {
    final pushes = <Route<dynamic>>[];
    final clock = StreamController<DateTime>();
    addTearDown(clock.close);
    final rotation = await mount(t, clock: clock.stream, nav: _Pushes(pushes));
    clock.add(now);
    rotation.add(facing(250));
    await t.pump();
    final before = pushes.length;
    expect(find.text('1:47'), findsOneWidget);
    clock.add(e.start.add(const Duration(seconds: 1)));
    await t.pump();
    await t.pump();
    expect(find.text('1:47'), findsNothing);
    expect(t.widget<PipAim>(find.byType(PipAim)).mode, PipMode.find);
    expect(pushes.length, before, reason: 'no push');
  });
}

class _Pushes extends NavigatorObserver {
  _Pushes(this.pushes);
  final List<Route<dynamic>> pushes;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes.add(route);
}
