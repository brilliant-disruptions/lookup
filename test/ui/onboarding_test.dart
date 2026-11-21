import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/services/refresh_service.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/location_service.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/onboarding_screen.dart';
import 'package:lookup/ui/theme.dart';

/// What settings start as; the offer tests change it.
var _start = const LookUpSettings();

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => _start;
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async =>
      state = AsyncData(f(state.value ?? await future));
}

final _now = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type, Duration inFuture) => SkyEvent(
      id: id,
      type: type,
      start: _now.add(inFuture),
      peak: _now.add(inFuture + const Duration(minutes: 2)),
      end: _now.add(inFuture + const Duration(minutes: 5)),
      peakElevationDeg: 60,
      riseAzimuthDeg: 247,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 90,
      details: const {'brightness': 'brighter than any star', 'label': 'Starlink train', 'count': 20},
    );

/// Nothing until the first refresh, as on a fresh install.
class _Home extends HomeNotifier {
  /// The `quick` flag of each refresh, in order.
  final quick = <bool>[];
  int get refreshes => quick.length;

  /// Holds full (not quick) refreshes until completed: Starlink on a slow network.
  Completer<void>? slowFull;

  /// Holds the quick look until completed: the ISS on a slow network.
  Completer<void>? slowQuick;

  /// Whether the look comes from the shipped ISS (Celestrak out of reach).
  bool approximate = false;
  @override
  bool get refreshing => !(slowFull?.isCompleted ?? true);
  @override
  Future<HomeData> build() async => const HomeData(events: [], aurora: null, lastRefresh: null, errors: []);
  @override
  Future<void> refresh({bool force = false, bool quick = false}) async {
    this.quick.add(quick);
    if (!quick && slowFull != null) await slowFull!.future;
    if (quick && slowQuick != null) await slowQuick!.future;
    state = AsyncData(HomeData(
      events: [
        _ev('iss:a', SkyEventType.iss, const Duration(hours: 5)),
        _ev('starlink:a', SkyEventType.starlinkTrain, const Duration(days: 1)), // Plus-only: no free tap
      ],
      aurora: null,
      lastRefresh: _now,
      errors: const [],
      approximate: approximate,
    ));
  }
}

class _Location implements LocationService {
  _Location(this.grant);
  final bool grant;
  @override
  Future<bool> requestPermission() async => grant;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Refresh implements RefreshService {
  int prefetched = 0;
  @override
  Future<void> prefetch() async => prefetched++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePlus implements PlusService {
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Notifications implements NotificationService {
  int asked = 0;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late ProviderContainer container;
  late _Home home;
  late _Notifications notifications;
  late _Refresh refresh;

  Future<void> pump(WidgetTester t, {required bool grantLocation}) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    home = _Home();
    notifications = _Notifications();
    refresh = _Refresh();
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      homeProvider.overrideWith(() => home),
      locationServiceProvider.overrideWithValue(_Location(grantLocation)),
      notificationServiceProvider.overrideWithValue(notifications),
      clockProvider.overrideWith((_) => Stream.value(DateTime.now())),
      plusServiceProvider.overrideWithValue(_FakePlus()),
      refreshServiceProvider.overrideWithValue(refresh),
    ]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildLookUpTheme(), home: const OnboardingScreen()),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> settle(WidgetTester t, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('location first, then your real next sight, then the alert ask', (t) async {
    await pump(t, grantLocation: true);
    await t.tap(find.text('Show me what\'s over me'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    // Nothing asked about notifications yet; the free sight is shown, the
    // Plus-only train is not promised.
    expect(notifications.asked, 0);
    // A quick look first (no 4.7 MB Starlink download), the full one behind it.
    expect(home.quick, [true, false]);
    expect(find.text('Your next sight'), findsOneWidget);
    expect(find.text('ISS flyover'), findsOneWidget);
    expect(find.text('Starlink train'), findsNothing);

    // Moment 3: the ask, with the tap it buys shown first.
    await t.tap(find.text('Continue'));
    await settle(t, 4);
    expect(find.byKey(const Key('tap-preview')), findsOneWidget);
    expect(notifications.asked, 0, reason: 'shown the tap before being asked');
    await t.tap(find.text('Tap me 10 minutes before'));
    await settle(t, 4);
    expect(notifications.asked, 1);
    expect(home.refreshes, 3); // alerts planned again now they can land
    // Then, once, what LookUp+ would add: the real Plus-only train coming. An
    // offer page, not the paywall: that only opens if they choose to try.
    expect(find.byKey(const Key('trial-offer')), findsOneWidget);
    expect(find.text('Starlink train'), findsOneWidget);
    expect(find.text('Restore purchases'), findsNothing);
    expect(container.read(settingsProvider).value?.onboarded, isFalse);
    await t.tap(find.byKey(const Key('trial-offer-not-now')));
    await settle(t);
    final s = container.read(settingsProvider).value!;
    expect(s.onboarded, isTrue);
    expect(s.trialOfferShown, isTrue, reason: 'once, never again');
    expect(s.plusDeclines, 1, reason: '"Not now" counts toward the soft asks stopping');
    await t.pumpWidget(const SizedBox());
  });

  // The first sights used to wait for the whole Starlink catalogue; on a
  // phone network that was most of onboarding.
  testWidgets('sights show before the slow full refresh, and the alert ask does not wait for it',
      (t) async {
    await pump(t, grantLocation: true);
    home.slowFull = Completer();
    await t.tap(find.text('Show me what\'s over me'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Your next sight'), findsOneWidget);
    expect(find.text('ISS flyover'), findsOneWidget);

    await t.tap(find.text('Continue'));
    await settle(t, 4);
    await t.tap(find.text('Tap me 10 minutes before'));
    await settle(t, 4);
    expect(notifications.asked, 1);
    // The running full refresh plans alerts at its end; no second one queued.
    expect(home.quick, [true, false]);
    home.slowFull!.complete();
    await t.pumpWidget(const SizedBox());
  });

  // The welcome screen is read while the ISS downloads, and the look shows
  // where the sights will be rather than a spinner.
  testWidgets('the ISS is fetched on the welcome screen, and the look holds places, not a spinner',
      (t) async {
    await pump(t, grantLocation: true);
    expect(refresh.prefetched, 1, reason: 'started before anything is tapped');
    home.slowQuick = Completer();
    await t.tap(find.text('Show me what\'s over me'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(const Key('sight-placeholder')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    home.slowQuick!.complete();
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.byKey(const Key('sight-placeholder')), findsNothing);
    expect(find.text('ISS flyover'), findsOneWidget);
    expect(find.textContaining('Times may be off'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a look from the shipped ISS says its times may be off', (t) async {
    await pump(t, grantLocation: true);
    home.approximate = true;
    await t.tap(find.text('Show me what\'s over me'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('ISS flyover'), findsOneWidget);
    expect(find.textContaining('Times may be off'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('three moments, no Pip tour or demo: the promise opens on the location ask', (t) async {
    await pump(t, grantLocation: true);
    expect(find.text('Hi! I\'m Pip.'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('Show me what\'s over me'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a denied location offers a town, not a dead end', (t) async {
    await pump(t, grantLocation: false);
    await t.tap(find.text('Show me what\'s over me'));
    await t.pump();
    await t.pump();
    expect(find.text('Choose your town'), findsOneWidget);
    expect(container.read(settingsProvider).value?.onboarded ?? false, isFalse);
    expect(notifications.asked, 0);
    await t.pumpWidget(const SizedBox());
  });

  // Pip is introduced on the first real sight, circles while it looks, and
  // blinks on the preview of the tap.
  testWidgets('Pip: circling while it looks, on the first sight, blinking on the tap preview', (t) async {
    await pump(t, grantLocation: true);
    PipMark pip() => t.widget<PipMark>(find.byKey(const Key('onboarding-pip')));
    home.slowQuick = Completer();
    await t.tap(find.text('Show me what\'s over me'));
    await settle(t);
    expect(find.text('Looking at your sky…'), findsOneWidget);
    expect(pip().state, PipState.searching);

    home.slowQuick!.complete();
    await settle(t);
    expect(pip().state, PipState.resting);
    expect(pip().flyFrom, isNotNull, reason: 'it flies to the first sight');
    expect(find.descendant(of: find.byType(GlassCard).first, matching: find.text('ISS flyover')), findsOneWidget);
    expect(find.textContaining('That\'s Pip'), findsOneWidget);

    await t.tap(find.text('Continue'));
    await settle(t, 4);
    expect(t.widget<PipMark>(find.byKey(const Key('onboarding-pip-blink'))).blinking, isTrue);
    expect(find.text('Tap me 10 minutes before'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('"Not now" finishes without the notification prompt', (t) async {
    await pump(t, grantLocation: true);
    await t.tap(find.text('Show me what\'s over me'));
    await settle(t);
    await t.tap(find.text('Continue'));
    await settle(t, 4);
    await t.tap(find.text('Not now'));
    await t.pump();
    await t.pump();
    expect(notifications.asked, 0);
    await settle(t);
    await t.tap(find.byKey(const Key('trial-offer-not-now')));
    await settle(t);
    expect(container.read(settingsProvider).value?.onboarded, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  for (final (what, start) in [
    ('LookUp+ already', const LookUpSettings(isPlus: true)),
    ('already seen once', const LookUpSettings(trialOfferShown: true)),
  ]) {
    testWidgets('no trial offer: $what', (t) async {
      _start = start;
      addTearDown(() => _start = const LookUpSettings());
      await pump(t, grantLocation: true);
      await t.tap(find.text('Show me what\'s over me'));
      await settle(t);
      await t.tap(find.text('Continue'));
      await settle(t, 4);
      await t.tap(find.text('Not now'));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('trial-offer')), findsNothing);
      expect(container.read(settingsProvider).value?.onboarded, isTrue);
      expect(container.read(settingsProvider).value?.plusDeclines, 0);
      await t.pumpWidget(const SizedBox());
    });
  }
}
