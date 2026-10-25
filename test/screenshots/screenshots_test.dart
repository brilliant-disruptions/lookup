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
import 'package:lookup/services/plus_service.dart';

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

final _events = [
  _ev('iss:1', SkyEventType.iss, const Duration(hours: 3, minutes: 12),
      details: {'brightness': 'brighter than any star', 'rangeKm': 480}),
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
    ],
    child: MaterialApp(theme: theme, debugShowCheckedModeBanner: false, home: home),
  );
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
    await t.tap(find.text('Upcoming'));
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
    await t.tap(find.text('Settings'));
    await t.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/5-settings.png'));
  });
}
