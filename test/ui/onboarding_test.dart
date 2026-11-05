import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/services/refresh_service.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/location_service.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/onboarding_screen.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings();
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

    await t.tap(find.text('Tap me 10 minutes before'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(notifications.asked, 1);
    expect(home.refreshes, 3); // alerts planned again now they can land

    // A Plus-only train really is coming, so the paywall shows its tap now;
    // closing it finishes onboarding.
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(container.read(settingsProvider).value?.onboarded, isNot(true));
    Navigator.of(t.element(find.text('Restore purchases'))).pop();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(container.read(settingsProvider).value?.onboarded, isTrue);
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

    await t.tap(find.text('Tap me 10 minutes before'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(notifications.asked, 1);
    // The running full refresh plans alerts at its end; no second one queued.
    expect(home.quick, [true, false]);
    expect(find.text('Restore purchases'), findsOneWidget);
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
    expect(find.byKey(const Key('sight-placeholder')), findsNWidgets(3));
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

  testWidgets('"Not now" finishes without the notification prompt', (t) async {
    await pump(t, grantLocation: true);
    await t.tap(find.text('Show me what\'s over me'));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    await t.tap(find.text('Not now'));
    await t.pump();
    await t.pump();
    expect(notifications.asked, 0);
    expect(container.read(settingsProvider).value?.onboarded, isTrue);
    await t.pumpWidget(const SizedBox());
  });
}
