import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plus/nudges.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/caught_it_screen.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/theme.dart';

final _now = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type) => SkyEvent(
      id: id,
      type: type,
      start: _now.subtract(const Duration(hours: 1)),
      peak: _now,
      end: _now.add(const Duration(hours: 2)),
      peakElevationDeg: 40,
      riseAzimuthDeg: 120,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 240,
      details: const {'body': 'Saturn'},
    );

final _saturn = _ev('planet:saturn:x', SkyEventType.planetHighlight);
final _iss = _ev('iss:x', SkyEventType.iss);

class _Settings extends SettingsNotifier {
  _Settings(this.start);
  final LookUpSettings start;
  @override
  Future<LookUpSettings> build() async => start;
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(events: const [], aurora: null, lastRefresh: _now, errors: const []);
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

late ProviderContainer _c;

Future<void> _mount(WidgetTester t, SkyEvent caught, {bool isPlus = false, int earlier = 2, DateTime? shownAt, int notNow = 0, SoftAsk? session}) async {
  t.view.physicalSize = const Size(1179, 4000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final log = SkyLog.from([
    for (var i = 0; i < earlier; i++)
      Sighting(eventId: 'old$i', seen: true, at: _now.subtract(Duration(days: i + 1)), type: SkyEventType.iss),
    Sighting(eventId: caught.id, seen: true, at: _now, type: caught.type),
  ]);
  _c = ProviderContainer(overrides: [
    settingsProvider.overrideWith(() => _Settings(LookUpSettings(onboarded: true, isPlus: isPlus, proNudgeAt: shownAt, proNudgeNotNow: notNow))),
    homeProvider.overrideWith(_Home.new),
    skyLogProvider.overrideWith((_) async => log),
    alertsEnabledProvider.overrideWith((_) async => true),
    plusServiceProvider.overrideWithValue(_FakePlus()),
    widgetPinnableProvider.overrideWith((_) async => false),
  ]);
  addTearDown(_c.dispose);
  await _c.read(settingsProvider.future);
  if (session != null) _c.read(softAskSessionProvider.notifier).claim(session);
  await t.pumpWidget(UncontrolledProviderScope(
    container: _c,
    child: MaterialApp(theme: buildLookUpTheme(), home: CaughtItScreen(event: caught, animate: false)),
  ));
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('free, a third catch of Saturn: one line about the Pro camera, and it remembers it said so', (t) async {
    await _mount(t, _saturn);
    expect(find.byKey(const Key('pro-tip')), findsOneWidget);
    expect(find.textContaining('Pro camera'), findsWidgets);
    expect(find.byType(PaywallSheet), findsNothing, reason: 'a line, never a pop-up');
    expect(_c.read(settingsProvider).value!.proNudgeAt, isNotNull);
    await t.tap(find.byKey(const Key('pro-tip-see')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(PaywallSheet), findsOneWidget, reason: 'only when they ask to see it');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('"Not now" hides it and counts', (t) async {
    await _mount(t, _saturn);
    await t.tap(find.byKey(const Key('pro-tip-not-now')));
    await t.pump();
    expect(find.byKey(const Key('pro-tip')), findsNothing);
    expect(_c.read(settingsProvider).value!.proNudgeNotNow, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('not on the first catch, not for a pass, not on LookUp+, not twice in a week, not after two "Not now"s', (t) async {
    for (final (what, ev, plus, earlier, shown, notNow) in [
      ('first catch', _saturn, false, 0, null, 0),
      ('a pass', _iss, false, 2, null, 0),
      ('LookUp+', _saturn, true, 2, null, 0),
      ('shown 3 days ago', _saturn, false, 2, _now.subtract(const Duration(days: 3)), 0),
      ('two Not nows', _saturn, false, 2, null, 2),
    ]) {
      await _mount(t, ev, isPlus: plus, earlier: earlier, shownAt: shown, notNow: notNow);
      expect(find.byKey(const Key('pro-tip')), findsNothing, reason: what);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('quiet when Home\'s card already had this session, or in the first two days', (t) async {
    await _mount(t, _saturn, session: SoftAsk.missedIt);
    expect(find.byKey(const Key('pro-tip')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
