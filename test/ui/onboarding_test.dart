import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/location_service.dart';
import 'package:lookup/services/notification_service.dart';
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
  int refreshes = 0;
  @override
  Future<HomeData> build() async => const HomeData(events: [], aurora: null, lastRefresh: null, errors: []);
  @override
  Future<void> refresh({bool force = false}) async {
    refreshes++;
    state = AsyncData(HomeData(
      events: [
        _ev('iss:a', SkyEventType.iss, const Duration(hours: 5)),
        _ev('starlink:a', SkyEventType.starlinkTrain, const Duration(days: 1)), // Plus-only: no free tap
      ],
      aurora: null,
      lastRefresh: _now,
      errors: const [],
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

  Future<void> pump(WidgetTester t, {required bool grantLocation}) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    home = _Home();
    notifications = _Notifications();
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_Settings.new),
      homeProvider.overrideWith(() => home),
      locationServiceProvider.overrideWithValue(_Location(grantLocation)),
      notificationServiceProvider.overrideWithValue(notifications),
      clockProvider.overrideWith((_) => Stream.value(DateTime.now())),
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
    expect(home.refreshes, 1);
    expect(find.text('Your next sight'), findsOneWidget);
    expect(find.text('ISS flyover'), findsOneWidget);
    expect(find.text('Starlink train'), findsNothing);

    await t.tap(find.text('Tap me 10 minutes before'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    expect(notifications.asked, 1);
    expect(home.refreshes, 2); // alerts planned again now they can land
    expect(container.read(settingsProvider).value?.onboarded, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a denied location offers a town, not a dead end', (t) async {
    await pump(t, grantLocation: false);
    await t.tap(find.text('Show me what\'s over me'));
    await t.pump();
    await t.pump();
    expect(find.text('Choose your town'), findsOneWidget);
    expect(container.read(settingsProvider).value?.onboarded, isFalse);
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
