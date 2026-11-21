import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plus/nudges.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/soft_asks.dart';
import 'package:lookup/ui/theme.dart';

final _now = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type, DateTime start, {Duration length = const Duration(minutes: 5), int? cloud, Map<String, Object?> details = const {}}) =>
    SkyEvent(
      id: id,
      type: type,
      start: start,
      peak: start.add(length ~/ 2),
      end: start.add(length),
      peakElevationDeg: 40,
      riseAzimuthDeg: 270,
      peakAzimuthDeg: 0,
      setAzimuthDeg: 90,
      cloudCoverPercent: cloud,
      details: details,
    );

final _missed = _ev('starlink-x', SkyEventType.starlinkTrain, _now.subtract(const Duration(hours: 10)), cloud: 5, details: {'past': true, 'label': 'Starlink train'});
final _cloudy = _ev('starlink-y', SkyEventType.starlinkTrain, _now.subtract(const Duration(hours: 10)), cloud: 80, details: {'past': true});
final _storm = _ev('aurora-outlook:x', SkyEventType.auroraOutlook, _now.add(const Duration(hours: 6)),
    length: const Duration(hours: 6), details: {'kp': 6.7, 'kpNeeded': 6.0, 'level': 'possible'});

class _Settings extends SettingsNotifier {
  _Settings(this.start);
  final LookUpSettings start;
  @override
  Future<LookUpSettings> build() async => start;
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

late ProviderContainer _c;

Future<void> _mount(WidgetTester t,
    {List<SkyEvent> events = const [], List<SkyEvent> recent = const [], LookUpSettings? s, SoftAsk? session}) async {
  final settings = s ?? LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, onboardedAt: _now.subtract(const Duration(days: 30)));
  _c = ProviderContainer(overrides: [settingsProvider.overrideWith(() => _Settings(settings))]);
  addTearDown(_c.dispose);
  await _c.read(settingsProvider.future);
  if (session != null) _c.read(softAskSessionProvider.notifier).claim(session);
  final home = HomeData(events: events, recent: recent, aurora: null, lastRefresh: _now, errors: const []);
  await t.pumpWidget(UncontrolledProviderScope(
    container: _c,
    child: MaterialApp(theme: buildLookUpTheme(), home: Scaffold(body: ListView(children: [HomeAsk(home: home)]))),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('"You missed it": a Starlink train went over, clear; said once, and remembered', (t) async {
    await _mount(t, recent: [_missed]);
    expect(find.byKey(const Key('home-ask-missedIt')), findsOneWidget);
    expect(find.text('A Starlink train went over you'), findsOneWidget);
    expect(find.textContaining('under clear skies. LookUp+ would have tapped you.'), findsOneWidget);
    expect(_c.read(settingsProvider).value!.missedItId, 'starlink-x');
    expect(_c.read(softAskSessionProvider), SoftAsk.missedIt, reason: 'it holds the session\'s one slot');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('never through cloud', (t) async {
    await _mount(t, recent: [_cloudy]);
    expect(find.byKey(const Key('home-ask-missedIt')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a storm tonight comes first, and the paywall it opens says why', (t) async {
    await _mount(t, events: [_storm], recent: [_missed]);
    expect(find.byKey(const Key('home-ask-storm')), findsOneWidget);
    expect(find.byKey(const Key('home-ask-missedIt')), findsNothing, reason: 'one card, the most time-critical');
    expect(find.text('The aurora could reach you tonight'), findsOneWidget);
    expect(find.textContaining('Kp'), findsNothing, reason: 'words, not numbers');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a sight they turned off is never pitched: no storm without aurora, no missed Starlink without Starlink', (t) async {
    final base = LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, onboardedAt: _now.subtract(const Duration(days: 30)));
    await _mount(t, events: [_storm], s: base.copyWith(auroraEnabled: false));
    expect(find.byKey(const Key('home-ask-storm')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await _mount(t, recent: [_missed], s: base.copyWith(starlinkEnabled: false));
    expect(find.byKey(const Key('home-ask-missedIt')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('in the first two days only a storm is said', (t) async {
    final fresh = LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, onboardedAt: _now.subtract(const Duration(hours: 20)));
    await _mount(t, recent: [_missed], s: fresh);
    expect(find.byKey(const Key('home-ask-missedIt')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await _mount(t, events: [_storm], s: fresh);
    expect(find.byKey(const Key('home-ask-storm')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('"Not now" puts it away and counts', (t) async {
    await _mount(t, recent: [_missed]);
    await t.tap(find.byKey(const Key('soft-ask-not-now')));
    await t.pump();
    expect(find.byKey(const Key('home-ask-missedIt')), findsNothing);
    expect(_c.read(settingsProvider).value!.plusDeclines, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('nothing when another ask had this session, on LookUp+, or after two "Not now"s', (t) async {
    await _mount(t, recent: [_missed], session: SoftAsk.proTip);
    expect(find.byKey(const Key('home-ask-missedIt')), findsNothing);
    await t.pumpWidget(const SizedBox());
    final old = _now.subtract(const Duration(days: 30));
    for (final s in [
      LookUpSettings(latitude: 1, longitude: 1, onboarded: true, onboardedAt: old, isPlus: true),
      LookUpSettings(latitude: 1, longitude: 1, onboarded: true, onboardedAt: old, plusDeclines: 2),
    ]) {
      await _mount(t, events: [_storm], recent: [_missed], s: s);
      expect(find.byKey(const Key('home-ask-storm')), findsNothing);
      expect(find.byKey(const Key('home-ask-missedIt')), findsNothing);
      await t.pumpWidget(const SizedBox());
    }
  });
}
