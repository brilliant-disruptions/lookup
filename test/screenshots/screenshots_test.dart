// Renders each screen with realistic data to PNG goldens. Run:
//   flutter test --update-goldens test/screenshots
// These are previews, not regression goldens; they are excluded from the
// default `flutter test` run by the `@Tags` below.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/app.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/home_shell.dart';
import 'package:lookup/ui/look_sheet.dart';
import 'package:lookup/ui/onboarding_screen.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/demo.dart';
import 'dart:math' as math;
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/ui/finder_screen.dart';
import 'package:lookup/ui/log_screen.dart';
import 'package:lookup/ui/share_card.dart';
import 'package:lookup/services/plus_service.dart';
import 'dart:convert';
import 'package:lookup/domain/finder/pointing.dart';
import 'package:lookup/domain/log/year_review.dart';
import 'package:lookup/domain/satellites/crew.dart';
import 'package:lookup/state/sky_extras.dart';
import 'package:lookup/ui/finder_camera.dart';
import 'package:lookup/ui/places_screen.dart';
import 'package:lookup/ui/satellites_screen.dart';
import 'package:lookup/ui/year_card.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/tonight.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/sky/object_sheet.dart';
import 'package:lookup/ui/sky/sky_screen.dart';
import 'package:lookup/ui/sky/sky_thing.dart';
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/fancy/starfield.dart';
import 'package:lookup/ui/upcoming_screen.dart';

final _now = DateTime.now();

SkyEvent _ev(String id, SkyEventType type, Duration fromNow,
        {double el = 62, Duration len = const Duration(minutes: 4, seconds: 10),
        double rise = 247, double peakAz = 190, double setAz = 95, int clouds = 8,
        Map<String, Object?> details = const {}}) =>
    SkyEvent(
      id: id,
      type: type,
      start: _now.toUtc().add(fromNow),
      peak: _now.toUtc().add(fromNow + Duration(seconds: len.inSeconds ~/ 2)),
      end: _now.toUtc().add(fromNow + len),
      peakElevationDeg: el,
      riseAzimuthDeg: rise,
      peakAzimuthDeg: peakAz,
      setAzimuthDeg: setAz,
      cloudCoverPercent: clouds,
      details: details,
    );

final _issOmm = (jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync()) as List).first as Map<String, Object?>;

final _events = [
  _ev('iss:1', SkyEventType.iss, const Duration(hours: 3, minutes: 12),
      details: {'brightness': 'brighter than any star', 'rangeKm': 480, 'omm': _issOmm}),
  _ev('aurora-outlook:1', SkyEventType.auroraOutlook, const Duration(hours: 4),
      len: const Duration(hours: 9), el: 15, rise: 0, peakAz: 0, setAz: 0, clouds: 30,
      details: {'kp': 6.33, 'kpNeeded': 6.0, 'level': 'possible', 'headline': 'Aurora possible tonight'}),
  _ev('starlink-2026-232:1', SkyEventType.starlinkTrain, const Duration(hours: 27, minutes: 40),
      el: 41, rise: 203, peakAz: 150, setAz: 70, clouds: 45,
      details: {'count': 27, 'label': 'Starlink train', 'launch': '2026-232', 'spreadMinutes': 3}),
  _ev('iss:2', SkyEventType.iss, const Duration(hours: 49, minutes: 5),
      el: 34, rise: 290, peakAz: 350, setAz: 60, clouds: 72,
      details: {'brightness': 'as bright as the brightest stars'}),
  _ev('iss:3', SkyEventType.iss, const Duration(days: 3, hours: 2),
      el: 78, rise: 240, peakAz: 160, setAz: 80, clouds: 5,
      details: {'brightness': 'brighter than any star'}),
  _ev('pair:1', SkyEventType.planetPairing, const Duration(days: 4, hours: 13), el: 22, rise: 250, peakAz: 250, setAz: 250, clouds: 15,
      len: const Duration(hours: 1),
      details: {'bodies': ['Moon', 'Jupiter'], 'separation': 2.4, 'when': 'evening', 'label': 'Moon and Jupiter'}),
  _ev('launch:1', SkyEventType.rocketLaunch, const Duration(days: 5, hours: 1), el: 18, rise: 292, peakAz: 292, setAz: 292, clouds: 10,
      len: const Duration(minutes: 6),
      details: {'name': 'Falcon 9 Block 5 | Starlink Group 15-16', 'distanceKm': 214, 'label': 'Rocket launch at twilight'}),
  _ev('transit-moon:1', SkyEventType.issTransit, const Duration(days: 2, hours: 5), el: 47, rise: 142, peakAz: 142, setAz: 142, clouds: 12,
      len: const Duration(milliseconds: 820),
      details: {'body': 'Moon', 'crossingMs': 820, 'travelKm': 12.4, 'travelBearingDeg': 315, 'halfWidthKm': 3.6,
        'siteLat': 36.25, 'siteLon': -86.9, 'rangeKm': 640, 'visibleHere': false}),
  _ev('meteor-LEO:2026', SkyEventType.meteorShower, const Duration(days: 6, hours: 3), el: 55, rise: 95, peakAz: 95, setAz: 95, clouds: 25,
      len: const Duration(hours: 7),
      details: {'shower': 'Leonids', 'perHour': 9, 'moonIllumination': 0.42, 'moonUp': false}),
];

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this.s);
  final LookUpSettings s;
  @override
  Future<LookUpSettings> build() async => s;
}

class _FakePlus implements PlusService {
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

SkyEvent _past(String id, SkyEventType type, Duration ago,
        {double el = 50, int clouds = 10, Map<String, Object?> details = const {}}) =>
    _ev(id, type, -ago, el: el, clouds: clouds, details: {...details, 'past': true});

final _recent = [
  _past('iss:p1', SkyEventType.iss, const Duration(hours: 21), el: 71,
      details: {'brightness': 'brighter than any star'}),
  _past('starlink-x:p2', SkyEventType.starlinkTrain, const Duration(days: 2, hours: 3), el: 38, clouds: 90,
      details: {'count': 27, 'label': 'Starlink train'}),
  _past('iss:p3', SkyEventType.iss, const Duration(days: 4, hours: 1), el: 44,
      details: {'brightness': 'as bright as the brightest stars'}),
];

final _quietEvents = [
  _ev('iss:far', SkyEventType.iss, const Duration(days: 9, hours: 2), el: 58, clouds: 20,
      details: {'brightness': 'brighter than any star', 'lookahead': true}),
];

var _homeEvents = _events;

class _FakeHome extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(
        events: _homeEvents,
        recent: _recent,
        aurora: AuroraSnapshot(fetchedAt: _now.toUtc(), kpNow: 4.33, forecast: const [], ovationProbability: 12),
        lastRefresh: _now.toUtc().subtract(const Duration(minutes: 14)),
        errors: const [],
      );
  @override
  Future<void> refresh({bool force = false}) async {}
}

Future<void> _loadFonts() async {
  final cache = Directory('/opt/flutter/bin/cache/artifacts/material_fonts');
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  await load('Roboto', [
    '${cache.path}/Roboto-Regular.ttf',
    '${cache.path}/Roboto-Medium.ttf',
    '${cache.path}/Roboto-Bold.ttf',
    '${cache.path}/Roboto-Black.ttf',
  ]);
  await load('MaterialIcons', ['${cache.path}/MaterialIcons-Regular.otf']);
  // App-bundled fonts (pubspec `fonts:`) are not auto-loaded by flutter_test.
  await load('Cormorant', [
    'assets/fonts/CormorantGaramond-Variable.ttf',
    'assets/fonts/CormorantGaramond-Italic-Variable.ttf',
  ]);
  await load('SplineMono', ['assets/fonts/SplineSansMono-Variable.ttf']);
  final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) await load('Noto Color Emoji', [emoji.path]);
}

Widget _app(Widget home, {LookUpSettings settings = const LookUpSettings(
  latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, isPlus: true)}) {
  final base = LookUpApp.theme;
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: const ['Noto Color Emoji']),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto', fontFamilyFallback: const ['Noto Color Emoji']),
  );
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettings(settings)),
      homeProvider.overrideWith(_FakeHome.new),
      clockProvider.overrideWith((_) => Stream.value(_now)),
      plusServiceProvider.overrideWithValue(_FakePlus()),
      skyLogProvider.overrideWith((_) async => _log),
      yearReviewProvider.overrideWith((_) async => YearReview.from(_sightings, _now.year, utcOffsetMinutes: _now.timeZoneOffset.inMinutes)),
      crewProvider.overrideWith((_) async => {
            Station.iss: const [
              CrewMember('Pyotr Dubrov', 'Commander', 'RFSA'),
              CrewMember('Anil Menon', 'Flight Engineer', 'NASA'),
              CrewMember('Joshua Kutryk', 'Flight Engineer', 'CSA'),
              CrewMember('Luke Delaney', 'Flight Engineer', 'NASA'),
              CrewMember('Sergey Teteryatnikov', 'Flight Engineer', 'RFSA'),
              CrewMember('Anna Kikina', 'Flight Engineer', 'RFSA'),
              CrewMember('Jessica Watkins', 'Flight Engineer', 'NASA'),
            ],
          }),
      alertsEnabledProvider.overrideWith((_) async => true),
      brightTonightProvider.overrideWith((_) async => _satellites),
      weatherProvider.overrideWith((_) async => _clearThenCloudy),
      skyCatalogProvider.overrideWith((_) async => _catalog),
    ],
    child: MaterialApp(theme: theme, debugShowCheckedModeBanner: false, home: home),
  );
}

final _catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
    jsonDecode(File('assets/sky/constellations.json').readAsStringSync()));

/// Clear evening, clouds after midnight.
final _clearThenCloudy = CloudForecast(
  latitude: 36.17,
  longitude: -86.78,
  fetchedAt: _now.toUtc(),
  hourly: [
    for (var h = -2; h < 30; h++)
      CloudSample(
        time: DateTime.utc(_now.toUtc().year, _now.toUtc().month, _now.toUtc().day, _now.toUtc().hour).add(Duration(hours: h)),
        coverPercent: h < 7 ? 8 : (h < 9 ? 45 : 85),
      ),
  ],
);

final _satellites = [
  _ev('sat:20580:1', SkyEventType.satellitePass, const Duration(hours: 2, minutes: 4), el: 48, rise: 225, peakAz: 160, setAz: 95,
      len: const Duration(minutes: 5, seconds: 30), details: {'name': 'Hubble Space Telescope', 'magnitude': 1.1}),
  _ev('sat:22285:1', SkyEventType.satellitePass, const Duration(hours: 2, minutes: 31), el: 71, rise: 190, peakAz: 270, setAz: 10,
      len: const Duration(minutes: 6), details: {'name': 'Zenit rocket stage', 'magnitude': 1.9}),
  _ev('sat:61047:1', SkyEventType.satellitePass, const Duration(hours: 3, minutes: 50), el: 39, rise: 320, peakAz: 30, setAz: 100,
      len: const Duration(minutes: 4, seconds: 50), details: {'name': 'BlueBird 3 (AST SpaceMobile)', 'magnitude': 0.6}),
  _ev('sat:27386:1', SkyEventType.satellitePass, const Duration(hours: 10, minutes: 12), el: 63, rise: 200, peakAz: 110, setAz: 20,
      len: const Duration(minutes: 5), details: {'name': 'Envisat', 'magnitude': 2.6}),
];

final _sightings = [
  for (var i = 0; i < 6; i++)
    Sighting(eventId: 'iss:$i', seen: true, at: _now.toUtc().subtract(Duration(days: 40 - i * 5)),
        type: SkyEventType.iss, peakElevationDeg: i == 2 ? 81 : 46, magnitude: i == 3 ? -3.7 : -2.4, place: 'Nashville',
        eventTime: _now.toUtc().subtract(Duration(days: 40 - i * 5))),
  Sighting(eventId: 'starlink-2026-232:1', seen: true, at: _now.toUtc().subtract(const Duration(days: 9)),
      type: SkyEventType.starlinkTrain, peakElevationDeg: 38, place: 'Nashville', eventTime: _now.toUtc().subtract(const Duration(days: 9))),
  Sighting(eventId: 'pair:x', seen: true, at: _now.toUtc().subtract(const Duration(days: 3)),
      type: SkyEventType.planetPairing, peakElevationDeg: 22, place: 'Nashville', eventTime: _now.toUtc().subtract(const Duration(days: 3))),
  Sighting(eventId: 'iss:no', seen: false, at: _now.toUtc().subtract(const Duration(days: 2)), type: SkyEventType.iss, reason: 'clouds'),
];

final _log = SkyLog.from(_sightings);

/// Device->world rotation (row-major) for a camera pointing at magnetic
/// azimuth [az], elevation [el], phone upright.
List<double> _pose(double az, double el) {
  final a = az * math.pi / 180, e = el * math.pi / 180;
  final v = [math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e)];
  final z = [-v[0], -v[1], -v[2]];
  final y = [-math.sin(a) * math.sin(e), -math.cos(a) * math.sin(e), math.cos(e)];
  final x = [y[1] * z[2] - y[2] * z[1], y[2] * z[0] - y[0] * z[2], y[0] * z[1] - y[1] * z[0]];
  return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
}

void main() {
  setUpAll(_loadFonts);

  Future<void> mount(WidgetTester tester, Widget w, {LookUpSettings? settings}) async {
    tester.view.physicalSize = const Size(1179, 2556); // iPhone 15 Pro
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(settings == null ? _app(w) : _app(w, settings: settings));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 900)); // let staggered rises settle
  }

  Future<void> shot(WidgetTester tester, Widget w, String name, {LookUpSettings? settings}) async {
    await mount(tester, w, settings: settings);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    // Flush staggered-entrance and provider retry timers before teardown.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
  }

  testWidgets('onboarding', (t) => shot(t, const OnboardingScreen(), '1-onboarding'));

  testWidgets('now', (t) => shot(t, const HomeShell(), '2-now'));

  testWidgets('quiet week', (t) async {
    _homeEvents = _quietEvents;
    addTearDown(() => _homeEvents = _events);
    await shot(t, const HomeShell(), '2b-quiet-week');
  });

  testWidgets('demo mid-pass', (t) async {
    // Real start chosen so _now sits ~95 s into the simulated pass.
    final realStart = _now.subtract(const Duration(seconds: demoLeadSeconds + 95));
    final sheet = Scaffold(
      body: Stack(children: [
        const HomeShell(),
        Container(color: Colors.black54),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: const Color(0xFF0E0F11),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: LookSheet(event: demoEvent(realStart), demo: true),
            ),
          ),
        ),
      ]),
    );
    await shot(t, sheet, '7-demo');
  });

  testWidgets('upcoming', (t) async {
    await mount(t, const HomeShell());
    await t.tap(find.text('Week'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 1200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/3-upcoming.png'));
  });

  testWidgets('look sheet', (t) async {
    final sheet = Scaffold(
      body: Stack(children: [
        const HomeShell(),
        Container(color: Colors.black54),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: const Color(0xFF0E0F11),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: LookSheet(event: _events.first),
            ),
          ),
        ),
      ]),
    );
    await shot(t, sheet, '4-look-sheet');
  });

  testWidgets('paywall', (t) async {
    final sheet = Scaffold(
      body: Stack(children: [
        const HomeShell(),
        Container(color: Colors.black54),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: const Color(0xFF0E0F11),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.only(top: 22),
              child: PaywallSheet(reason: _events[2]),
            ),
          ),
        ),
      ]),
    );
    await shot(t, sheet, '6-paywall',
        settings: const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true));
  });

  testWidgets('settings', (t) async {
    await mount(t, const HomeShell());
    await t.tap(find.byTooltip('Settings'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/5-settings.png'));
  });

  testWidgets('finder', (t) async {
    final target = _events.firstWhere((e) => e.type == SkyEventType.rocketLaunch); // WNW, low
    await mount(t, FinderScreen(event: target, orientationStream: Stream.value(_pose(275, 10))));
    await t.pump(const Duration(milliseconds: 50));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/8-finder.png'));
  });

  testWidgets('log', (t) => shot(t, const LogScreen(), '9-log'));

  testWidgets('share cards', (t) async {
    final cards = Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            SizedBox(width: 300, child: ShareCard(event: _recent.first, mode: ShareMode.sawIt, place: 'Nashville')),
            const SizedBox(height: 20),
            SizedBox(width: 300, child: ShareCard(event: _events.first, mode: ShareMode.invite, place: 'Nashville')),
          ]),
        ),
      ),
    );
    await shot(t, cards, '10-share-cards');
  });

  Widget sheetOver(Widget child) => Scaffold(
        body: Stack(children: [
          const HomeShell(),
          Container(color: Colors.black54),
          Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: const Color(0xFF0E0F11),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Padding(padding: const EdgeInsets.only(top: 22), child: child),
            ),
          ),
        ]),
      );

  testWidgets('transit', (t) async {
    await shot(t, sheetOver(LookSheet(event: _events.firstWhere((e) => e.type == SkyEventType.issTransit))), '11-transit');
  });

  testWidgets('satellites tonight', (t) => shot(t, const SatellitesTonightScreen(), '12-satellites'));

  testWidgets('places', (t) => shot(t, const PlacesScreen(), '13-places',
      settings: const LookUpSettings(onboarded: true, isPlus: true)
          .usePlace(const SavedPlace(name: 'Home', latitude: 36.1659, longitude: -86.7844))
          .usePlace(const SavedPlace(name: 'Cabin in the Smokies', latitude: 35.6118, longitude: -83.4895))
          .usePlace(const SavedPlace(name: 'Home', latitude: 36.1659, longitude: -86.7844))));

  testWidgets('year card', (t) async {
    final r = YearReview.from(_sightings, _now.year, utcOffsetMinutes: _now.timeZoneOffset.inMinutes)!;
    await shot(t, Scaffold(body: Center(child: SizedBox(width: 320, child: YearCard(r)))), '14-year-card');
  });

  testWidgets('camera overlay', (t) async {
    // A dusk sky stands in for the camera feed.
    final path = [
      for (var i = 0; i <= 25; i++)
        (t: _now.toUtc().add(Duration(seconds: i * 10)),
         d: SkyDir(245 - i * 4.4, 8 + 42 * math.sin(i / 25 * math.pi))),
    ];
    final r = _pose(195, 24);
    await shot(
      t,
      Scaffold(
        body: Stack(children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF02040A), Color(0xFF0B1A33), Color(0xFF2C3E5C), Color(0xFF6E5A4A)],
                  stops: [0, 0.45, 0.8, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) => CustomPaint(
                painter: SkyOverlayPainter(
                  r: r,
                  declinationDeg: 0,
                  target: path[12].d,
                  path: path,
                  now: path[12].t,
                  onTarget: false,
                  previewHeightPx: c.maxHeight,
                  labelStyle: Theme.of(context).textTheme.labelSmall!,
                ),
              ),
            ),
          ),
        ]),
      ),
      '15-camera-overlay',
    );
  });

  // App Store set: 6.9" (1320×2868), caption above a framed screen.
  Widget framed(String title, String sub, Widget screen) => Scaffold(
        backgroundColor: Colors.black,
        body: Builder(
          builder: (context) => Column(children: [
            const SizedBox(height: 70),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(title, textAlign: TextAlign.center,
                  style: displaySerif(context, size: 40, weight: FontWeight.w600, height: 1.05)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Text(sub, textAlign: TextAlign.center,
                  style: const TextStyle(color: LookUpColors.grey, fontSize: 16, height: 1.35)),
            ),
            const SizedBox(height: 26),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(34, 0, 34, 0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(44)),
                    border: Border.all(color: const Color(0x553C9DFF), width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(42)),
                    child: FittedBox(
                      fit: BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 393,
                        height: 852,
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              size: const Size(393, 852), padding: const EdgeInsets.only(top: 54, bottom: 30)),
                          child: screen,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );

  Future<void> storeShot(WidgetTester tester, String name, String title, String sub, Widget screen) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(framed(title, sub, screen)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/appstore/$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
  }

  testWidgets('appstore 1 now', (t) => storeShot(t, '1-now', 'Step outside\nright now.',
      'A tap ten minutes before the space station flies over you.', const HomeShell()));

  testWidgets('appstore 2 look', (t) => storeShot(t, '2-look', 'Know exactly\nwhere to look.',
      'Plain directions, a live countdown and who\'s aboard.', sheetOver(LookSheet(event: _events.first))));

  testWidgets('appstore 3 camera', (t) async {
    final path = [
      for (var i = 0; i <= 25; i++)
        (t: _now.toUtc().add(Duration(seconds: i * 10)),
         d: SkyDir(245 - i * 4.4, 8 + 42 * math.sin(i / 25 * math.pi))),
    ];
    await storeShot(
      t,
      '3-camera',
      'See its path\nover your sky.',
      'Hold up your phone: the pass is drawn on the real sky.',
      Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF02040A), Color(0xFF0B1A33), Color(0xFF2C3E5C), Color(0xFF6E5A4A)],
                stops: [0, 0.45, 0.8, 1],
              ),
            ),
          ),
        ),
        const Positioned.fill(child: Starfield(density: 0.0005, maxOpacity: 0.7)),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, c) => CustomPaint(
              painter: SkyOverlayPainter(
                r: _pose(195, 24),
                declinationDeg: 0,
                target: path[12].d,
                path: path,
                now: path[12].t,
                onTarget: false,
                previewHeightPx: c.maxHeight,
                labelStyle: Theme.of(context).textTheme.labelSmall!,
              ),
            ),
          ),
        ),
      ]),
    );
  });

  testWidgets('appstore 4 transit', (t) => storeShot(t, '4-transit', 'Catch the station\ncrossing the Moon.',
      'Under a second long. LookUp tells you where to stand.',
      sheetOver(LookSheet(event: _events.firstWhere((e) => e.type == SkyEventType.issTransit)))));

  testWidgets('appstore 5 satellites', (t) => storeShot(t, '5-satellites', 'Hubble and friends,\ntonight.',
      'The brightest satellites crossing your sky.', const SatellitesTonightScreen()));

  testWidgets('appstore 6 upcoming', (t) => storeShot(t, '6-upcoming', 'Every good night\nin one list.',
      'Starlink trains, meteor showers, eclipses, launches, aurora.', const UpcomingScreen()));

  testWidgets('appstore 7 log', (t) => storeShot(t, '7-log', 'Remember\nwhat you saw.',
      'A sky log with badges, photos and your year in review.', const LogScreen()));

  testWidgets('sky tab', (t) => shot(t, const SkyScreen(), '16-sky'));

  testWidgets('object sheet', (t) async {
    final sky = planetsTonight(now: _now.toUtc(), lat: 36.17, lon: -86.78, darkness: SkyDarkness.suburbs);
    final saturn = SkyThing.planet(sky.firstWhere((p) => p.planet == Planet.saturn), 36.17, -86.78);
    await shot(t, sheetOver(ObjectSheet(thing: saturn)), '17-object');
  });

  testWidgets('appstore 0 sky', (t) => storeShot(t, '0-sky', 'Everything\nin your sky.',
      'Planets, constellations and the Moon, with whether you\'ll see them tonight.', const SkyScreen()));
}
