import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/calendar.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/delta_t.dart';
import 'package:lookup/domain/sky/history.dart';

/// Geocentric apparent RA/Dec (degrees) from JPL Horizons (DE441), UT,
/// fetched 2026-10-30: two dates in each of 3000 BC … 2400 AD.
const _horizons = <(String, double, double, double)>[
  ('sun', 625660.55, 243.3451, -21.7195),
  ('sun', 625751.72, 337.0666, -9.8529),
  ('sun', 990910.55, 250.6526, -22.7142),
  ('sun', 991001.72, 343.9111, -7.0095),
  ('sun', 1356160.55, 258.1700, -23.3606),
  ('sun', 1356251.72, 350.7396, -4.0618),
  ('sun', 1538785.55, 261.9938, -23.5472),
  ('sun', 1538876.72, 354.1693, -2.5597),
  ('sun', 1721410.55, 265.8606, -23.6395),
  ('sun', 1721501.72, 357.6022, -1.0520),
  ('sun', 1904035.55, 269.7560, -23.6337),
  ('sun', 1904126.72, 1.0489, 0.4589),
  ('sun', 2086660.55, 273.6762, -23.5278),
  ('sun', 2086751.72, 4.5100, 1.9648),
  ('sun', 2269285.55, 277.6351, -23.3192),
  ('sun', 2269376.72, 8.0074, 3.4670),
  ('sun', 2598010.55, 284.8184, -22.6901),
  ('sun', 2598101.72, 14.3788, 6.1301),
  ('moon', 625660.55, 92.6376, 28.5340),
  ('moon', 625751.72, 207.6110, -16.5291),
  ('moon', 990910.55, 281.3596, -25.8571),
  ('moon', 991001.72, 40.6320, 13.7450),
  ('moon', 1356160.55, 128.0735, 15.4917),
  ('moon', 1356251.72, 244.4636, -16.4464),
  ('moon', 1538785.55, 210.1483, -13.3500),
  ('moon', 1538876.72, 344.3883, -2.5143),
  ('moon', 1721410.55, 315.2627, -13.2576),
  ('moon', 1721501.72, 74.4151, 23.6433),
  ('moon', 1904035.55, 58.3302, 25.4886),
  ('moon', 1904126.72, 173.0947, -0.5253),
  ('moon', 2086660.55, 164.9728, 8.7231),
  ('moon', 2086751.72, 281.9527, -28.3632),
  ('moon', 2269285.55, 248.6255, -23.1663),
  ('moon', 2269376.72, 21.1582, 6.3144),
  ('moon', 2598010.55, 144.0391, 11.1396),
  ('moon', 2598101.72, 275.2634, -24.1159),
  ('mercury', 625660.55, 228.3379, -19.6397),
  ('mercury', 625751.72, 312.4542, -20.6729),
  ('mercury', 990910.55, 238.8713, -22.1806),
  ('mercury', 991001.72, 319.5452, -18.6208),
  ('mercury', 1356160.55, 250.0328, -24.0651),
  ('mercury', 1356251.72, 327.5063, -15.9577),
  ('mercury', 1538785.55, 255.8142, -24.7186),
  ('mercury', 1538876.72, 331.7448, -14.4082),
  ('mercury', 1721410.55, 261.7039, -25.1602),
  ('mercury', 1721501.72, 336.1084, -12.7295),
  ('mercury', 1904035.55, 267.6733, -25.3777),
  ('mercury', 1904126.72, 340.5857, -10.9301),
  ('mercury', 2086660.55, 273.6883, -25.3632),
  ('mercury', 2086751.72, 345.1589, -9.0249),
  ('mercury', 2269285.55, 279.7528, -25.1133),
  ('mercury', 2269376.72, 349.8435, -7.0200),
  ('mercury', 2598010.55, 273.5129, -24.0526),
  ('mercury', 2598101.72, 349.4253, -6.3013),
  ('venus', 625660.55, 212.5218, -12.1976),
  ('venus', 625751.72, 329.2545, -14.3192),
  ('venus', 990910.55, 296.2426, -23.2842),
  ('venus', 991001.72, 9.4240, 11.0534),
  ('venus', 1356160.55, 229.4939, -17.4891),
  ('venus', 1356251.72, 346.3798, -7.4038),
  ('venus', 1538785.55, 219.1719, -11.0367),
  ('venus', 1538876.72, 317.3865, -17.3543),
  ('venus', 1721410.55, 313.5446, -19.2608),
  ('venus', 1721501.72, 9.5579, 12.2618),
  ('venus', 1904035.55, 283.5557, -24.2862),
  ('venus', 1904126.72, 32.1466, 13.8569),
  ('venus', 2086660.55, 248.0630, -21.1777),
  ('venus', 2086751.72, 3.4944, 0.0975),
  ('venus', 2269285.55, 229.5119, -14.4739),
  ('venus', 2269376.72, 334.7544, -11.4453),
  ('venus', 2598010.55, 243.4056, -16.8550),
  ('venus', 2598101.72, 336.8550, -10.1089),
  ('mars', 625660.55, 319.0978, -16.8686),
  ('mars', 625751.72, 12.2245, 6.0288),
  ('mars', 990910.55, 240.0519, -21.7164),
  ('mars', 991001.72, 316.1239, -18.3554),
  ('mars', 1356160.55, 169.8173, 6.9786),
  ('mars', 1356251.72, 183.0013, 1.7520),
  ('mars', 1538785.55, 98.9059, 27.3763),
  ('mars', 1538876.72, 92.2120, 26.3455),
  ('mars', 1721410.55, 4.0300, 2.2578),
  ('mars', 1721501.72, 52.8288, 20.5785),
  ('mars', 1904035.55, 320.0102, -16.8330),
  ('mars', 1904126.72, 22.7870, 9.6637),
  ('mars', 2086660.55, 280.9316, -24.1667),
  ('mars', 2086751.72, 352.6127, -4.2487),
  ('mars', 2269285.55, 244.8888, -21.5434),
  ('mars', 2269376.72, 316.7003, -17.8741),
  ('mars', 2598010.55, 53.6506, 21.4391),
  ('mars', 2598101.72, 91.9572, 25.2563),
  ('jupiter', 625660.55, 177.6121, 2.5408),
  ('jupiter', 625751.72, 179.2202, 2.1056),
  ('jupiter', 990910.55, 287.1456, -24.0163),
  ('jupiter', 991001.72, 309.6787, -20.0356),
  ('jupiter', 1356160.55, 54.8834, 19.5624),
  ('jupiter', 1356251.72, 56.1088, 20.0834),
  ('jupiter', 1538785.55, 130.0493, 19.8361),
  ('jupiter', 1538876.72, 120.5304, 22.0710),
  ('jupiter', 1721410.55, 187.7810, -1.9020),
  ('jupiter', 1721501.72, 186.4322, -0.9837),
  ('jupiter', 1904035.55, 238.3548, -19.8181),
  ('jupiter', 1904126.72, 251.6333, -21.9694),
  ('jupiter', 2086660.55, 295.4925, -22.0276),
  ('jupiter', 2086751.72, 316.8834, -17.3377),
  ('jupiter', 2269285.55, 352.9653, -4.4488),
  ('jupiter', 2269376.72, 10.3019, 3.2505),
  ('jupiter', 2598010.55, 321.5360, -15.8200),
  ('jupiter', 2598101.72, 341.8923, -8.5567),
  ('saturn', 625660.55, 99.6679, 24.9809),
  ('saturn', 625751.72, 93.5181, 25.3266),
  ('saturn', 990910.55, 91.0380, 24.4502),
  ('saturn', 991001.72, 85.7548, 24.5049),
  ('saturn', 1356160.55, 81.2933, 23.2820),
  ('saturn', 1356251.72, 77.6832, 23.2188),
  ('saturn', 1538785.55, 78.9092, 22.7784),
  ('saturn', 1538876.72, 76.0358, 22.7619),
  ('saturn', 1721410.55, 70.9062, 21.4242),
  ('saturn', 1721501.72, 69.5632, 21.5352),
  ('saturn', 1904035.55, 67.4900, 20.6084),
  ('saturn', 1904126.72, 67.1549, 20.8824),
  ('saturn', 2086660.55, 60.9752, 19.0881),
  ('saturn', 2086751.72, 62.0881, 19.6613),
  ('saturn', 2269285.55, 57.2525, 18.0518),
  ('saturn', 2269376.72, 59.4387, 18.8896),
  ('saturn', 2598010.55, 278.3568, -22.3919),
  ('saturn', 2598101.72, 286.8007, -21.7466),];

Equatorial _model(String body, DateTime utc) => switch (body) {
      'sun' => sunEquatorial(utc),
      'moon' => moonEquatorial(utc),
      _ => planetEquatorial(Planet.values.byName(body), utc),
    };

void main() {
  group('ΔT (Espenak & Meeus)', () {
    test('published values', () {
      expect(deltaTSeconds(0), closeTo(10583.6, 0.1));
      expect(deltaTSeconds(1000), closeTo(1574.2, 0.1));
      expect(deltaTSeconds(1600), closeTo(120, 0.5));
      expect(deltaTSeconds(2000), closeTo(63.86, 0.1));
    });

    test('no jumps where the polynomials meet', () {
      for (final y in [-500.0, 500.0, 1600.0, 1700.0, 1800.0, 2050.0, 2150.0]) {
        expect(deltaTSeconds(y - 1e-6), closeTo(deltaTSeconds(y), 1.0), reason: '$y');
      }
    });
  });

  group('calendar', () {
    test('Julian Days match Meeus', () {
      expect(julianDay(2000, 1, 1, 12), 2451545.0);
      expect(julianDay(1957, 10, 4, 0.81 * 24), closeTo(2436116.31, 1e-6));
      expect(julianDay(333, 1, 27, 12), 1842713.0); // Julian calendar
      expect(julianDay(-4712, 1, 1, 12), 0);
    });

    test('4 October 1582 (Julian) is followed by 15 October (Gregorian)', () {
      expect(julianDay(1582, 10, 15) - julianDay(1582, 10, 4), 1);
      expect(isMissingDate(1582, 10, 10), isTrue);
      expect(daysInMonth(1500, 2), 29); // Julian leap year
      expect(daysInMonth(1900, 2), 28);
      expect(daysInMonth(-1, 2), 28);
      expect(daysInMonth(0, 2), 29); // 1 BC
    });

    test('dates round-trip and read as written', () {
      final d = HistoricDate.fromJulianDay(julianDay(1504, 2, 29, 19.5));
      expect((d.year, d.month, d.day, d.hour, d.minute), (1504, 2, 29, 19, 30));
      expect(d.dateLabel, 'Feb 29, 1504');
      expect(d.timeLabel, '7:30 PM');
      expect(HistoricDate.fromJulianDay(julianDay(-1, 6, 17, 19.75)).dateLabel, 'Jun 17, 2 BC');
      final u = utcFromLocalMeanTime(1969, 7, 20, 20.5933, -95.10);
      expect(u.difference(DateTime.utc(1969, 7, 21, 2, 56)).inSeconds.abs(), lessThan(60));
      expect(localMeanTime(u, -95.10).timeLabel, '8:36 PM');
    });
  });

  test('the Sun, Moon and planets agree with JPL Horizons, 3000 BC to 2400 AD', () {
    for (final (body, jd, ra, dec) in _horizons) {
      final utc = utcFromJulianDay(jd);
      final early = utc.isBefore(utcFromJulianDay(julianDay(-999, 1, 1)));
      // Measured: from 1000 BC on, the Moon is within 0.45° and the rest
      // within 0.25°; before, the Moon within 1.7° (ΔT itself is uncertain
      // by an hour or so then).
      final tolerance = body == 'moon' ? (early ? 2.0 : 0.6) : (early ? 0.5 : 0.3);
      expect(equatorialSeparationDeg(_model(body, utc), Equatorial(ra, dec, 1)), lessThan(tolerance),
          reason: '$body at JD $jd');
    }
  });

  group('famous nights show what history says', () {
    late SkyCatalog catalog;
    setUpAll(() {
      Map<String, Object?> read(String f) => jsonDecode(File('assets/sky/$f').readAsStringSync()) as Map<String, Object?>;
      catalog = SkyCatalog.fromJson(read('stars.json'), read('constellations.json'), read('proper_motion.json'));
    });
    FamousNight night(String id) => famousNights.firstWhere((n) => n.id == id);
    Horizontal planet(FamousNight n, Planet p) => planetHorizontal(p, n.utc, n.lat, n.lon);
    double sunAlt(FamousNight n) => sunHorizontal(n.utc, n.lat, n.lon).altitudeDeg;

    test('Thuban was the pole star when the pyramids were built', () {
      final thuban = catalog.stars.firstWhere((s) => s.name == 'Thuban');
      expect(thuban.pm, isNotNull);
      final n = night('giza');
      // Its height equals your latitude when it sits on the pole.
      expect((thuban.horizontal(n.utc, n.lat, n.lon).altitudeDeg - n.lat).abs(), lessThan(1.6));
      // Nearest the pole around 2830 BC.
      double fromPole(int year) => 90 - precessFromJ2000(thuban.raDeg, thuban.decDeg, utcFromJulianDay(julianDay(year, 1, 1))).decDeg;
      final years = [for (var y = -3499; y <= -1999; y += 10) y];
      final nearest = years.reduce((a, b) => fromPole(a) < fromPole(b) ? a : b);
      expect(nearest, inInclusiveRange(-2899, -2749));
    });

    test('Jupiter and Saturn a degree apart, high over Jerusalem, 7 BC', () {
      final n = night('conjunction-7bc');
      final j = planet(n, Planet.jupiter), s = planet(n, Planet.saturn);
      expect(separationDeg(j, s), lessThan(1.3));
      expect(j.altitudeDeg, greaterThan(30));
      expect(sunAlt(n), lessThan(-12));
    });

    test('Venus and Jupiter nearly touching after sunset, 17 June 2 BC', () {
      final n = night('conjunction-2bc');
      final v = planet(n, Planet.venus), j = planet(n, Planet.jupiter);
      expect(separationDeg(v, j), lessThan(0.4));
      expect(v.altitudeDeg, greaterThan(20));
      expect(sunAlt(n), lessThan(-6));
    });

    test('the Moon rose eclipsed over Jamaica, 29 Feb 1504 (Julian)', () {
      final n = night('columbus');
      expect(moonElongationDeg(n.utc), greaterThan(179));
      expect(moonHorizontal(n.utc, n.lat, n.lon).altitudeDeg, greaterThan(5));
      expect(sunAlt(n), lessThan(-6));
    });

    test('Jupiter high in the east for Galileo, 7 Jan 1610', () {
      final n = night('galileo');
      final j = planet(n, Planet.jupiter);
      expect(j.altitudeDeg, greaterThan(30));
      expect(j.azimuthDeg, inInclusiveRange(70, 130));
      expect(sunAlt(n), lessThan(-6));
    });

    test('no Moon for the Titanic', () {
      final n = night('titanic');
      expect(n.utc.difference(DateTime.utc(1912, 4, 15, 2, 38)).inSeconds.abs(), lessThan(60));
      expect(moonHorizontal(n.utc, n.lat, n.lon).altitudeDeg, lessThan(-20));
    });

    test('the Moon up in the west-southwest over Houston for the first step', () {
      final n = night('apollo11');
      final m = moonHorizontal(n.utc, n.lat, n.lon);
      expect(m.altitudeDeg, greaterThan(15));
      expect(m.azimuthDeg, inInclusiveRange(225, 270));
    });

    test('every night is in the range the map can show', () {
      for (final n in famousNights) {
        expect(n.year, inInclusiveRange(-2999, 3000), reason: n.id);
        expect(isMissingDate(n.year, n.month, n.day), isFalse, reason: n.id);
      }
    });
  });
}
