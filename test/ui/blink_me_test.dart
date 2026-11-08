import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/look_sheet.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(onboarded: true);
}

/// Counts re-plans instead of fetching.
class _Home extends HomeNotifier {
  int replans = 0;
  @override
  Future<HomeData> build() async =>
      HomeData(events: const [], recent: const [], aurora: null, lastRefresh: null, errors: const []);
  @override
  Future<void> refresh({bool force = false, bool quick = false}) async => replans++;
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  final now = DateTime.utc(2026, 11, 6, 22);
  SkyEvent pass(SkyEventType type) => SkyEvent(
        id: '${type.name}:1',
        type: type,
        start: now.add(const Duration(hours: 5)),
        peak: now.add(const Duration(hours: 5, minutes: 2)),
        end: now.add(const Duration(hours: 5, minutes: 4)),
        peakElevationDeg: 60,
        riseAzimuthDeg: 247,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 95,
      );

  Future<(ProviderContainer, _Home)> mount(WidgetTester t, SkyEvent e) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final home = _Home();
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        homeProvider.overrideWith(() => home),
        clockProvider.overrideWith((_) => Stream.value(now)),
      ],
      child: MaterialApp(theme: buildLookUpTheme(), home: Scaffold(body: LookSheet(event: e))),
    ));
    await t.pump();
    return (ProviderScope.containerOf(t.element(find.byType(LookSheet))), home);
  }

  // The lead is per event and goes straight into the plan: picking it
  // re-plans, picking it again hands the event back to Settings' lead.
  testWidgets('picking a lead saves it for this event and re-plans; picking it again clears it', (t) async {
    final (c, home) = await mount(t, pass(SkyEventType.iss));
    expect(find.text('Blink me'), findsOneWidget);
    await t.tap(find.text('1 hour'));
    await t.pump();
    expect(c.read(settingsProvider).value!.blinkLeads, {'iss:1': 60});
    expect(home.replans, 1);
    await t.tap(find.text('1 hour'));
    await t.pump();
    expect(c.read(settingsProvider).value!.blinkLeads, isEmpty);
    expect(home.replans, 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('no chips for things that are never pushed', (t) async {
    await mount(t, pass(SkyEventType.satellitePass));
    expect(find.text('Blink me'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
