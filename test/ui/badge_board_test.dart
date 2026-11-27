import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/badges/badge_board.dart';
import 'package:lookup/ui/theme.dart';
import 'package:material_ui/material_ui.dart' hide Badge;

// Noon today, so the catches below never fall in the 3 AM hour (that earns
// the secret "Up past three" and the test would fail between 3 and 4 AM).
final _now = () { final n = DateTime.now().toUtc(); return DateTime.utc(n.year, n.month, n.day, 12); }();

// Coming events count from the real clock: from noon, a pass "in 3 hours"
// would already be over after 15:00 UTC.
final _clock = DateTime.now().toUtc();

SkyEvent _ev(String id, SkyEventType type, Duration inFuture, {double el = 40}) => SkyEvent(
      id: id,
      type: type,
      start: _clock.add(inFuture),
      peak: _clock.add(inFuture),
      end: _clock.add(inFuture + const Duration(minutes: 5)),
      peakElevationDeg: el,
      riseAzimuthDeg: 200,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 100,
    );

class _Home extends HomeNotifier {
  _Home(this.events);
  final List<SkyEvent> events;
  @override
  Future<HomeData> build() async => HomeData(events: events, aurora: null, lastRefresh: _now, errors: const []);
}

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, placeName: 'Nashville');
}

void main() {
  final year = _now.year;
  final upcoming = [
    _ev('iss:next', SkyEventType.iss, const Duration(hours: 3)),
    _ev('starlink:t', SkyEventType.starlinkTrain, const Duration(days: 2)),
    _ev('meteor-GEM:$year', SkyEventType.meteorShower, const Duration(days: 20)),
  ];
  final log = SkyLog.from([
    for (var i = 0; i < 3; i++)
      Sighting(eventId: 'iss:$i', seen: true, at: _now.subtract(Duration(days: 10 - i)), type: SkyEventType.iss),
  ], onboardedAt: _now.subtract(const Duration(days: 20)));

  Future<void> board(WidgetTester t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [homeProvider.overrideWith(() => _Home(upcoming)), settingsProvider.overrideWith(_Settings.new)],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: BadgeBoard(log: log))),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('a patch for every badge, earned or not; secrets are question marks; progress under levelled ones', (t) async {
    await board(t);
    for (final id in ['looked-up', 'first-light', 'station-spotter', 'train-spotter', 'planet-set', 'up-past-three']) {
      expect(find.byKey(Key('patch-$id')), findsOneWidget, reason: id);
    }
    final station = find.byKey(const Key('patch-station-spotter'));
    expect(find.descendant(of: station, matching: find.text('3 of 5')), findsOneWidget);
    final secret = find.byKey(const Key('patch-up-past-three'));
    expect(find.descendant(of: secret, matching: find.text('???')), findsOneWidget);
    expect(find.text('Up past three'), findsNothing, reason: 'a secret stays a riddle');
    expect(find.textContaining('°'), findsNothing, reason: 'words, not degrees');
  });

  testWidgets('this season: the Geminids with their best night and a countdown', (t) async {
    await board(t);
    final row = find.byKey(Key('season-season-GEM-$year'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Geminids $year')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('days')), findsOneWidget);
  });

  testWidgets('a tap opens the patch: how to earn it, how close, and the next real chance over you', (t) async {
    await board(t);
    await t.tap(find.byKey(const Key('patch-station-spotter')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    final sheet = find.byKey(const Key('badge-sheet-station-spotter'));
    expect(find.descendant(of: sheet, matching: find.text('Station spotter · Bronze')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('3 of 5 for silver')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('Next chance over Nashville')), findsOneWidget);
  });

  testWidgets('a secret\'s sheet gives only its riddle and no hint', (t) async {
    await board(t);
    await t.ensureVisible(find.byKey(const Key('patch-up-past-three')));
    await t.pump(const Duration(milliseconds: 200));
    await t.tap(find.byKey(const Key('patch-up-past-three')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    final sheet = find.byKey(const Key('badge-sheet-up-past-three'));
    expect(find.descendant(of: sheet, matching: find.text('A secret patch')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('staying up very late')), findsOneWidget);
    expect(find.byKey(const Key('badge-next-chance')), findsNothing);
  });
}
