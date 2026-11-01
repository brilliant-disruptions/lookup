import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/home_shell.dart';
import 'package:lookup/ui/kit/navigation.dart';
import 'package:lookup/ui/kit/surfaces.dart' show ListRow;
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/state/night_state.dart';
import 'package:lookup/ui/night_vision_controls.dart';
import 'package:lookup/ui/settings_screen.dart';
import 'package:lookup/ui/sky/sky_camera_screen.dart';
import 'package:lookup/ui/sky/sky_screen.dart';
import 'package:lookup/ui/year_card.dart';

class _Settings extends SettingsNotifier {
  _Settings({this.toured = true});
  final bool toured;

  @override
  Future<LookUpSettings> build() async =>
      LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, toured: toured);

  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async {
    final start = DateTime.now().toUtc().add(const Duration(hours: 3));
    return HomeData(
      events: [
        SkyEvent(
          id: 'iss:1',
          type: SkyEventType.iss,
          start: start,
          peak: start.add(const Duration(minutes: 2)),
          end: start.add(const Duration(minutes: 4)),
          peakElevationDeg: 60,
          riseAzimuthDeg: 250,
          peakAzimuthDeg: 180,
          setAzimuthDeg: 90,
          cloudCoverPercent: 5,
        ),
      ],
      aurora: null,
      lastRefresh: DateTime.now().toUtc(),
      errors: const [],
    );
  }

  @override
  Future<void> refresh({bool force = false}) async {}
}

void main() {
  late SkyCatalog catalog;
  setUpAll(() {
    catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
        jsonDecode(File('assets/sky/constellations.json').readAsStringSync()));
  });

  late ProviderContainer container;

  // Route and caption transitions finish over a couple of frames.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> pump(WidgetTester t, {bool toured = true}) async {
    t.view.physicalSize = const Size(1179, 2556); // a phone, not the 800×600 default
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(toured: toured)),
        homeProvider.overrideWith(_Home.new),
        clockProvider.overrideWith((_) => Stream.value(DateTime.now())),
        skyLogProvider.overrideWith((_) async => SkyLog.from(const [])),
        yearReviewProvider.overrideWith((_) async => null),
        alertsEnabledProvider.overrideWith((_) async => true),
        weatherProvider.overrideWith((_) async => null),
        skyCatalogProvider.overrideWith((_) async => catalog),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: HomeShell())));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('four tabs; settings live behind the gear', (t) async {
    await pump(t);
    Finder tab(String label) => find.descendant(of: find.byType(FloatingTabBar), matching: find.text(label));
    for (final label in ['Tonight', 'Sky', 'Week', 'Log']) {
      expect(tab(label), findsOneWidget);
    }
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Nashville'), findsWidgets);

    await t.tap(find.text('Week'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('The week'), findsOneWidget);
    expect(find.text('At a glance'), findsOneWidget);

    await t.tap(find.text('Sky'));
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.textContaining('tap anything'), findsOneWidget); // the dome map
    await t.scrollUntilVisible(find.text('Saturn'), 300,
        scrollable: find.descendant(of: find.byType(SkyScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('Planets'), findsOneWidget);
    expect(find.text('Saturn'), findsOneWidget);

    await t.tap(tab('Tonight'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('What to tell me about'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  // Settings stays Settings: a tap opens all of it. Press and hold is only a
  // shortcut to night vision.
  testWidgets('press and hold Settings for just night vision; a tap is still all of Settings', (t) async {
    await pump(t);
    await t.longPress(find.byTooltip('Settings'));
    await settle(t);
    expect(find.byType(NightVisionCard), findsOneWidget);
    expect(find.text('How red'), findsOneWidget);
    expect(find.text('What to tell me about'), findsNothing, reason: 'not the whole of Settings');

    // Dragging How red down nudges Auto down (no light sensor in tests: Auto says full red).
    await t.drag(find.descendant(of: find.byType(NightVisionCard), matching: find.byType(Slider)), const Offset(-120, 0));
    await settle(t);
    final s = container.read(settingsProvider).value!;
    expect(s.nightVisionFollowsLight, isTrue, reason: 'a tweak never switches Auto off');
    expect(s.nightVisionNudge, lessThan(0));
    expect(container.read(nightVisionDragProvider), isNull, reason: 'the preview ends with the drag');

    // The card links to the Night vision section of Settings.
    await t.tap(find.text('All night vision settings ›'));
    await settle(t);
    expect(find.byType(NightVisionCard), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.text('How red'), findsOneWidget);
    await t.pageBack();
    await settle(t);

    // A plain tap: all of Settings, no card.
    await t.tap(find.byTooltip('Settings'));
    await settle(t);
    expect(find.byType(NightVisionCard), findsNothing);
    expect(find.text('What to tell me about'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('Settings: Auto and How red only while night vision is on', (t) async {
    await pump(t);
    await t.tap(find.byTooltip('Settings'));
    await settle(t);
    final list = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)).first;
    final row = find.ancestor(of: find.text('Night vision'), matching: find.byType(ListRow));
    await t.scrollUntilVisible(row, 200, scrollable: list);
    await t.drag(list, const Offset(0, 300)); // down into the middle, clear of the header
    await settle(t);
    expect(find.text('How red'), findsOneWidget);
    await t.tap(find.descendant(of: row, matching: find.byType(Switch)));
    await settle(t);
    expect(container.read(settingsProvider).value!.nightVision, isFalse);
    expect(find.text('How red'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('the camera on Tonight opens the live sky through the camera, from Tonight', (t) async {
    await pump(t);
    expect(find.byType(SkyCameraScreen), findsNothing);
    // Where the eye used to be: one tap from the home screen to the camera view.
    await t.tap(find.descendant(of: find.byType(AppHeader), matching: find.byTooltip('Sky through your camera')).first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    final camera = t.widget<SkyCameraScreen>(find.byType(SkyCameraScreen));
    expect(camera.time, isNull, reason: 'from Tonight it follows the clock');
    expect(camera.things, isNotEmpty, reason: 'the Moon and planets the live Sky map shows');
    expect(container.read(homeTabProvider), 0, reason: 'closing it goes back to Tonight');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('Tonight keeps to the next thing; the rest is one row each', (t) async {
    await pump(t);
    expect(find.text('More tonight'), findsOneWidget);
    expect(find.text('Your favourites'), findsOneWidget);
    expect(find.textContaining('Sky tab to follow it'), findsOneWidget);
    expect(find.text('Where to go tonight'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('first time in, a five-stop tour; done once, then remembered', (t) async {
    await pump(t, toured: false);
    await settle(t);
    expect(find.text('1 of 5'), findsOneWidget);
    expect(find.text('The next thing worth stepping out for'), findsOneWidget);

    await t.tap(find.text('Next'));
    await settle(t);
    expect(find.text('2 of 5'), findsOneWidget);
    expect(find.text('Everything up there now'), findsOneWidget);
    // Tapping anywhere goes on too.
    await t.tapAt(const Offset(20, 20));
    await settle(t);
    expect(find.text('Plan ahead'), findsOneWidget);
    await t.tap(find.text('Next'));
    await settle(t);
    expect(find.text('Red light after dark'), findsOneWidget);
    expect(find.byIcon(Icons.remove_red_eye_rounded), findsNothing, reason: 'Settings has the switch now, not an eye');
    await t.tap(find.text('Next'));
    await settle(t);
    expect(find.text('5 of 5'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    await t.tap(find.text('Got it'));
    await settle(t);
    expect(find.text('5 of 5'), findsNothing);
    expect(container.read(settingsProvider).value!.toured, isTrue);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('skipping the tour counts as seen; Settings can replay it', (t) async {
    await pump(t, toured: false);
    await settle(t);
    await t.tap(find.text('Skip'));
    await settle(t);
    expect(find.text('1 of 5'), findsNothing);
    expect(container.read(settingsProvider).value!.toured, isTrue);

    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    await Scrollable.ensureVisible(t.element(find.text('Show me around')), alignment: 0.5);
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Show me around'));
    await settle(t);
    await settle(t);
    expect(find.text('1 of 5'), findsOneWidget);
    expect(find.text('The week'), findsNothing, reason: 'the tour starts on Tonight');
    await t.tap(find.text('Skip'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });
}
