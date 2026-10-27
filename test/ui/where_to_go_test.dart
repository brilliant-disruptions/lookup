import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/open_meteo_client.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/plan/where_to_go.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';
import 'package:lookup/state/plan_state.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/where_to_go_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.s);
  final LookUpSettings s;
  @override
  Future<LookUpSettings> build() async => s;
}

/// Every hour of the next two days at [cover]%.
CloudForecast _forecast(double lat, double lon, int cover) {
  final from = DateTime.now().toUtc().subtract(const Duration(hours: 2));
  final hour = DateTime.utc(from.year, from.month, from.day, from.hour);
  return CloudForecast(latitude: lat, longitude: lon, fetchedAt: from, hourly: [
    for (var h = 0; h < 48; h++) CloudSample(time: hour.add(Duration(hours: h)), coverPercent: cover),
  ]);
}

class _Meteo extends OpenMeteoClient {
  @override
  Future<CloudForecast> fetchCloudForecast(double lat, double lon, {int days = 7, int pastDays = 7}) async =>
      _forecast(lat, lon, 0);
}

void main() {
  final dusk = DateTime.utc(2026, 10, 20, 23);
  NightOutlook night(int cover) => NightOutlook.from(
        start: dusk,
        end: dusk.add(const Duration(hours: 11)),
        weather: CloudForecast(latitude: 0, longitude: 0, fetchedAt: dusk, hourly: [
          for (var h = 0; h < 11; h++) CloudSample(time: dusk.add(Duration(hours: h)), coverPercent: cover),
        ]),
      );
  PlaceNight place(String name, int cover, {bool here = false, SkyDarkness sky = SkyDarkness.suburbs}) => PlaceNight(
      name: name,
      here: here,
      darkness: sky,
      outlook: night(cover),
      distanceKm: here ? null : 243,
      bearingDeg: here ? null : 95);

  group('words', () {
    test('go: where, how clear, how far, and what here is doing', () {
      final w = whereToGoWords(whereToGo([place('Home', 100, here: true), place('The cabin', 0, sky: SkyDarkness.dark)]));
      expect(w.headline, 'Head to The cabin');
      expect(w.detail, 'Clear all night under a dark sky, 240 km east. Here: cloudy all night.');
    });

    test('stay put says why', () {
      final w = whereToGoWords(whereToGo([place('Home', 0, here: true), place('The cabin', 100)]));
      expect(w.headline, 'Stay put tonight');
      expect(w.detail, 'Home is clear all night. Your other places are cloudy.');
    });

    test('cloudy everywhere', () {
      final w = whereToGoWords(whereToGo([place('Home', 100, here: true), place('The cabin', 100)]));
      expect(w.headline, 'Cloudy at all your places');
    });

    test('times keep their case mid-sentence', () {
      final w = whereToGoWords(whereToGo([
        PlaceNight(name: 'Home', here: true, darkness: SkyDarkness.suburbs, outlook: NightOutlook.from(
            start: dusk, end: dusk.add(const Duration(hours: 11)),
            weather: CloudForecast(latitude: 0, longitude: 0, fetchedAt: dusk, hourly: [
              for (var h = 0; h < 11; h++) CloudSample(time: dusk.add(Duration(hours: h)), coverPercent: h < 2 ? 0 : 100),
            ]))),
        place('The cabin', 0, sky: SkyDarkness.dark),
      ]));
      expect(w.detail, contains('Here: clear until '));
      expect(w.detail, isNot(contains(' am.')));
      expect(w.detail, isNot(contains(' pm.')));
    });

    test('distances are rounded, never falsely precise', () {
      PlaceNight at(double km) => PlaceNight(name: 'x', here: false, darkness: SkyDarkness.dark, outlook: null, distanceKm: km, bearingDeg: 0);
      expect(howFar(at(7.4)), '7 km north');
      expect(howFar(at(43)), '45 km north');
      expect(howFar(at(243)), '240 km north');
    });
  });

  group('provider', () {
    setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

    ProviderContainer container(LookUpSettings s) {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith(() => _Settings(s)),
        weatherProvider.overrideWith((_) async => _forecast(36.17, -86.78, 100)),
        openMeteoProvider.overrideWithValue(_Meteo()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('nothing to compare without a saved place', () async {
      final w = await container(const LookUpSettings(latitude: 36.17, longitude: -86.78)).read(whereToGoProvider.future);
      expect(w, isNull);
    });

    test('cloudy at home, clear at the cabin: go to the cabin', () async {
      final w = await container(const LookUpSettings(
        latitude: 36.17,
        longitude: -86.78,
        places: [SavedPlace(name: 'The cabin', latitude: 35.61, longitude: -83.49, skyDarkness: SkyDarkness.dark)],
      )).read(whereToGoProvider.future);
      expect(w!.spots, hasLength(2));
      expect(w.result.kind, WhereToGoKind.go);
      final cabin = w.result.best!;
      expect(cabin.name, 'The cabin');
      expect(cabin.darkness, SkyDarkness.dark);
      expect(cabin.distanceKm, closeTo(302, 5));
      expect(w.result.ranked.last.here, isTrue);
    });
  });

  testWidgets('the screen ranks places and invites a first saved place', (t) async {
    Future<void> show(({WhereToGo result, List<Spot> spots})? w) async {
      await t.pumpWidget(ProviderScope(
        key: UniqueKey(),
        overrides: [whereToGoProvider.overrideWith((_) async => w)],
        child: MaterialApp(theme: buildLookUpTheme(), home: const WhereToGoScreen()),
      ));
      await t.pumpAndSettle();
    }

    await show(null);
    expect(find.text('Save somewhere darker'), findsOneWidget);
    expect(find.text('Add a place'), findsOneWidget);

    final r = whereToGo([place('Home', 100, here: true), place('The cabin', 0, sky: SkyDarkness.dark)]);
    await show((
      result: r,
      spots: const [
        (name: 'Home', lat: 36.17, lon: -86.78, darkness: null, here: true),
        (name: 'The cabin', lat: 35.61, lon: -83.49, darkness: SkyDarkness.dark, here: false),
      ],
    ));
    expect(find.text('Head to The cabin'), findsOneWidget);
    expect(find.text('Best'), findsOneWidget);
    expect(find.text('You\'re here'), findsOneWidget);
    expect(find.text('240 km east'), findsOneWidget);
    // Best first.
    expect(t.getTopLeft(find.text('Dark sky')).dy, lessThan(t.getTopLeft(find.text('You\'re here')).dy));
  });
}
