import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/home_shell.dart';
import 'package:lookup/ui/year_card.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async =>
      const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true);
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
  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        homeProvider.overrideWith(_Home.new),
        clockProvider.overrideWith((_) => Stream.value(DateTime.now())),
        skyLogProvider.overrideWith((_) async => SkyLog.from(const [])),
        yearReviewProvider.overrideWith((_) async => null),
        alertsEnabledProvider.overrideWith((_) async => true),
      ],
      child: const MaterialApp(home: HomeShell()),
    ));
    await t.pump(const Duration(seconds: 2));
  }

  testWidgets('three tabs; settings live behind the gear', (t) async {
    await pump(t);
    for (final label in ['Tonight', 'Sky', 'Log']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Nashville'), findsWidgets);

    await t.tap(find.text('Sky'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Your sky'), findsOneWidget);
    expect(find.text('Coming up'), findsOneWidget);

    await t.tap(find.text('Tonight'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.byTooltip('Settings'));
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('What to tell me about'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 1));
  });
}
