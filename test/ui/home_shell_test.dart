import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
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
import 'package:lookup/ui/now_screen.dart';
import 'package:lookup/ui/settings_screen.dart';
import 'package:lookup/ui/sky/sky_camera_screen.dart';
import 'package:lookup/ui/sky/sky_screen.dart';
import 'package:lookup/ui/year_card.dart';
import 'package:lookup/services/notification_service.dart' show AlertAction;
import 'package:lookup/ui/finder_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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
  Future<void> refresh({bool force = false, bool quick = false}) async {}
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

  // "Find it" on an alert is one step: straight into the finder. A Look
  // sheet first would cost the pass.
  testWidgets('Find it on an alert opens the finder directly', (t) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await pump(t);
    final event = (await container.read(homeProvider.future)).events.single;
    await container.read(storeProvider).saveEvents([event]);
    container.read(alertTapProvider.notifier).set(AlertTap(event.id, action: AlertAction.find));
    await settle(t);
    expect(find.byType(FinderScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing, reason: 'no Look sheet on the way');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('three tabs: Next, Sky, Log; settings live behind the gear', (t) async {
    await pump(t);
    Finder tab(String label) => find.descendant(of: find.byType(FloatingTabBar), matching: find.text(label));
    for (final label in ['Next', 'Sky', 'Log']) {
      expect(tab(label), findsOneWidget);
    }
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Nashville'), findsWidgets);

    expect(find.text('Week'), findsNothing, reason: 'the week is a step inside Next, not a tab');
    expect(find.text('Coming up'), findsOneWidget);
    await t.scrollUntilVisible(find.text('See the full week'), 300,
        scrollable: find.descendant(of: find.byType(NowScreen), matching: find.byType(Scrollable)).first);
    await t.drag(find.byType(NowScreen), const Offset(0, -150));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('See the full week'));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('The week'), findsOneWidget);
    expect(find.text('At a glance'), findsOneWidget);
    await t.tap(find.byTooltip('Back'));
    await settle(t);
    expect(find.text('The week'), findsNothing);

    await t.tap(find.text('Sky'));
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.textContaining('tap anything'), findsOneWidget); // the dome map
    await t.scrollUntilVisible(find.text('Saturn'), 300,
        scrollable: find.descendant(of: find.byType(SkyScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('Planets'), findsOneWidget);
    expect(find.text('Saturn'), findsOneWidget);

    await t.tap(tab('Next'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('What to tell me about'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('every tab has the Settings gear, and it opens Settings', (t) async {
    await pump(t);
    Finder tab(String label) => find.descendant(of: find.byType(FloatingTabBar), matching: find.text(label));
    for (final label in ['Next', 'Sky', 'Log']) {
      await t.tap(tab(label));
      await t.pump(const Duration(seconds: 1));
      expect(find.descendant(of: find.byType(AppHeader), matching: find.byTooltip('Settings')), findsOneWidget,
          reason: label);
    }
    await t.tap(find.descendant(of: find.byType(AppHeader), matching: find.byTooltip('Settings')));
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

  testWidgets('the camera lives on Sky, not on Next', (t) async {
    await pump(t);
    expect(find.byTooltip('Sky through your camera'), findsNothing, reason: 'Next is about the next thing, nothing else');
    await t.tap(find.descendant(of: find.byType(FloatingTabBar), matching: find.text('Sky')));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.descendant(of: find.byType(AppHeader), matching: find.byTooltip('Sky through your camera')).first);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    final camera = t.widget<SkyCameraScreen>(find.byType(SkyCameraScreen));
    expect(camera.time, isNull, reason: 'it follows the clock');
    expect(camera.things, isNotEmpty, reason: 'the Moon and planets the live Sky map shows');
    expect(container.read(homeTabProvider), 1, reason: 'closing it goes back to Sky');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  // Next is the hero, a timeline under it, and one line on where to go.
  // Favourites and the 20-second story moved to Sky, where you go looking.
  testWidgets('Next keeps to the next thing: hero, Coming up, one where-to-go row', (t) async {
    await pump(t);
    expect(find.text('Coming up'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Where to go tonight'), 300,
        scrollable: find.descendant(of: find.byType(NowScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('Where to go tonight'), findsOneWidget);
    expect(find.text('More tonight'), findsNothing);
    expect(find.text('Your favourites'), findsNothing);
    expect(find.text('Tonight in 20 seconds'), findsNothing);
    await t.tap(find.descendant(of: find.byType(FloatingTabBar), matching: find.text('Sky')));
    await t.pump(const Duration(seconds: 1));
    await t.scrollUntilVisible(find.text('Your favourites'), 300,
        scrollable: find.descendant(of: find.byType(SkyScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('Your favourites'), findsOneWidget);
    expect(find.textContaining('Tap \u2665 on anything'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  // The five-stop spotlight tour and the auto-played demo are gone from first
  // run: onboarding already showed the product working.
  testWidgets('first time in: no tour or demo over the home screen', (t) async {
    await pump(t, toured: false);
    await settle(t);
    expect(find.text('1 of 5'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Coming up'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });
}
