import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/look_sheet.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/plan_screen.dart';
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/where_to_go_screen.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.isPlus);
  final bool isPlus;
  @override
  Future<LookUpSettings> build() async => LookUpSettings(onboarded: true, isPlus: isPlus);
}

class _FakePlus implements PlusService {
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _start = DateTime.utc(2026, 11, 6, 3, 5);
final _transit = SkyEvent(
  id: 'transit-moon:1',
  type: SkyEventType.issTransit,
  start: _start,
  peak: _start,
  end: _start.add(const Duration(milliseconds: 800)),
  peakElevationDeg: 40,
  riseAzimuthDeg: 140,
  peakAzimuthDeg: 140,
  setAzimuthDeg: 140,
  details: const {'body': 'Moon', 'crossingMs': 800},
);

Future<void> mount(WidgetTester t, {required bool isPlus, required void Function(BuildContext) onTap}) async {
  t.view.physicalSize = const Size(1179, 3000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(() => _Settings(isPlus)), plusServiceProvider.overrideWithValue(_FakePlus())],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        // Like the real app's root, something keeps the settings loaded.
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(settingsProvider);
            return Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => onTap(c), child: const Text('Go'))));
          },
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
  await t.tap(find.text('Go'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('free: Where to go tonight opens the paywall on that feature', (t) async {
    await mount(t, isPlus: false, onTap: openWhereToGo);
    expect(find.byType(PaywallSheet), findsOneWidget);
    expect(find.text('Find the clear, dark sky near you tonight, and go.'), findsOneWidget);
  });

  testWidgets('free: tonight and the next two nights plan; the fourth night is LookUp+', (t) async {
    await mount(t, isPlus: false, onTap: (c) => openPlan(c, night: 3));
    expect(find.byType(PaywallSheet), findsOneWidget);
    expect(find.text('Plan any of the next 14 nights, here or at any saved place.'), findsOneWidget);
  });

  testWidgets('free: a transit is photo planning, on LookUp+', (t) async {
    await mount(t, isPlus: false, onTap: (c) => showLookSheet(c, _transit));
    expect(find.byType(PaywallSheet), findsOneWidget);
    expect(find.byType(LookSheet), findsNothing);
  });

  testWidgets('LookUp+: straight to the transit', (t) async {
    await mount(t, isPlus: true, onTap: (c) => showLookSheet(c, _transit));
    expect(find.byType(PaywallSheet), findsNothing);
    expect(find.byType(LookSheet), findsOneWidget);
  });

  test('list rows lock Plus-only alerts and transits on free, nothing on Plus', () {
    expect(lockedOnFree(_transit, isPlus: false), isTrue);
    expect(lockedOnFree(_transit, isPlus: true), isFalse);
  });
}
