import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/plan/night_plan.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/tonight.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';

void main() {
  late SkyCatalog catalog;
  setUpAll(() {
    catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
        jsonDecode(File('assets/sky/constellations.json').readAsStringSync()));
  });

  // Nashville, noon on 2026-10-20 (CDT).
  const lat = 36.17, lon = -86.78;
  final noon = DateTime.utc(2026, 10, 20, 17);

  List<NightPlan> nights(int n, {CloudForecast? weather}) => [
        for (var i = 0; i < n; i++)
          planNight(
              catalog: catalog,
              at: noon.add(Duration(days: i)),
              lat: lat,
              lon: lon,
              darkness: SkyDarkness.suburbs,
              weather: weather),
      ];

  test('a plan made at noon is for the coming night', () {
    final p = nights(1).single;
    // Dusk around 6:35 PM, dawn around 6:35 AM local.
    expect(p.window!.start.difference(DateTime.utc(2026, 10, 20, 23, 35)).inMinutes.abs(), lessThan(30));
    expect(p.window!.end.difference(DateTime.utc(2026, 10, 21, 11, 35)).inMinutes.abs(), lessThan(30));
  });

  test('the next night is a day later', () {
    final [a, b] = nights(2);
    expect(b.window!.start.difference(a.window!.start).inMinutes, closeTo(24 * 60, 5));
  });

  test('sightings are keyed by the ids the Sky tab uses', () {
    final s = nights(1).single.sightings;
    expect(s.keys, containsAll([SkyId.moon, SkyId.planet(Planet.saturn), SkyId.constellation('And')]));
  });

  test('Saturn, a fortnight after opposition, is good tonight', () {
    final good = firstGoodNight(SkyId.planet(Planet.saturn), nights(3));
    expect(good?.night, 0);
    final w = nights(1).single.window!;
    expect(good!.sighting.best.isAfter(w.start) && good.sighting.best.isBefore(w.end), isTrue);
  });

  test('never "good" through cloud: an overcast spell pushes the next good night back', () {
    final overcast = CloudForecast(
      latitude: lat,
      longitude: lon,
      fetchedAt: noon,
      hourly: [
        // Solid cloud for the first three nights, then clear.
        for (var h = 0; h < 24 * 6; h++)
          CloudSample(time: noon.add(Duration(hours: h)), coverPercent: h < 24 * 3 ? 100 : 0),
      ],
    );
    final plans = nights(6, weather: overcast);
    expect(plans.first.outlook!.hasForecast, isTrue);
    final good = firstGoodNight(SkyId.planet(Planet.saturn), plans);
    expect(good?.night, 3);
    for (final p in plans.take(3)) {
      expect(p.sightings.values.whereType<SkySighting>().where((s) => s.verdict == Seeability.great), isEmpty);
    }
  });

  test('past the end of the forecast, nights say so instead of guessing clear', () {
    final short = CloudForecast(
      latitude: lat,
      longitude: lon,
      fetchedAt: noon,
      hourly: [for (var h = 0; h < 48; h++) CloudSample(time: noon.add(Duration(hours: h)), coverPercent: 10)],
    );
    final plans = nights(5, weather: short);
    expect(plans.first.outlook!.hasForecast, isTrue);
    expect(plans.last.outlook!.hasForecast, isFalse);
  });

  test('something that never comes up has no good night', () {
    expect(firstGoodNight('showpiece:nowhere', nights(2)), isNull);
  });
}
