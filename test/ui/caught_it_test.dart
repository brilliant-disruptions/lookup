import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/caught_it_screen.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/theme.dart';

final _now = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type, Duration fromNow) => SkyEvent(
  id: id,
  type: type,
  start: _now.add(fromNow),
  peak: _now.add(fromNow + const Duration(minutes: 2)),
  end: _now.add(fromNow + const Duration(minutes: 4)),
  peakElevationDeg: 55,
  riseAzimuthDeg: 300,
  peakAzimuthDeg: 20,
  setAzimuthDeg: 110,
);

final _seen = _ev('iss:seen', SkyEventType.iss, const Duration(hours: -1));
final _events = [
  _ev('iss:next', SkyEventType.iss, const Duration(days: 2)),
  _ev('tiangong:a', SkyEventType.tiangong, const Duration(days: 1)),
];

class _Settings extends SettingsNotifier {
  _Settings(this.isPlus);
  final bool isPlus;
  @override
  Future<LookUpSettings> build() async => LookUpSettings(onboarded: true, isPlus: isPlus);
}

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(events: _events, aurora: null, lastRefresh: _now, errors: const []);
  @override
  Future<void> refresh({bool force = false}) async {}
}

class _FakePlus implements PlusService {
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _mount(WidgetTester t, {required bool isPlus}) async {
  t.view.physicalSize = const Size(1179, 4000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final log = SkyLog.from([Sighting(eventId: _seen.id, seen: true, at: _now, type: SkyEventType.iss)]);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(isPlus)),
        homeProvider.overrideWith(_Home.new),
        skyLogProvider.overrideWith((_) async => log),
        alertsEnabledProvider.overrideWith((_) async => true),
        plusServiceProvider.overrideWithValue(_FakePlus()),
      ],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: CaughtItScreen(event: _seen, animate: false),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
  await t.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('free: celebrates, shows the badge and next sight, and offers Plus for a real dated sight', (t) async {
    await _mount(t, isPlus: false);
    expect(find.text('You caught it.'), findsOneWidget);
    expect(find.text('Your first sighting'), findsOneWidget);
    expect(find.text('First light'), findsOneWidget);
    expect(find.text('Next over you'), findsOneWidget);
    expect(find.text('Share it'), findsOneWidget);
    expect(find.text('Tiangong flyover'), findsOneWidget);

    await t.tap(find.text('Get the tap with LookUp+'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(PaywallSheet), findsOneWidget);
  });

  testWidgets('Plus: nothing is sold, and next is the soonest sight', (t) async {
    await _mount(t, isPlus: true);
    expect(find.text('You caught it.'), findsOneWidget);
    expect(find.text('Get the tap with LookUp+'), findsNothing);
    expect(find.text('Tiangong flyover'), findsOneWidget); // now the "next" card
  });
}
