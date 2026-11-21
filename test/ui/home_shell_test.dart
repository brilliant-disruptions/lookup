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
import 'package:lookup/ui/kit/pip_mark.dart';
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
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Settings extends SettingsNotifier {
  _Settings({this.toured = true, this.firstBadge = false});
  final bool toured;

  /// Just finished onboarding: the first badge hasn't had its moment.
  final bool firstBadge;

  @override
  Future<LookUpSettings> build() async =>
      LookUpSettings(
          latitude: 36.17,
          longitude: -86.78,
          placeName: 'Nashville',
          onboarded: true,
          toured: toured,
          firstBadgeShown: !firstBadge);

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

  Future<void> pump(WidgetTester t, {bool toured = true, bool firstBadge = false}) async {
    t.view.physicalSize = const Size(1179, 2556); // a phone, not the 800×600 default
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(toured: toured, firstBadge: firstBadge)),
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

  testWidgets('four tabs: Home, Week, Explore, Log, and Pip; settings live behind the gear', (t) async {
    await pump(t);
    Finder tab(String label) => find.descendant(of: find.byType(FloatingTabBar), matching: find.text(label));
    for (final label in ['Home', 'Week', 'Explore', 'Log']) {
      expect(tab(label), findsOneWidget);
    }
    expect(tab('Next'), findsNothing, reason: 'there\'s no "now" to go with it');
    expect(find.byKey(const Key('pip-button')), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Nashville'), findsWidgets);

    expect(find.text('Tonight and ahead'), findsNothing, reason: 'the week is its own tab');
    expect(find.text('Coming up'), findsOneWidget);
    // "See every night" on Home goes to the Week tab.
    await t.scrollUntilVisible(find.text('See every night'), 300,
        scrollable: find.descendant(of: find.byType(NowScreen), matching: find.byType(Scrollable)).first);
    await t.drag(find.byType(NowScreen), const Offset(0, -150));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('See every night'));
    await t.pump(const Duration(seconds: 1));
    expect(container.read(homeTabProvider), HomeTab.week);
    expect(find.text('Tonight and ahead'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing, reason: 'a tab, not a pushed screen');

    await t.tap(tab('Explore'));
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.textContaining('tap anything'), findsOneWidget); // the dome map
    await t.scrollUntilVisible(find.text('Saturn'), 300,
        scrollable: find.descendant(of: find.byType(SkyScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('Planets'), findsOneWidget);
    expect(find.text('Saturn'), findsOneWidget);

    await t.tap(tab('Home'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('What to tell me about'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('Explore: a day at a time, up to a week either way; the sky through history is hidden', (t) async {
    await pump(t);
    await t.tap(find.descendant(of: find.byType(FloatingTabBar), matching: find.text('Explore')));
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    final forward = find.byKey(const ValueKey('day-forward'));
    await t.scrollUntilVisible(forward, 200,
        scrollable: find.descendant(of: find.byType(SkyScreen), matching: find.byType(Scrollable)).first);
    expect(find.widgetWithText(TextButton, 'Any night'), findsNothing);
    expect(find.textContaining('3000 BC'), findsNothing);
    // The strip moves as the night changes, so press the button itself.
    for (var i = 0; i < 7; i++) {
      t.widget<IconButton>(forward).onPressed!();
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(t.widget<IconButton>(forward).onPressed, isNull, reason: 'a week ahead is as far as it goes');
    expect(find.byType(PaywallSheet), findsNothing, reason: 'and it never asks for LookUp+');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('every tab has the Settings gear, and it opens Settings', (t) async {
    await pump(t);
    Finder tab(String label) => find.descendant(of: find.byType(FloatingTabBar), matching: find.text(label));
    for (final label in ['Home', 'Week', 'Explore', 'Log']) {
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

  // Pip sits beside the tabs on every tab, and a tap is the live camera.
  testWidgets('Pip beside the tabs opens the live sky camera, from any tab', (t) async {
    await pump(t);
    expect(find.byTooltip('Sky through your camera'), findsNothing, reason: 'Home is about the next thing; Pip is the camera');
    await t.tap(find.descendant(of: find.byType(FloatingTabBar), matching: find.text('Log')));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byKey(const Key('pip-button')));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    final camera = t.widget<SkyCameraScreen>(find.byType(SkyCameraScreen));
    expect(camera.time, isNull, reason: 'it follows the clock');
    expect(camera.things, isNotEmpty, reason: 'the Moon and planets the live Explore map shows');
    expect(container.read(homeTabProvider), HomeTab.log, reason: 'closing it goes back where you were');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  // Home is the hero and the next three things: fast to read, for a kid or
  // anyone. Where to go, favourites and the story live elsewhere.
  testWidgets('Home keeps to the next thing: hero, three coming up, every night a tap away', (t) async {
    await pump(t);
    expect(find.text('Coming up'), findsOneWidget);
    await t.scrollUntilVisible(find.text('See every night'), 300,
        scrollable: find.descendant(of: find.byType(NowScreen), matching: find.byType(Scrollable)).first);
    expect(find.text('Where to go tonight'), findsNothing);
    expect(find.text('More tonight'), findsNothing);
    expect(find.text('Your favourites'), findsNothing);
    expect(find.text('Tonight in 20 seconds'), findsNothing);
    await t.tap(find.descendant(of: find.byType(FloatingTabBar), matching: find.text('Explore')));
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

  // The first badge comes straight after setting up, once.
  testWidgets('just onboarded: the first badge, with Pip waving, once', (t) async {
    await pump(t, firstBadge: true);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Your first badge'), findsOneWidget);
    expect(find.text('Looked up'), findsOneWidget);
    expect(t.widget<PipMark>(find.byKey(const Key('first-badge-pip'))).state, PipState.greet);
    final s = container.read(settingsProvider).value!;
    expect(s.firstBadgeShown, isTrue, reason: 'once only');
    expect(s.onboardedAt, isNotNull, reason: 'dates the badge');
    await t.tap(find.text('Let\'s look'));
    await settle(t);
    expect(find.text('Your first badge'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });

  testWidgets('after that, Home opens straight to the sky', (t) async {
    await pump(t);
    expect(find.text('Your first badge'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });
}
