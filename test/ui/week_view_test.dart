import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/kit/kit.dart' show eventStyle;
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/upcoming_screen.dart';

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
        // Went over three nights ago: last week, above tonight.
        recent: [_ev('iss:old', SkyEventType.iss, const Duration(days: -3))],
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

  testWidgets('at a glance: one list, opened on tonight, the first sight picked, tap another', (t) async {
    await pump(t);
    expect(find.text('Calendar'), findsNothing, reason: 'one view now, no calendar');
    expect(find.text('Tonight and ahead'), findsOneWidget);
    // Each night a bar; the first sight still to come is shown below.
    expect(find.bySemanticsLabel(RegExp(r'^(Tonight|This morning|Tomorrow|[A-Z][a-z]+day)')), findsWidgets);
    expect(find.text('ISS flyover'), findsOneWidget);
    await t.ensureVisible(find.bySemanticsLabel(RegExp(r'^Starlink train, ')));
    await t.pump();

    await t.tap(find.bySemanticsLabel(RegExp(r'^Starlink train, ')));
    await t.pump();
    expect(find.text('Starlink train'), findsOneWidget);
    expect(find.text('Alert with LookUp+'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    // The tools are at the end of the list.
    await t.scrollUntilVisible(find.text('Plan a night'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Plan a night'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('last week is a scroll up: faded, with what went over', (t) async {
    await pump(t);
    // Opens on tonight; last week sits above it.
    expect(find.text('Tonight and ahead'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Last week'), -300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Last week'), findsOneWidget);
    final old = find.bySemanticsLabel(RegExp(r'^ISS flyover, '));
    expect(old, findsWidgets);
    await t.ensureVisible(old.first);
    await t.pump();
    await t.tap(old.first);
    await t.pump();
    expect(find.text('Visible if it was clear'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
