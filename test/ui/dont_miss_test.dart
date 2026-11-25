import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/now_screen.dart';
import 'package:lookup/ui/theme.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Home's "Don't miss" row: a memorable moment (LookUp+) leads Coming up,
/// in words, and Coming up stays three rows.
class _Settings extends SettingsNotifier {
  _Settings(this.plus);
  final bool plus;
  @override
  Future<LookUpSettings> build() async =>
      LookUpSettings(latitude: 39.74, longitude: -104.99, placeName: 'Denver', onboarded: true, isPlus: plus);
}

final _now = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type, Duration from, Map<String, Object?> details) => SkyEvent(
      id: id,
      type: type,
      start: _now.add(from),
      peak: _now.add(from + const Duration(minutes: 2)),
      end: _now.add(from + const Duration(minutes: 60)),
      peakElevationDeg: 50,
      riseAzimuthDeg: 180,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 180,
      details: details,
    );

final _gathering = _ev('gather:Mars+Jupiter+Regulus:2026-11-15', SkyEventType.gathering, const Duration(days: 3), {
  'bodies': ['Mars', 'Jupiter', 'Regulus'],
  'label': 'Mars, Jupiter and Regulus',
  'separation': 3.7,
  'nightsLeft': 4,
  'when': 'morning',
});

class _Home extends HomeNotifier {
  _Home(this.events);
  final List<SkyEvent> events;
  @override
  Future<HomeData> build() async => HomeData(events: events, aurora: null, lastRefresh: _now, errors: const []);
  @override
  Future<void> refresh({bool force = false, bool quick = false}) async {}
}

class _FakePlus implements PlusService {
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());
  final soon = [
    _ev('iss:a', SkyEventType.iss, const Duration(hours: 3), const {}),
    _ev('iss:b', SkyEventType.iss, const Duration(days: 1), const {}),
    _ev('iss:c', SkyEventType.iss, const Duration(days: 1, hours: 2), const {}),
    _ev('iss:d', SkyEventType.iss, const Duration(days: 2), const {}),
  ];

  Future<void> pump(WidgetTester t, {required bool plus, required List<SkyEvent> events}) async {
    t.view.physicalSize = const Size(1125, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(plus)),
        homeProvider.overrideWith(() => _Home(events)),
        plusServiceProvider.overrideWithValue(_FakePlus()),
        alertsEnabledProvider.overrideWith((_) async => true),
        clockProvider.overrideWith((_) => Stream.value(DateTime.now())),
      ],
      child: MaterialApp(theme: buildLookUpTheme(), home: const NowScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('LookUp+: the memorable moment leads Coming up, in words', (t) async {
    await pump(t, plus: true, events: [...soon, _gathering]..sort((a, b) => a.start.compareTo(b.start)));
    final row = find.byKey(const ValueKey('dont-miss'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Don\'t miss')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('Mars, Jupiter and Regulus · ')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('°')), findsNothing, reason: 'words, not degrees');
    // Still three rows under the hero: the moment and two more (iss:a is the hero).
    expect(find.textContaining('ISS flyover'), findsNWidgets(2 + 1));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('free: no "Don\'t miss" row', (t) async {
    await pump(t, plus: false, events: [...soon, _gathering]..sort((a, b) => a.start.compareTo(b.start)));
    expect(find.byKey(const ValueKey('dont-miss')), findsNothing);
    expect(find.text('Don\'t miss'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nothing memorable this week: no row', (t) async {
    await pump(t, plus: true, events: soon);
    expect(find.byKey(const ValueKey('dont-miss')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
