import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/plus_card.dart';
import 'package:lookup/ui/theme.dart';

final _now = DateTime.now().toUtc();

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final LookUpSettings initial;
  @override
  Future<LookUpSettings> build() async => initial;
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(
    events: [
      SkyEvent(
        id: 'starlink:1',
        type: SkyEventType.starlinkTrain,
        start: _now.add(const Duration(days: 2)),
        peak: _now.add(const Duration(days: 2, minutes: 2)),
        end: _now.add(const Duration(days: 2, minutes: 4)),
        peakElevationDeg: 45,
        riseAzimuthDeg: 250,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 100,
        details: const {'label': 'Starlink train', 'count': 24},
      ),
    ],
    aurora: null,
    lastRefresh: _now,
    errors: const [],
  );
  @override
  Future<void> refresh({bool force = false}) async {}
}

Future<void> mount(WidgetTester t, LookUpSettings s) async {
  t.view.physicalSize = const Size(1179, 3000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(() => _Settings(s)), homeProvider.overrideWith(_Home.new)],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: const Scaffold(body: Column(children: [PlusNearYouCard()])),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

void main() {
  const free = LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);

  testWidgets('free: the real taps they would miss, and a way to LookUp+', (t) async {
    await mount(t, free);
    expect(find.text('1 more tap coming that free won\'t send'), findsOneWidget);
    expect(find.text('Starlink train'), findsOneWidget);
    expect(find.text('See LookUp+'), findsOneWidget);
  });

  testWidgets('"Not now" puts it away', (t) async {
    await mount(t, free);
    await t.tap(find.text('Not now'));
    await t.pump();
    expect(find.text('See LookUp+'), findsNothing);
  });

  testWidgets('never shown to LookUp+ users', (t) async {
    await mount(t, const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, isPlus: true));
    expect(find.text('LookUp+ near you'), findsNothing);
  });
}
