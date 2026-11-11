import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/week_view.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/kit/kit.dart' show eventStyle;
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/upcoming_screen.dart';
import 'package:lookup/ui/week_views.dart' show CalendarPage;

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async =>
      const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true);
}

final _now = DateTime.now().toUtc();

/// The next 9 PM local that's still ahead, so every sight below sits on
/// one known night whatever time the test runs.
final _base = () {
  final l = DateTime.now();
  final today9 = DateTime(l.year, l.month, l.day, 21);
  return (l.isBefore(today9.subtract(const Duration(hours: 1))) ? today9 : DateTime(l.year, l.month, l.day + 1, 21)).toUtc();
}();

SkyEvent _ev(String id, SkyEventType type, Duration from, [Map<String, Object?> details = const {}]) => SkyEvent(
      id: id,
      type: type,
      start: _base.add(from),
      peak: _base.add(from + const Duration(minutes: 2)),
      end: _base.add(from + const Duration(minutes: 5)),
      peakElevationDeg: 50,
      riseAzimuthDeg: 250,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 90,
      details: details,
    );

class _Home extends HomeNotifier {
  _Home({this.satellitesMissing = false});
  final bool satellitesMissing;

  @override
  Future<HomeData> build() async => HomeData(
        events: [
          _ev('iss:a', SkyEventType.iss, Duration.zero, const {'brightness': 'brighter than any star'}),
          _ev('transit:a', SkyEventType.issTransit, const Duration(minutes: 30), const {'body': 'Moon'}),
          _ev('starlink:a', SkyEventType.starlinkTrain, const Duration(days: 2), const {'label': 'Starlink train', 'count': 24}),
          _ev('tiangong:a', SkyEventType.tiangong, const Duration(days: 3)),
          _ev('pair:a', SkyEventType.planetPairing, const Duration(days: 4),
              const {'bodies': ['Venus', 'the Moon'], 'label': 'Venus and the Moon'}),
        ],
        aurora: null,
        lastRefresh: _now,
        errors: const [],
        satellitesMissing: satellitesMissing,
      );
  @override
  Future<void> refresh({bool force = false, bool quick = false}) async {}
}

void main() {
  Future<void> pump(WidgetTester t, {bool satellitesMissing = false}) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        homeProvider.overrideWith(() => _Home(satellitesMissing: satellitesMissing)),
        clockProvider.overrideWith((_) => Stream.value(DateTime.now())),
      ],
      child: MaterialApp(theme: buildLookUpTheme(), home: const UpcomingScreen()),
    ));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  // A week with no flyovers must say why when it's our missing data, not
  // an empty sky, and stay quiet when the data is there.
  testWidgets('says satellite passes are on their way only while orbit data is missing', (t) async {
    const note = 'Satellite passes will appear once we can reach the tracking data.';
    await pump(t, satellitesMissing: true);
    expect(find.text(note), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await pump(t);
    expect(find.text(note), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('at a glance, each marker says what it is: which satellite, which planets', (t) async {
    await pump(t);
    for (final name in ['ISS', 'ISS × Moon', 'Starlink', 'Tiangong', 'Venus · Moon']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    expect(eventStyle(SkyEventType.tiangong).color, isNot(eventStyle(SkyEventType.iss).color));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('at a glance: the week on one screen, the first sight picked, tap another', (t) async {
    await pump(t);
    expect(find.text('At a glance'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    // Seven nights, each a bar; the first sight is shown below.
    expect(find.bySemanticsLabel(RegExp(r'^(Tonight|This morning|Tomorrow|[A-Z][a-z]+day)')), findsWidgets);
    expect(find.text('ISS flyover'), findsOneWidget);
    expect(find.text('Plan a night'), findsOneWidget);

    await t.tap(find.bySemanticsLabel(RegExp(r'^Starlink train, ')));
    await t.pump();
    expect(find.text('Starlink train'), findsOneWidget);
    expect(find.text('Alert with LookUp+'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the glider slides to the calendar, which shows the same night', (t) async {
    await pump(t);
    await t.tap(find.bySemanticsLabel(RegExp(r'^Starlink train, ')));
    await t.pump();
    await t.tap(find.text('Calendar'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
    // The Starlink night is picked there too, with its sights listed.
    expect(find.text('Starlink train'), findsOneWidget);
    expect(find.text('Two weeks'), findsOneWidget);
    // The key names only the dots on the calendar: the ISS and Tiangong
    // apart, and nothing for meteors when there are none.
    Finder key(String label) => find.descendant(of: find.byType(CalendarPage), matching: find.text(label));
    for (final label in ['ISS', 'Starlink', 'Tiangong', 'Planets']) {
      expect(key(label), findsOneWidget, reason: label);
    }
    expect(key('Meteors'), findsNothing);
    expect(key('Stations'), findsNothing);
    expect(t.takeException(), isNull);

    // Back to the ISS's night by tapping its day: the ISS and the
    // transit's "Also" line.
    final night = nightOf(_base);
    await t.tap(find.bySemanticsLabel(RegExp('^[A-Z][a-z]{2}, [A-Z][a-z]{2} ${night.day}:')).first);
    await t.pump();
    expect(find.text('ISS flyover'), findsOneWidget);
    expect(find.textContaining('Also: '), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
