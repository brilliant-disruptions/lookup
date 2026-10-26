import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/sun.dart';
import 'package:lookup/domain/sky/tonight.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';

void main() {
  const lat = 36.17, lon = -86.78; // Nashville
  final now = DateTime.utc(2026, 10, 20, 20); // 3 PM CDT
  late SkyCatalog catalog;
  setUpAll(() {
    catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
        jsonDecode(File('assets/sky/constellations.json').readAsStringSync()));
  });

  group('planet highlights match published dates', () {
    final hl = planetHighlights(DateTime.utc(2025, 12, 1), days: 500);
    void expectNear(Planet p, String kind, DateTime when) {
      final match = hl.where((h) => h.planet == p && h.kind == kind && h.date.difference(when).inDays.abs() <= 2);
      expect(match, isNotEmpty, reason: '${p.label} $kind near $when');
    }

    test('oppositions', () {
      expectNear(Planet.jupiter, 'opposition', DateTime.utc(2026, 1, 10));
      expectNear(Planet.saturn, 'opposition', DateTime.utc(2026, 10, 4));
      expectNear(Planet.mars, 'opposition', DateTime.utc(2027, 2, 19));
    });

    test('greatest elongations', () {
      expectNear(Planet.venus, 'elongation', DateTime.utc(2026, 8, 15));
      expectNear(Planet.venus, 'elongation', DateTime.utc(2027, 1, 3));
      expectNear(Planet.mercury, 'elongation', DateTime.utc(2026, 2, 19));
      expectNear(Planet.mercury, 'elongation', DateTime.utc(2026, 10, 12));
      final venusAug = hl.firstWhere((h) => h.planet == Planet.venus && h.date.month == 8);
      expect(venusAug.evening, isTrue);
      expect(venusAug.title, 'Venus at its best after sunset');
    });
  });

  test('planet magnitudes are in the published range', () {
    expect(planetMagnitude(Planet.jupiter, DateTime.utc(2026, 1, 10)), closeTo(-2.6, 0.3));
    expect(planetMagnitude(Planet.venus, DateTime.utc(2026, 8, 15)), closeTo(-4.4, 0.3));
    expect(planetMagnitude(Planet.mars, DateTime.utc(2027, 2, 19)), closeTo(-1.2, 0.3));
  });

  test('Nashville sunset on Oct 20 2026 is about 6:04 PM CDT', () {
    final c = horizonCrossings((t) => sunAltitudeDeg(t, lat, lon), now, now.add(const Duration(hours: 24)), h0: -0.83);
    expect(c.first.rising, isFalse);
    expect(c.first.t.difference(DateTime.utc(2026, 10, 20, 23, 4)).inMinutes.abs(), lessThan(6));
    expect(c[1].rising, isTrue);
  });

  test('planets tonight: Venus near the Sun (conjunction Oct 24), Saturn up all evening', () {
    final ps = planetsTonight(now: now, lat: lat, lon: lon, darkness: SkyDarkness.suburbs);
    expect(ps, hasLength(5));
    final venus = ps.firstWhere((p) => p.planet == Planet.venus);
    expect(venus.visible, isFalse);
    expect(venus.whyNot, 'Too close to the Sun right now');
    final saturn = ps.firstWhere((p) => p.planet == Planet.saturn);
    expect(saturn.visible, isTrue);
    expect(saturn.sighting!.altDeg, greaterThan(40));
    // Visible ones come first, brightest first.
    expect(ps.takeWhile((p) => p.visible).every((p) => p.visible), isTrue);
    expect(ps.first.visible, isTrue);
  });

  test('moon: waxing gibbous a week before the Oct 26 full Moon', () {
    final m = moonTonight(now: now, lat: lat, lon: lon);
    expect(m.phase, MoonPhase.waxingGibbous);
    expect(m.illumination, closeTo(0.7, 0.1));
    expect(m.waxing, isTrue);
    expect(moonPhase(DateTime.utc(2026, 10, 26, 5)), MoonPhase.full);
  });

  test('catalog loads all 88 constellations and the naked-eye stars', () {
    expect(catalog.constellations, hasLength(88));
    expect(catalog.stars.length, greaterThan(1500));
    expect(catalog.stars.first.mag, lessThan(-1)); // Sirius
    expect(catalog.stars.where((s) => s.name == 'Polaris'), hasLength(1));
    final polaris = catalog.stars.firstWhere((s) => s.name == 'Polaris');
    // The pole star sits at the observer's latitude, due north.
    final h = polaris.horizontal(now, lat, lon);
    expect(h.altitudeDeg, closeTo(lat, 1.5));
  });

  test('constellations tonight: autumn favourites up, summer ones low or gone', () {
    final cs = constellationsTonight(catalog: catalog, now: now, lat: lat, lon: lon, darkness: SkyDarkness.suburbs);
    final ids = cs.map((c) => c.constellation.id).toList();
    expect(ids, containsAll(['Cas', 'Peg', 'And', 'Cyg']));
    expect(ids, isNot(contains('Cru'))); // Southern Cross never rises in Nashville
    expect(cs.first.constellation.rank, 1);
  });

  group('can I see it', () {
    SkyConditions sky({double sun = -20, double moonAlt = -10, double illum = 0, int? cloud, int? vis, int? rain}) =>
        SkyConditions(sunAltDeg: sun, moonAltDeg: moonAlt, moonIllumination: illum, cloudPercent: cloud, visibilityM: vis, precipProbability: rain);

    test('basics: below horizon, clear, low', () {
      expect(canSee(altDeg: -5, mag: -2, c: sky(), darkness: SkyDarkness.city), Seeability.belowHorizon);
      expect(canSee(altDeg: 50, mag: -2, c: sky(), darkness: SkyDarkness.city), Seeability.great);
      expect(canSee(altDeg: 7, mag: -2, c: sky(), darkness: SkyDarkness.city), Seeability.low);
    });

    test('weather wins over a bright planet', () {
      expect(canSee(altDeg: 50, mag: -2, c: sky(cloud: 90), darkness: SkyDarkness.dark), Seeability.cloudy);
      expect(canSee(altDeg: 50, mag: -2, c: sky(cloud: 55), darkness: SkyDarkness.dark), Seeability.patchy);
      expect(canSee(altDeg: 50, mag: -2, c: sky(rain: 80), darkness: SkyDarkness.dark), Seeability.rain);
      expect(canSee(altDeg: 50, mag: -2, c: sky(vis: 800), darkness: SkyDarkness.dark), Seeability.foggy);
    });

    test('the Andromeda Galaxy: dark sky yes, city no, full Moon no', () {
      expect(canSee(altDeg: 60, mag: 3.4, diffuse: true, c: sky(), darkness: SkyDarkness.dark).yes, isTrue);
      expect(canSee(altDeg: 60, mag: 3.4, diffuse: true, c: sky(), darkness: SkyDarkness.city), Seeability.tooFaint);
      expect(canSee(altDeg: 60, mag: 3.4, diffuse: true, c: sky(moonAlt: 40, illum: 1), darkness: SkyDarkness.dark),
          Seeability.moonlit);
    });

    test('twilight hides faint stars but not Venus', () {
      expect(canSee(altDeg: 20, mag: 2.0, c: sky(sun: -4), darkness: SkyDarkness.dark), Seeability.twilight);
      expect(canSee(altDeg: 20, mag: -4.2, c: sky(sun: -4), darkness: SkyDarkness.dark).yes, isTrue);
    });
  });

  test('night outlook finds the clear stretch and says its shape', () {
    final start = DateTime.utc(2026, 10, 21, 0), end = DateTime.utc(2026, 10, 21, 11);
    CloudForecast f(List<int> covers) => CloudForecast(
          latitude: lat,
          longitude: lon,
          fetchedAt: start,
          hourly: [
            for (var i = 0; i < covers.length; i++)
              CloudSample(time: start.add(Duration(hours: i)), coverPercent: covers[i]),
          ],
        );
    final later = NightOutlook.from(start: start, end: end, weather: f([5, 10, 10, 20, 80, 90, 90, 90, 90, 90, 90]));
    expect(later.shape, 'clouds-later');
    expect(later.bestStart, start);
    expect(later.bestEnd, start.add(const Duration(hours: 4)));
    expect(NightOutlook.from(start: start, end: end, weather: f(List.filled(11, 5))).shape, 'clear');
    expect(NightOutlook.from(start: start, end: end, weather: f(List.filled(11, 95))).shape, 'cloudy');
    expect(NightOutlook.from(start: start, end: end, weather: f([90, 90, 90, 80, 40, 20, 10, 5, 5, 5, 5])).shape, 'clearing');
    expect(NightOutlook.from(start: start, end: end).shape, 'unknown');
  });
}
