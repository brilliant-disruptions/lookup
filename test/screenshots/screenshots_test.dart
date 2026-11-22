// Renders each screen with realistic data to PNG goldens. Run:
//   flutter test --update-goldens test/screenshots
// These are previews, not regression goldens; they are excluded from the
// default `flutter test` run by the `@Tags` below.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/services/refresh_service.dart';
import 'package:lookup/app.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/home_shell.dart';
import 'package:lookup/ui/caught_it_screen.dart';
import 'package:lookup/ui/intro_scene.dart';
import 'package:lookup/ui/look_sheet.dart';
import 'package:lookup/ui/plus_card.dart';
import 'package:lookup/ui/look_up_now_screen.dart';
import 'package:lookup/services/alert_art.dart';
import 'package:lookup/ui/starter_card.dart';
import 'package:lookup/ui/kit/kit.dart' show FloatingTabBar, PipMark, PipMood, SegmentedTabs, SkyBackdrop;
import 'package:lookup/ui/kit/firefly_mark.dart' show fireflyGlow;
import 'package:lookup/ui/onboarding_screen.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/demo.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/ui/finder_screen.dart';
import 'package:lookup/ui/catch_it_screen.dart';
import 'package:lookup/domain/photo/capture_plan.dart';
import 'package:lookup/domain/photo/framing.dart';
import 'package:lookup/services/capture/practice_capture.dart';
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
import 'package:lookup/services/location_service.dart';
import 'package:lookup/services/notification_service.dart';
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

const _london = LookUpSettings(latitude: 51.5, longitude: -0.12, placeName: 'London', onboarded: true, firstBadgeShown: true, toured: true);

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

class _Refresh implements RefreshService {
  int prefetched = 0;
  @override
  Future<void> prefetch() async => prefetched++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakePlus implements PlusService {
  @override
  Stream<String> get errors => const Stream.empty();
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
  Future<void> refresh({bool force = false, bool quick = false}) async {}
}

Future<void> _loadFonts() async {
  final cache = Directory('${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts');
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
  latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, firstBadgeShown: true, isPlus: true, toured: true,
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
      refreshServiceProvider.overrideWithValue(_Refresh()),
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

final _log = SkyLog.from(_sightings, onboardedAt: _now.toUtc().subtract(const Duration(days: 40)));

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

/// The phone's motion sensors have no implementation under `flutter test`.
/// Screens that follow the phone (the Sky panorama, Look up now) would throw
/// MissingPluginException; answer its settings calls and give it a sensor
/// that never reports, so they hold the view each screenshot was composed at.
void _silentRotationSensor() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  m.setMockMethodCallHandler(const MethodChannel('rotation_sensor/method'), (_) async => null);
  m.setMockStreamHandler(const EventChannel('rotation_sensor/orientation'), MockStreamHandler.inline(onListen: (_, _) {}));
  // The rotation sensor watches screen orientation through this one.
  m.setMockMethodCallHandler(const MethodChannel('native_device_orientation'), (_) async => null);
  m.setMockStreamHandler(const EventChannel('native_device_orientation_events'), MockStreamHandler.inline(onListen: (_, _) {}));
}

class _GrantLocation implements LocationService {
  @override
  Future<bool> requestPermission() async => true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _GrantNotifications implements NotificationService {
  @override
  Future<bool> requestPermission() async => true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    _silentRotationSensor();
    await _loadFonts();
  });

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
          latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, firstBadgeShown: true, isPlus: true,
          favourites: ['planet:saturn', 'm31', 'con:Ori', 'planet:venus'],
          places: [SavedPlace(name: 'The cabin', latitude: 35.61, longitude: -83.49, skyDarkness: SkyDarkness.dark)])));

  testWidgets('where to go', (t) => shot(t, const WhereToGoScreen(), '20-where-to-go',
      settings: const LookUpSettings(
          latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, firstBadgeShown: true, isPlus: true,
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

  // The redesign's three moments, then the three tabs.
  testWidgets('onboarding moments', (t) async {
    await mount(t, const OnboardingScreen(),
        settings: const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville'),
        extra: [
          locationServiceProvider.overrideWithValue(_GrantLocation()),
          notificationServiceProvider.overrideWithValue(_GrantNotifications()),
        ]);
    // Follow Pip: a light to tap, Pip asking where you are, then your own sky.
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/40-onboarding-1-welcome.png'));
    await t.tap(find.byKey(const Key('onboarding-wake')));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/40-onboarding-3-tap.png'));
    await t.tap(find.text('Show me my sky'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/40-onboarding-2-sight.png'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 5));
  });

  testWidgets('sky and log tabs', (t) async {
    await mount(t, const HomeShell());
    Finder tab(String l) => find.descendant(of: find.byType(FloatingTabBar), matching: find.text(l));
    await t.tap(tab('Explore'));
    await t.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/41-tab-sky.png'));
    await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/41-tab-sky-more.png'));
    await t.tap(tab('Log'));
    await t.pump(const Duration(seconds: 2));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/42-tab-log.png'));
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
    await t.tap(find.descendant(of: find.byType(FloatingTabBar), matching: find.text('Week')));
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
      settings: const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, firstBadgeShown: true, toured: true)));

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

  testWidgets('plus card', (t) => shot(
      t,
      const Scaffold(
        body: SkyBackdrop(
          child: SafeArea(
            child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Column(children: [PlusNearYouCard()])),
          ),
        ),
      ),
      '30-plus-card',
      settings: const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, firstBadgeShown: true, toured: true)));

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
        settings: const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true, firstBadgeShown: true));
  });

  testWidgets('settings', (t) async {
    await mount(t, const HomeShell());
    await t.tap(find.byTooltip('Settings'));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/5-settings.png'));
  });

  // Press and hold Settings: just night vision, in a dim room (60% red).
  testWidgets('night vision card', (t) async {
    await mount(t, const NightVision(enabled: true, strength: 0.6, child: HomeShell()));
    await t.longPress(find.byTooltip('Settings'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/31-night-vision-card.png'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 5));
  });

  // The card's link: Settings, opened at the Night vision section.
  testWidgets('night vision settings', (t) async {
    await mount(t, const HomeShell());
    await t.longPress(find.byTooltip('Settings'));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('All night vision settings ›'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/32-night-vision-settings.png'));
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 5));
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
      settings: const LookUpSettings(onboarded: true, firstBadgeShown: true, isPlus: true)
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

  // App Store set: ten 6.9" images (1320×2868) cut from one long night
  // sky, so they flow into each other in the store: each phone straddles
  // the edge between two images, and one pass path runs through them all.
  // Each screen is rendered once on its own (with its own settings) and
  // captured, then laid into the panorama.
  testWidgets('appstore set', (t) async {
    final evening = _evening();
    final path = [
      for (var i = 0; i <= 25; i++)
        (t: _now.toUtc().add(Duration(seconds: i * 10)), d: SkyDir(245 - i * 4.4, 8 + 42 * math.sin(i / 25 * math.pi))),
    ];
    final shots = <_StoreShot>[
      const _StoreShot('01-alert', 'It taps you\nbefore it flies over.', 'Ten minutes\' warning and which way to face. Quiet when it\'s cloudy.',
          _LockScreen()),
      _StoreShot('02-home', 'Step outside\nright now.', 'One answer: is tonight worth it, and when to look.', const HomeShell(),
          events: evening.events, extra: [tonightSkyProvider.overrideWith((_) async => evening.plan)]),
      _StoreShot('03-pip', 'Meet Pip.\nIt shows you where.', 'Hold your phone up. Pip flies to it, and a tap catches it.',
          _PipGuides(path: path, pose: _pose(195, 44)), tint: LookUpColors.good),
      _StoreShot('04-caught', 'Every catch,\ncelebrated.', 'A new patch, your picture in Photos, and how many millions were under the same pass.',
          CaughtItScreen(event: _londonPass(), animate: false, onAddPhoto: () async {}),
          settings: _london, tint: LookUpColors.gold),
      _StoreShot('05-patches', 'A patch for\neverything you catch.', 'Levels, collections, seasonal sights and a few secrets.', const LogScreen(),
          tint: LookUpColors.gold, act: (t) async {
        final tab = find.descendant(of: find.byType(SegmentedTabs), matching: find.text('Badges'));
        await t.tap(tab.first);
        await t.pump(const Duration(milliseconds: 600));
        await t.drag(find.byType(ListView).first, const Offset(0, -560));
        await t.pump(const Duration(milliseconds: 800));
      }),
      const _StoreShot('06-explore', 'Everything\nin your sky.', 'Planets, constellations and the Moon, with whether you\'ll see them.',
          SkyScreen(), tint: LookUpColors.violet),
      _StoreShot('07-look', 'Know exactly\nwhere to look.', 'Plain directions, a live countdown and who\'s aboard.',
          sheetOver(LookSheet(event: _events.first))),
      const _StoreShot('08-week', 'Every good night\nin one list.', 'Starlink trains, meteor showers, eclipses, launches, aurora.',
          UpcomingScreen(), tint: LookUpColors.violet),
      _StoreShot('09-transit', 'Catch the station\ncrossing the Moon.', 'Under a second long. LookUp tells you where to stand.',
          sheetOver(LookSheet(event: _events.firstWhere((e) => e.type == SkyEventType.issTransit))), tint: LookUpColors.cyan),
      const _StoreShot('10-satellites', 'Hubble and friends,\ntonight.', 'The brightest satellites crossing your sky.',
          SatellitesTonightScreen(), tint: LookUpColors.cyan),
    ];

    // How Pip feels on each image as it flies through them (eyes only).
    const moods = [
      PipMood.happy, PipMood.curious, PipMood.happy, PipMood.amazed, PipMood.wink,
      PipMood.happy, PipMood.curious, PipMood.happy, PipMood.amazed, PipMood.happy,
    ];

    // 1. Each screen on its own, as a phone shows it, captured.
    final screens = <ui.Image>[];
    for (final s in shots) {
      t.view.physicalSize = const Size(393 * 3, 852 * 3);
      t.view.devicePixelRatio = 3;
      t.view.padding = const FakeViewPadding(top: 54 * 3, bottom: 30 * 3);
      final saved = _homeEvents;
      if (s.events != null) _homeEvents = s.events!;
      const key = Key('store-screen');
      final w = RepaintBoundary(key: key, child: Material(color: Colors.black, child: s.screen));
      await t.pumpWidget(s.settings == null ? _app(w, extra: s.extra) : _app(w, settings: s.settings!, extra: s.extra));
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 900));
      if (s.act != null) {
        await s.act!(t);
        await t.pump(const Duration(seconds: 1));
      }
      final ro = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      screens.add((await t.runAsync(() => ro.toImage(pixelRatio: 3)))!);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(minutes: 5));
      _homeEvents = saved;
    }

    // 2. The panorama, one slice at a time.
    t.view.physicalSize = const Size(1320, 2868);
    t.view.devicePixelRatio = 3;
    t.view.resetPadding();
    addTearDown(t.view.reset);
    for (var i = 0; i < shots.length; i++) {
      await t.pumpWidget(MaterialApp(
        theme: LookUpApp.theme,
        debugShowCheckedModeBanner: false,
        home: _StoreSlice(index: i, shots: shots, screens: screens, moods: moods),
      ));
      await t.pump();
      // Let Pip's feeling ease in.
      await t.pump(const Duration(milliseconds: 700));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/appstore/${shots[i].name}.png'));
    }
  });

  testWidgets('sky tab', (t) => shot(t, const SkyScreen(), '16-sky'));

  testWidgets('object sheet', (t) async {
    final sky = planetsTonight(now: _now.toUtc(), lat: 36.17, lon: -86.78, darkness: SkyDarkness.suburbs);
    final saturn = SkyThing.planet(sky.firstWhere((p) => p.planet == Planet.saturn), 36.17, -86.78);
    await shot(t, sheetOver(ObjectSheet(thing: saturn)), '17-object');
  });

  // Catch it, over a real pass (London, 23 Oct 2026, nearly overhead).
  // Render with TZ=Europe/London so the times are London's.
  group('catch it', () {
    final pass = PassPredictor(latitude: 51.5, longitude: -0.12)
        .predict(
          record: OmmRecord.fromJson(_issOmm),
          type: SkyEventType.iss,
          from: DateTime.utc(2026, 10, 23, 4),
          to: DateTime.utc(2026, 10, 23, 6),
          minPeakElevationDeg: 10,
        )
        .first;
    final path = passPath(pass, 51.5, -0.12);
    final plan = planCapture(path: path, magnitude: typicalMagnitude(pass), caps: practiceCaps, siteSqm: 19.8,
        sunAltDeg: sunHorizontal(pass.peak, 51.5, -0.12).altitudeDeg)!;
    _ShotCamera camera() => _ShotCamera(path: path, magnitude: typicalMagnitude(pass), latDeg: 51.5, lonDeg: -0.12, catalog: _catalog);

    Future<void> catchShot(WidgetTester t, Widget w, String name, {Future<void> Function(WidgetTester)? act}) async {
      // LOOKUP_SMALL=1 renders at a small phone's size (375×667 pt, an
      // iPhone SE) into goldens/small/, to check nothing is clipped there.
      final small = Platform.environment['LOOKUP_SMALL'] == '1';
      if (small) name = 'small/$name';
      t.view.physicalSize = small ? const Size(750, 1334) : const Size(1179, 2556);
      t.view.devicePixelRatio = small ? 2 : 3;
      if (small) t.view.padding = const FakeViewPadding(top: 40);
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(w, settings: _london));
      // Stacking runs on the test clock; decoding pictures needs real time.
      for (var i = 0; i < 60; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump(const Duration(milliseconds: 50));
      }
      if (act != null) {
        await act(t);
        for (var i = 0; i < 10; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 100));
        }
      }
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(minutes: 5));
    }

    // Aiming: a little right of the spot, so it says which way to turn.
    final c = plan.framing.center;
    final aimPose = levelPose(SkyDir(c.azimuthDeg + 11, c.elevationDeg - 3));

    testWidgets('aim', (t) => catchShot(
        t,
        CatchItScreen(
          event: pass,
          backend: camera(),
          orientationStream: Stream.value(aimPose),
          clock: () => pass.start.subtract(const Duration(minutes: 3, seconds: 20)),
        ),
        '30-catch-aim'));

    testWidgets('capturing', (t) => catchShot(
        t,
        CatchItScreen(
          event: pass,
          backend: camera(),
          clock: () => plan.startAt.add(plan.length * 0.55),
          debug: const CatchItDebug(phase: CatchPhase.capturing, progress: 0.55),
        ),
        '31-catch-capturing'));

    testWidgets('caught', (t) => catchShot(
        t,
        CatchItScreen(
          event: pass,
          backend: camera(),
          clock: () => plan.stopAt,
          debug: const CatchItDebug(phase: CatchPhase.done, progress: 1),
        ),
        '32-catch-done'));

    testWidgets('camera settings', (t) => catchShot(
        t,
        CatchItScreen(
          event: pass,
          backend: camera(),
          orientationStream: Stream.value(levelPose(c)),
          clock: () => pass.start.subtract(const Duration(minutes: 3, seconds: 20)),
        ),
        '33-catch-settings',
        act: (t) async {
          await t.tap(find.byTooltip('Camera settings'));
        }));

    testWidgets('practice', (t) => catchShot(
        t,
        CatchItScreen(event: pass, practice: true),
        '34-catch-practice'));
  });
}

/// The practice sky standing in for the camera: the real plan's view with
/// the real stars, so screenshots show what the phone would.
class _ShotCamera extends PracticeCapture {
  _ShotCamera({required super.path, required super.magnitude, required super.latDeg, required super.lonDeg, super.catalog})
      : super(width: 720);
  @override
  bool get isPractice => false;
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

/// One App Store screen: its words, what the phone shows, and how to get
/// it into that state.
class _StoreShot {
  const _StoreShot(this.name, this.title, this.sub, this.screen,
      {this.settings, this.extra = const [], this.events, this.act, this.tint = LookUpColors.blue});
  final String name, title, sub;
  final Widget screen;
  final LookUpSettings? settings;
  final List<Override> extra;
  final List<SkyEvent>? events;
  final Future<void> Function(WidgetTester)? act;
  final Color tint;
}

/// The panorama's measures, in logical pixels: each image is [w] wide.
const _storeW = 440.0, _storeH = 956.0;

/// Where phone [i] sits in the panorama: from halfway across its own image
/// into the next one.
double _phoneLeft(int i) => i * _storeW + _storeW * 0.5;

/// One image of the App Store panorama: the shared sky (so edges meet), the
/// previous phone running in from the left, this one running off the right,
/// and this image's words.
class _StoreSlice extends StatelessWidget {
  const _StoreSlice({required this.index, required this.shots, required this.screens, required this.moods});
  final int index;
  final List<_StoreShot> shots;
  final List<ui.Image> screens;
  final List<PipMood> moods;

  @override
  Widget build(BuildContext context) {
    final x0 = index * _storeW;
    final s = shots[index];
    return Scaffold(
      backgroundColor: const Color(0xFF03050C),
      body: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned.fill(
          child: CustomPaint(painter: _StoreSky(x0: x0, tints: [for (final s in shots) s.tint], count: shots.length)),
        ),
        // Pip's trail, under the phones: it comes out from behind the last one.
        Positioned.fill(child: CustomPaint(painter: _PipTrail(x0: x0, count: shots.length))),
        for (final j in [index - 1, index])
          if (j >= 0)
            Positioned(
              left: _phoneLeft(j) - x0,
              top: 292,
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0009)
                  ..rotateY(-0.30)
                  ..rotateZ(0.05)
                  ..scaleByDouble(0.9, 0.9, 1, 1),
                child: _StorePhone(screen: screens[j], clock: j != 0),
              ),
            ),
        // Pip, flying the pass from image to image, in the gap between phones.
        Positioned(
          left: _pipAt(index).dx - x0 - _pipSize(index) / 2,
          top: _pipAt(index).dy - _pipSize(index) / 2,
          child: PipMark(key: ValueKey(index), size: _pipSize(index), mood: moods[index]),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 64,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Text(s.title, textAlign: TextAlign.center, style: display(42, weight: FontWeight.w500, height: 1.08)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 34),
              child: Text(s.sub, textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.grey, fontSize: 16.5, height: 1.35)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The pass's line across the panorama, at [x].
double _passY(double x) => _storeH * (0.52 - 0.22 * math.sin(x / (_storeW * 1.35) * math.pi + 0.6));

/// Pip on image [i]: on the pass, in the gap where one phone ends and the
/// next begins. Bigger on "Meet Pip".
Offset _pipAt(int i) {
  // "Meet Pip": it comes up off the pass to say hello under the words.
  if (i == 2) return Offset(i * _storeW + _storeW / 2, 250);
  final x = i * _storeW + 188;
  return Offset(x, _passY(x) - 8);
}

double _pipSize(int i) => i == 2 ? 132 : 84;

/// Pip's trail along the pass: a few droplets of its light behind each place
/// it sits, fading back toward the last one.
class _PipTrail extends CustomPainter {
  const _PipTrail({required this.x0, required this.count});
  final double x0;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(-x0, 0);
    for (var i = 0; i < count; i++) {
      final head = _pipAt(i);
      for (var k = 1; k <= 9; k++) {
        final x = head.dx - _pipSize(i) * 0.35 - k * 15;
        // Off the pass (Meet Pip), the drops curve up from the line to it.
        final c = Offset.lerp(Offset(x, _passY(x) - 8), Offset(x, head.dy), math.pow(1 - k / 10, 2).toDouble())!;
        final a = 0.55 * (1 - k / 10);
        final r = 6.5 * (1 - k / 12);
        if (c.dx < x0 - 20 || c.dx > x0 + _storeW + 20) continue;
        canvas.drawCircle(
            c,
            r * 3,
            Paint()
              ..shader = RadialGradient(colors: [fireflyGlow.withValues(alpha: a * 0.5), fireflyGlow.withValues(alpha: 0)])
                  .createShader(Rect.fromCircle(center: c, radius: r * 3)));
        canvas.drawCircle(c, r, Paint()..color = fireflyGlow.withValues(alpha: a));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PipTrail o) => o.x0 != x0;
}

/// A phone as it looks in the hand: the titanium band with its buttons, the
/// black border under the glass, the captured screen under a status bar and
/// the Dynamic Island, and a faint reflection across the glass. [clock] is
/// off for the lock screen, which shows its own.
class _StorePhone extends StatelessWidget {
  const _StorePhone({required this.screen, this.clock = true});
  final ui.Image screen;
  final bool clock;

  static const _sw = 393.0, _sh = 852.0, _band = 4.5, _border = 6.0;
  static const _w = _sw + 2 * (_band + _border), _h = _sh + 2 * (_band + _border);
  static const _r = 67.0;

  static Widget _button(double left, double top, double h) => Positioned(
        left: left,
        top: top,
        child: Container(
          width: 4.2,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [Color(0xFF2E3138), Color(0xFF8D929B), Color(0xFF4A4E56), Color(0xFF24272D)],
              stops: [0, 0.35, 0.7, 1],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        width: _w,
        height: _h,
        child: Stack(clipBehavior: Clip.none, children: [
          // Action button and volume on the left; side button and Camera
          // Control on the right.
          _button(-3, 168, 32),
          _button(-3, 226, 60),
          _button(-3, 298, 60),
          _button(_w - 1.2, 252, 96),
          _button(_w - 1.2, 556, 56),
          // The band: brushed titanium catching the light along its edges.
          Container(
            width: _w,
            height: _h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_r),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFA4A9B2), Color(0xFF4A4E57), Color(0xFF7D828B), Color(0xFF2C2F35), Color(0xFF8F949D)],
                stops: [0, 0.22, 0.5, 0.78, 1],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0xA6000000), blurRadius: 70, offset: Offset(0, 36)),
                BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 6)),
              ],
            ),
          ),
          // The band's polished inner lip.
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(1.4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_r - 1.4),
                border: Border.all(color: const Color(0x33FFFFFF), width: 0.8),
              ),
            ),
          ),
          // The glass: black border, then the screen.
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(_band),
              decoration: BoxDecoration(color: const Color(0xFF020203), borderRadius: BorderRadius.circular(_r - _band)),
              padding: const EdgeInsets.all(_border),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_r - _band - _border),
                child: Stack(children: [
                  RawImage(image: screen, width: _sw, height: _sh, fit: BoxFit.fill),
                  // The status bar, either side of the island.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 54,
                    child: Row(children: [
                      SizedBox(
                        width: (_sw - 126) / 2,
                        child: clock
                            ? const Padding(
                                padding: EdgeInsets.only(top: 4, left: 14),
                                child: Text('9:41',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                              )
                            : null,
                      ),
                      const Spacer(),
                      const Padding(
                        padding: EdgeInsets.only(top: 4, right: 30),
                        child: CustomPaint(size: Size(76, 13), painter: _StatusIcons()),
                      ),
                    ]),
                  ),
                  // The Dynamic Island, its camera just showing.
                  Positioned(
                    top: 11,
                    left: (_sw - 126) / 2,
                    child: Container(
                      width: 126,
                      height: 37,
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(19)),
                      alignment: const Alignment(0.72, 0),
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: Alignment(-0.3, -0.35),
                            radius: 0.8,
                            colors: [Color(0xFF2B3550), Color(0xFF0B0E18), Color(0xFF050608)],
                            stops: [0, 0.45, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          // Light on the glass: a soft sheen from the top left, and the
          // glass's own rim.
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(_band),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_r - _band),
                  border: Border.all(color: const Color(0x1AFFFFFF), width: 0.8),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x1CFFFFFF), Color(0x08FFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x06FFFFFF)],
                    stops: [0, 0.28, 0.42, 0.85, 1],
                  ),
                ),
              ),
            ),
          ),
        ]),
      );
}

/// Signal, Wi-Fi and a nearly full battery, as iOS draws them.
class _StatusIcons extends CustomPainter {
  const _StatusIcons();

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    // Signal: four bars.
    for (var k = 0; k < 4; k++) {
      final h = 4.0 + k * 2.6;
      canvas.drawRRect(RRect.fromLTRBR(k * 5.0, 12 - h, k * 5.0 + 3.3, 12, const Radius.circular(1)), white);
    }
    // Wi-Fi: a dot and two arcs.
    const c = Offset(32, 12);
    canvas.drawArc(Rect.fromCircle(center: c, radius: 3.6), -3 * math.pi / 4, math.pi / 2, true, white);
    final arc = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    for (final r in const [7.0, 10.6]) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -3 * math.pi / 4 + 0.08, math.pi / 2 - 0.16, false, arc);
    }
    // Battery.
    final dim = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(RRect.fromLTRBR(47.5, 0.5, 72.5, 12.5, const Radius.circular(4)), dim);
    canvas.drawRRect(RRect.fromLTRBR(49.5, 2.5, 49.5 + 19, 10.5, const Radius.circular(2.4)), white);
    canvas.drawRRect(RRect.fromLTRBR(73.6, 4.4, 75.2, 8.6, const Radius.circular(1)), Paint()..color = Colors.white.withValues(alpha: 0.4));
  }

  @override
  bool shouldRepaint(_StatusIcons old) => false;
}

/// The sky behind the whole panorama, drawn for the slice starting at [x0]:
/// the night, a glow of each shot's colour under its phone, stars, and one
/// pass's dashed path running through every image with the station on it.
class _StoreSky extends CustomPainter {
  const _StoreSky({required this.x0, required this.tints, required this.count});
  final double x0;
  final List<Color> tints;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF03050C), Color(0xFF0B1630), Color(0xFF162A52)],
            stops: [0, 0.55, 1],
          ).createShader(rect));
    canvas.save();
    canvas.translate(-x0, 0);
    // Each phone's colour, glowing low behind it.
    for (var i = 0; i < count; i++) {
      final c = Offset(_phoneLeft(i) + 170, _storeH * 0.78);
      canvas.drawCircle(
          c,
          420,
          Paint()
            ..shader = RadialGradient(colors: [tints[i].withValues(alpha: 0.22), tints[i].withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: c, radius: 420)));
    }
    // Stars, the same wherever an image is cut.
    final rnd = math.Random(11);
    final star = Paint();
    for (var k = 0; k < 2200; k++) {
      final p = Offset(rnd.nextDouble() * _storeW * count, rnd.nextDouble() * _storeH);
      final b = rnd.nextDouble();
      if (p.dx < x0 - 4 || p.dx > x0 + _storeW + 4) continue;
      star.color = Colors.white.withValues(alpha: 0.25 + 0.6 * b * b);
      canvas.drawCircle(p, 0.5 + 1.1 * b * b, star);
    }
    // The pass: one long gentle wave across the panorama, dashed.
    final path = Path();
    for (var x = -40.0; x <= _storeW * count + 40; x += 6) {
      final y = _passY(x);
      x == -40 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final pen = Paint()
      ..color = const Color(0xFF5A8DE8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 30) {
        canvas.drawPath(m.extractPath(d, d + 16), pen);
      }
      // The station, twice along the way, with its glow.
      for (final f in const [0.27, 0.71]) {
        final at = m.getTangentForOffset(m.length * f)!.position;
        canvas.drawCircle(
            at,
            34,
            Paint()
              ..shader = RadialGradient(colors: [const Color(0xFF9CC2FF).withValues(alpha: 0.6), const Color(0x009CC2FF)])
                  .createShader(Rect.fromCircle(center: at, radius: 34)));
        canvas.drawCircle(at, 7, Paint()..color = Colors.white);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StoreSky o) => o.x0 != x0;
}

/// The sky camera's look: the real overlay, Pip landed on the pass as the
/// plain dot it becomes to guide, and the camera's own words.
class _PipGuides extends StatelessWidget {
  const _PipGuides({required this.path, required this.pose});
  final List<({DateTime t, SkyDir d})> path;
  final List<double> pose;

  @override
  Widget build(BuildContext context) => Stack(children: [
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
          child: LayoutBuilder(builder: (context, c) {
            final p = projectToScreen(pose, path[12].d, declinationDeg: 0, previewHeightPx: c.maxHeight);
            final at = p == null ? Offset(c.maxWidth / 2, c.maxHeight / 2) : Offset(c.maxWidth / 2 + p.x, c.maxHeight / 2 + p.y);
            return Stack(children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: SkyOverlayPainter(
                    r: pose,
                    declinationDeg: 0,
                    target: path[12].d,
                    path: path,
                    now: path[12].t,
                    onTarget: true,
                    previewHeightPx: c.maxHeight,
                    labelStyle: Theme.of(context).textTheme.labelSmall!,
                  ),
                ),
              ),
              Positioned(left: at.dx - 28, top: at.dy - 28, child: const PipMark(size: 56, asDot: true)),
            ]);
          }),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 500,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xCC0B1328), borderRadius: BorderRadius.circular(18)),
            child: const Text('That\'s the space station. Tap Pip to catch it!',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]);
}

