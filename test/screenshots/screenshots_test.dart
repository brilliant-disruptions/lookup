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
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/app.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/home_shell.dart';
import 'package:lookup/ui/caught_it_screen.dart';
import 'package:lookup/ui/intro_scene.dart';
import 'package:lookup/ui/look_sheet.dart';
import 'package:lookup/ui/look_up_now_screen.dart';
import 'package:lookup/services/alert_art.dart';
import 'package:lookup/ui/starter_card.dart';
import 'package:lookup/ui/kit/kit.dart' show SkyBackdrop;
import 'package:lookup/ui/onboarding_screen.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/demo.dart';
import 'dart:math' as math;
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
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
import 'package:lookup/state/plan_state.dart';
import 'package:lookup/domain/plan/night_plan.dart';
import 'package:lookup/ui/finder_camera.dart';
import 'package:lookup/ui/places_screen.dart';
import 'package:lookup/ui/plan_screen.dart';
import 'package:lookup/ui/where_to_go_screen.dart';
import 'package:lookup/ui/favourites_screen.dart';
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
import 'package:lookup/ui/kit/starfield.dart';
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

/// A real pass from the fixture's elements (London, 21 Oct 2026), under the
/// id the sample log has as its 5th station sighting, so "You caught it"
/// shows the badge and who else was under it.
SkyEvent _londonPass() {
  final e = PassPredictor(latitude: 51.5, longitude: -0.12)
      .predict(
        record: OmmRecord.fromJson(_issOmm),
        type: SkyEventType.iss,
        from: DateTime.utc(2026, 10, 20, 16),
        to: DateTime.utc(2026, 10, 22),
        minPeakElevationDeg: 10,
      )
      .first;
  return SkyEvent(
    id: 'iss:4',
    type: e.type,
    start: e.start,
    peak: e.peak,
    end: e.end,
    peakElevationDeg: e.peakElevationDeg,
    riseAzimuthDeg: e.riseAzimuthDeg,
    peakAzimuthDeg: e.peakAzimuthDeg,
    setAzimuthDeg: e.setAzimuthDeg,
    details: {...e.details, 'past': true},
  );
}

const _london = LookUpSettings(latitude: 51.5, longitude: -0.12, placeName: 'London', onboarded: true, toured: true);

/// A good evening for the verdict: a clear pass an hour out going right by
/// Saturn, clear until late, the Moon setting before midnight. Times follow
/// the clock it's rendered at, so render it in an evening time zone (e.g.
/// TZ=Asia/Kolkata in the UTC afternoon).
({NightPlan plan, List<SkyEvent> events}) _evening() {
  final now = DateTime.now().toUtc();
  final start = now.subtract(const Duration(minutes: 30));
  final end = start.add(const Duration(hours: 10));
  final hour = DateTime.utc(start.year, start.month, start.day, start.hour);
  final weather = CloudForecast(
    latitude: 36.17,
    longitude: -86.78,
    fetchedAt: now,
    hourly: [for (var i = -1; i <= 11; i++) CloudSample(time: hour.add(Duration(hours: i)), coverPercent: i < 6 ? 6 : 82)],
  );
  return (
    plan: NightPlan(
      window: (start: start, end: end),
      outlook: NightOutlook.from(start: start, end: end, weather: weather),
      planets: [
        PlanetTonight(
          planet: Planet.saturn,
          magnitude: 0.6,
          elongationDeg: 120,
          evening: true,
          sighting: SkySighting(best: now.add(const Duration(minutes: 25)), altDeg: 38, azDeg: 140, verdict: Seeability.great),
        ),
      ],
      moon: MoonTonight(phase: MoonPhase.waxingCrescent, illumination: 0.38, waxing: true, set: now.add(const Duration(hours: 2, minutes: 20))),
      constellations: const [],
      showpieces: const [],
      darkness: SkyDarkness.suburbs,
    ),
    events: [
      _ev('iss:v', SkyEventType.iss, const Duration(hours: 1, minutes: 5), clouds: 6,
          details: {'brightness': 'brighter than any star', 'landmarks': 'passing right by Saturn'}),
      ..._events.skip(1),
    ],
  );
}

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
  await load('Inter', ['assets/fonts/InterVariable.ttf']);
  final emoji = File('/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf');
  if (emoji.existsSync()) await load('Noto Color Emoji', [emoji.path]);
}

Widget _app(Widget home, {LookUpSettings settings = const LookUpSettings(
  latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, isPlus: true, toured: true,
  favourites: ['planet:saturn', 'm31', 'con:Ori', 'planet:venus']), List<Override> extra = const []}) {
  final base = LookUpApp.theme;
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamilyFallback: const ['Noto Color Emoji']),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamilyFallback: const ['Noto Color Emoji']),
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
      // Saved places away from Nashville stay clear all night.
      placeForecastProvider.overrideWith((ref, at) async =>
          (at.lat - 36.17).abs() < 0.2 && (at.lon + 86.78).abs() < 0.2 ? _clearThenCloudy : _clear(at.lat, at.lon)),
      skyCatalogProvider.overrideWith((_) async => _catalog),
      // Isolate.run doesn't finish under the test clock; plan the nights here.
      nightsAheadProvider.overrideWith((_) async => [
            for (var i = 0; i < nightsAhead; i++)
              planNight(catalog: _catalog, at: _now.toUtc().add(Duration(days: i)), lat: 36.17, lon: -86.78,
                  darkness: SkyDarkness.suburbs, weather: _clearThenCloudy),
          ]),
      ...extra,
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

CloudForecast _clear(double lat, double lon) => CloudForecast(
      latitude: lat,
      longitude: lon,
      fetchedAt: _now.toUtc(),
      hourly: [
        for (var h = -2; h < 30; h++)
          CloudSample(
            time: DateTime.utc(_now.toUtc().year, _now.toUtc().month, _now.toUtc().day, _now.toUtc().hour).add(Duration(hours: h)),
            coverPercent: 5,
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

  Future<void> mount(WidgetTester tester, Widget w, {LookUpSettings? settings, List<Override> extra = const []}) async {
    tester.view.physicalSize = const Size(1179, 2556); // iPhone 15 Pro
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(settings == null ? _app(w, extra: extra) : _app(w, settings: settings, extra: extra));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 900)); // let staggered rises settle
    await tester.pump(const Duration(seconds: 1)); // and ones mounted after async data
  }

  Future<void> shot(WidgetTester tester, Widget w, String name, {LookUpSettings? settings, List<Override> extra = const []}) async {
    await mount(tester, w, settings: settings, extra: extra);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
    // Flush staggered-entrance and provider retry timers before teardown.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
  }

  testWidgets('onboarding', (t) => shot(t, const OnboardingScreen(), '1-onboarding'));

  testWidgets('now', (t) => shot(t, const HomeShell(), '2-now'));

  testWidgets('night vision', (t) => shot(t, const NightVision(enabled: true, child: HomeShell()), '18-night-vision'));

  testWidgets('plan a night', (t) => shot(t, const PlanScreen(), '19-plan',
      settings: const LookUpSettings(
          latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, isPlus: true,
          favourites: ['planet:saturn', 'm31', 'con:Ori', 'planet:venus'],
          places: [SavedPlace(name: 'The cabin', latitude: 35.61, longitude: -83.49, skyDarkness: SkyDarkness.dark)])));

  testWidgets('where to go', (t) => shot(t, const WhereToGoScreen(), '20-where-to-go',
      settings: const LookUpSettings(
          latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, isPlus: true,
          places: [
            SavedPlace(name: 'The cabin', latitude: 35.61, longitude: -83.49, skyDarkness: SkyDarkness.dark),
            SavedPlace(name: 'Percy Priest Lake', latitude: 36.06, longitude: -86.51),
          ])));

  testWidgets('dark skies', (t) async {
    await mount(t, const WhereToGoScreen());
    await t.drag(find.byType(ListView).first, const Offset(0, -200));
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/21-dark-skies.png'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 5));
  });

  testWidgets('tour', (t) async {
    await mount(t, const HomeShell(),
        settings: const LookUpSettings(
            latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, isPlus: true));
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/22-tour-1.png'));
    await t.tap(find.text('Next'));
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 400));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/22-tour-2.png'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 5));
  });

  testWidgets('now, scrolled', (t) async {
    await mount(t, const HomeShell());
    await t.drag(find.byType(ListView).first, const Offset(0, -700));
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/2c-now-more.png'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 5));
  });

  testWidgets('favourites', (t) => shot(t, const FavouritesScreen(), '23-favourites'));

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

  testWidgets('caught it', (t) => shot(
      t,
      CaughtItScreen(
        event: _londonPass(),
        animate: false,
        onAddPhoto: () async {},
      ),
      '24-caught-it',
      settings: _london));

  testWidgets('starter sky', (t) => shot(
      t,
      const Scaffold(
        body: SkyBackdrop(
          child: SafeArea(
            child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Column(children: [StarterSkyCard()])),
          ),
        ),
      ),
      '25-starter-sky',
      settings: const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, toured: true)));

  testWidgets('alert art', (t) async {
    t.view.physicalSize = const Size(1024, 512);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(CustomPaint(size: const Size(1024, 512), painter: _ArtPainter(_events.first)));
    await expectLater(find.byType(CustomPaint), matchesGoldenFile('goldens/26-alert-art.png'));
  });

  testWidgets('look up now', (t) => shot(
      t,
      LookUpNowScreen(
        event: _ev('iss:soon', SkyEventType.iss, const Duration(minutes: 1, seconds: 47),
            details: {'brightness': 'brighter than any star'}),
        // Facing south: it appears west-southwest, to the right.
        orientationStream: Stream.value(const [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0]),
      ),
      '27-look-up-now'));

  // An approximation of the Android widget (res/layout/next_event_widget.xml)
  // for the README: the same picture, scrim, words and colours.
  testWidgets('home widget preview', (t) async {
    t.view.physicalSize = const Size(1080, 1000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final e = _events.first;
    Widget widget(double w, double h) => Container(
          width: w,
          height: h,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x17FFFFFF)),
            gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0B1328), Color(0xFF04060B)]),
          ),
          child: Stack(fit: StackFit.expand, children: [
            FittedBox(fit: BoxFit.cover, child: SizedBox(width: 1024, height: 512, child: CustomPaint(painter: _ArtPainter(e, titled: false)))),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xE604060B), Color(0x9904060B), Color(0x0004060B)]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Next up · Tonight', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: LookUpColors.blue)),
                const SizedBox(height: 2),
                const Text('ISS flyover', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                Text('3:11:58', style: numeric(size: 30, weight: FontWeight.w700)),
                const Spacer(),
                const Text('Tonight, 10:17 PM', style: TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
                const Text('Look west-southwest, high in the sky', style: TextStyle(fontSize: 12.5)),
              ]),
            ),
          ]),
        );
    await t.pumpWidget(_app(Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2B3A55), Color(0xFF1A1F2C)]),
        ),
        child: Center(child: widget(330, 170)),
      ),
    )));
    await t.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/28-home-widget.png'));
  });

  // The verdict on a good evening: a clear pass an hour out, Saturn up, clear
  // until late. Times follow the clock it's rendered at (render it in the
  // evening's time zone, e.g. TZ=Asia/Kolkata in the afternoon UTC).
  testWidgets('verdict', (t) async {
    final e = _evening();
    final saved = _homeEvents;
    _homeEvents = e.events;
    addTearDown(() => _homeEvents = saved);
    await shot(t, const HomeShell(), '29-verdict', extra: [tonightSkyProvider.overrideWith((_) async => e.plan)]);
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
          .usePlace(const SavedPlace(name: 'Cabin in the Smokies', latitude: 35.6118, longitude: -83.4895, skyDarkness: SkyDarkness.dark))
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
  Widget framed(String title, String sub, Widget screen, {Color tint = LookUpColors.blue}) => Scaffold(
        backgroundColor: Colors.black,
        body: Builder(
          builder: (context) => DecoratedBox(
            // Night, not flat black, with the shot's colour glowing behind the phone.
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, 0.15),
                radius: 0.95,
                colors: [tint.withValues(alpha: 0.30), tint.withValues(alpha: 0.06), Colors.transparent],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCC0B1328), Color(0x0004060B)],
                  stops: [0, 0.45],
                ),
              ),
              child: Column(children: [
            const SizedBox(height: 70),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(title, textAlign: TextAlign.center,
                  style: display(38, weight: FontWeight.w700, height: 1.08)),
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
                    border: Border.all(color: const Color(0x33FFFFFF), width: 2),
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
          ),
        ),
      );

  Future<void> storeShot(WidgetTester tester, String name, String title, String sub, Widget screen,
      {Color tint = LookUpColors.blue, LookUpSettings? settings, Future<void> Function(WidgetTester)? act, List<Override> extra = const []}) async {
    tester.view.physicalSize = const Size(1320, 2868);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final framedScreen = framed(title, sub, screen, tint: tint);
    await tester.pumpWidget(settings == null ? _app(framedScreen, extra: extra) : _app(framedScreen, settings: settings, extra: extra));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 900));
    if (act != null) {
      await act(tester);
      await tester.pump(const Duration(seconds: 1));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/appstore/$name.png'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
  }

  // The App Store set, in listing order. The first is the one most people
  // see without swiping, so it's the product's moment: the tap itself.
  testWidgets('appstore 01 alert', (t) => storeShot(t, '01-alert', 'It taps you\nbefore it flies over.',
      'Ten minutes\' warning and which way to face. Quiet when it\'s cloudy.', const _LockScreen()));

  // Rendered with the evening scene, so render it in an evening time zone
  // (TZ=Asia/Kolkata in the UTC afternoon), like the verdict preview.
  testWidgets('appstore 02 now', (t) async {
    final e = _evening();
    final saved = _homeEvents;
    _homeEvents = e.events;
    addTearDown(() => _homeEvents = saved);
    await storeShot(t, '02-now', 'Step outside\nright now.', 'One answer: is tonight worth it, and when to look.', const HomeShell(),
        extra: [tonightSkyProvider.overrideWith((_) async => e.plan)]);
  });

  testWidgets('appstore 03 camera', (t) async {
    final path = [
      for (var i = 0; i <= 25; i++)
        (t: _now.toUtc().add(Duration(seconds: i * 10)),
         d: SkyDir(245 - i * 4.4, 8 + 42 * math.sin(i / 25 * math.pi))),
    ];
    await storeShot(
      t,
      '03-camera',
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
      tint: LookUpColors.cyan,
    );
  });

  testWidgets('appstore 04 caught', (t) => storeShot(t, '04-caught', 'Every sighting,\ncelebrated.',
      'Badges, a card to share, and how many millions were under the same pass.',
      CaughtItScreen(event: _londonPass(), animate: false, onAddPhoto: () async {}),
      settings: _london));

  testWidgets('appstore 05 starter', (t) => storeShot(t, '05-starter', 'Three sights\nto start with.',
      'A pass, a planet and a star pattern, picked from your own sky.', const HomeShell(),
      tint: LookUpColors.gold,
      act: (t) async {
        await t.drag(find.byType(ListView).first, const Offset(0, -370));
        await t.pump(const Duration(milliseconds: 600));
      }));

  testWidgets('appstore 06 sky', (t) => storeShot(t, '06-sky', 'Everything\nin your sky.',
      'Planets, constellations and the Moon, with whether you\'ll see them tonight.', const SkyScreen(),
      tint: LookUpColors.violet));

  testWidgets('appstore 07 look', (t) => storeShot(t, '07-look', 'Know exactly\nwhere to look.',
      'Plain directions, a live countdown and who\'s aboard.', sheetOver(LookSheet(event: _events.first))));

  testWidgets('appstore 08 transit', (t) => storeShot(t, '08-transit', 'Catch the station\ncrossing the Moon.',
      'Under a second long. LookUp tells you where to stand.',
      sheetOver(LookSheet(event: _events.firstWhere((e) => e.type == SkyEventType.issTransit))),
      tint: LookUpColors.cyan));

  testWidgets('appstore 09 satellites', (t) => storeShot(t, '09-satellites', 'Hubble and friends,\ntonight.',
      'The brightest satellites crossing your sky.', const SatellitesTonightScreen(), tint: LookUpColors.cyan));

  testWidgets('appstore 10 upcoming', (t) => storeShot(t, '10-upcoming', 'Every good night\nin one list.',
      'Starlink trains, meteor showers, eclipses, launches, aurora.', const UpcomingScreen(), tint: LookUpColors.violet));

  testWidgets('sky tab', (t) => shot(t, const SkyScreen(), '16-sky'));

  testWidgets('object sheet', (t) async {
    final sky = planetsTonight(now: _now.toUtc(), lat: 36.17, lon: -86.78, darkness: SkyDarkness.suburbs);
    final saturn = SkyThing.planet(sky.firstWhere((p) => p.planet == Planet.saturn), 36.17, -86.78);
    await shot(t, sheetOver(ObjectSheet(thing: saturn)), '17-object');
  });

}

/// A phone's lock screen at dusk: the clock, the station crossing the sky,
/// and LookUp's alert, worded as the real one is. Store art only.
class _LockScreen extends StatelessWidget {
  const _LockScreen();
  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF03060E), Color(0xFF0A1630), Color(0xFF1B2D52), Color(0xFF3A3550)],
              stops: [0, 0.5, 0.85, 1],
            ),
          ),
        ),
        const Starfield(density: 0.0011, maxOpacity: 0.9),
        const Positioned(
          left: 16,
          right: 16,
          bottom: 70,
          height: 430,
          child: IntroScene(animate: false, chrome: false),
        ),
        Positioned(
          top: 82,
          left: 0,
          right: 0,
          child: Column(children: [
            const Text('Thursday, November 5',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xDDF4F6FA))),
            Text('9:55', style: display(96, weight: FontWeight.w700, height: 1.05, color: const Color(0xF2F4F6FA))),
          ]),
        ),
        const Positioned(
          top: 268,
          left: 12,
          right: 12,
          child: AlertBanner(
            type: SkyEventType.iss,
            title: 'ISS flyover in 10 min',
            body: 'Brighter than any star, rising in the west-southwest, high in the sky at its best, 4 min.',
          ),
        ),
        Positioned(
          left: 44,
          right: 44,
          bottom: 40,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final icon in [Icons.flashlight_on_rounded, Icons.photo_camera_rounded])
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: Center(
            child: Container(
              width: 134,
              height: 5,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
      ]);
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.e, {this.titled = true});
  final SkyEvent e;
  final bool titled;
  @override
  void paint(Canvas canvas, Size size) => AlertArt.paint(canvas, e, startLabel: titled ? '9:05 PM' : '10:17 PM', titled: titled);
  @override
  bool shouldRepaint(_ArtPainter old) => false;
}
