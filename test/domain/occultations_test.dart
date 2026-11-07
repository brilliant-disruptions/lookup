import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/occultations.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';

/// Occultations against IOTA's published predictions (lunar-occultations.com,
/// archived by the Wayback Machine). An occultation alert says "the Moon
/// covers it at 9:14": a wrong "covers" is a false alarm, so the call is
/// pinned at the edge of the path as well as the times in the middle of it.
/// See docs/moon-accuracy.md. Don't loosen these to make a change pass.
void main() {
  late SkyCatalog catalog;
  setUpAll(() {
    catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
        jsonDecode(File('assets/sky/constellations.json').readAsStringSync()),
        jsonDecode(File('assets/sky/proper_motion.json').readAsStringSync()));
  });

  double dm(int d, double m) => d < 0 ? d - m / 60 : d + m / 60;
  List<Occultation> at(double lat, double lon, DateTime around) => occultations(
      now: around.subtract(const Duration(hours: 12)), latDeg: lat, lonDeg: lon, stars: catalog.stars, days: 1);

  void expectTimes(Occultation o, DateTime? d, DateTime? r, Duration within, String where) {
    expect(o.covered, isTrue, reason: where);
    for (final (ours, iota) in [(o.disappears, d), (o.reappears, r)]) {
      if (iota == null) {
        expect(ours, isNull, reason: '$where: IOTA has no visible contact');
        continue;
      }
      final off = ours!.difference(iota).abs();
      expect(off, lessThanOrEqualTo(within), reason: '$where: $ours vs IOTA $iota');
      expect(off, lessThanOrEqualTo(o.plusMinus), reason: '$where: outside its own ±${o.plusMinus}');
    }
  }

  test('Mars, 8 Dec 2022: the US and Europe to within 25 s of IOTA', () {
    // Mars at opposition, behind the full Moon. Measured: ≤ 19 s everywhere.
    final rows = [
      ('Los Angeles', dm(33, 56.6), dm(-118, 24.5), (2, 30, 23), (3, 30, 11)),
      ('Denver', dm(39, 51.5), dm(-104, 40.0), (2, 44, 56), (3, 48, 30)),
      ('Chicago', dm(41, 52.9), dm(-87, 37.7), (3, 10, 58), (4, 4, 55)),
      ('Phoenix', dm(33, 32.1), dm(-112, 23.0), (2, 32, 23), (3, 30, 47)),
      ('Seattle', dm(47, 26.9), dm(-122, 18.6), (2, 51, 57), (3, 50, 35)),
      ('London', dm(51, 28.7), -27.7 / 60, (5, 0, 25), (5, 59, 31)),
      ('Madrid', dm(40, 28.3), dm(-3, 33.6), (5, 21, 15), (6, 7, 15)),
    ];
    for (final (where, lat, lon, d, r) in rows) {
      final o = at(lat, lon, DateTime.utc(2022, 12, 8, 3)).where((o) => o.body == 'Mars').single;
      expect(o.isPlanet, isTrue);
      expectTimes(o, DateTime.utc(2022, 12, 8, d.$1, d.$2, d.$3), DateTime.utc(2022, 12, 8, r.$1, r.$2, r.$3),
          const Duration(seconds: 25), where);
    }
  });

  test('Aldebaran 2017 and Spica 2025: bright stars to within 15 s of IOTA', () {
    // Measured: ≤ 9 s. Luanda only sees Spica go in.
    final rows = [
      ('Tokyo', dm(35, 45.9), dm(140, 23.2), 'Aldebaran', DateTime.utc(2017, 1, 9, 15, 2, 0), DateTime.utc(2017, 1, 9, 16, 9, 22)),
      ('Seoul', dm(37, 33.5), dm(126, 47.4), 'Aldebaran', DateTime.utc(2017, 1, 9, 14, 39, 25), DateTime.utc(2017, 1, 9, 15, 53, 27)),
      ('Taipei', dm(25, 4.2), dm(121, 33.1), 'Aldebaran', DateTime.utc(2017, 1, 9, 14, 53, 0), DateTime.utc(2017, 1, 9, 15, 30, 39)),
      ('Dakar', dm(14, 44.4), dm(-17, 29.4), 'Spica', DateTime.utc(2025, 1, 21, 2, 19, 10), DateTime.utc(2025, 1, 21, 3, 27, 40)),
      ('Accra', dm(5, 36.2), -10.1 / 60, 'Spica', DateTime.utc(2025, 1, 21, 2, 47, 22), DateTime.utc(2025, 1, 21, 4, 0, 3)),
      ('Lagos', dm(6, 34.6), dm(3, 19.3), 'Spica', DateTime.utc(2025, 1, 21, 2, 56, 54), DateTime.utc(2025, 1, 21, 3, 56, 28)),
      ('Luanda', dm(-8, 51.5), dm(13, 13.9), 'Spica', DateTime.utc(2025, 1, 21, 3, 36, 40), null),
    ];
    for (final (where, lat, lon, star, d, r) in rows) {
      final o = at(lat, lon, d).single;
      expect(o.body, star);
      expect(o.isPlanet, isFalse);
      expectTimes(o, d, r, const Duration(seconds: 15), where);
    }
  });

  test('near the southern limit it says "near the Moon", never "covers"', () {
    // Aldebaran, 9 Jan 2017, Taiwan. IOTA has Hualien, Makung and Chiayi
    // covered for 24, 14 and 10 minutes: grazes, inside our 1′ margin, so
    // they're near. Kaohsiung is just outside the path; Manila is far out.
    final around = DateTime.utc(2017, 1, 9, 15, 10);
    for (final (where, lat, lon) in [
      ('Hualien', dm(24, 1.4), dm(121, 37.1)),
      ('Makung', dm(23, 34.1), dm(119, 37.7)),
      ('Chiayi', dm(23, 27.7), dm(120, 23.6)),
      ('Kaohsiung', 22.63, 120.30),
    ]) {
      final o = at(lat, lon, around).single;
      expect(o.body, 'Aldebaran');
      expect(o.covered, isFalse, reason: where);
      expect((o.closestSepDeg - o.moonRadiusDeg).abs(), lessThanOrEqualTo(occultationStarMarginDeg), reason: where);
      expect(o.disappears, isNull);
      expect(o.reappears, isNull);
    }
    expect(at(14.6, 121.0, around), isEmpty, reason: 'Manila');
  });

  test('nothing in daylight: Aldebaran from Cairo, Sun 22° up', () {
    expect(at(dm(30, 7.3), dm(31, 24.3), DateTime.utc(2017, 1, 9, 13, 5)), isEmpty);
  });

  test('stars fainter than the floor are not tried', () {
    // Aldebaran's place, but mag 2.5.
    final faint = catalog.stars.firstWhere((s) => s.name == 'Aldebaran');
    final o = occultations(
        now: DateTime.utc(2017, 1, 9, 3),
        latDeg: dm(35, 45.9),
        lonDeg: dm(140, 23.2),
        stars: [Star(faint.raDeg, faint.decDeg, occultationMaxStarMag + 0.5, name: 'Faint', pm: faint.pm)],
        days: 1);
    expect(o, isEmpty);
  });

  test('annual aberration is typed in right: Meeus example 23.a', () {
    // θ Persei, 2028 Nov 13.19 TD, mean place of date α 41.5472°, δ 49.3485°:
    // Δα +30.045″, Δδ +6.697″. Up to 20″ on every star, so it matters at
    // the Moon's limb.
    final utc = DateTime.utc(2028, 11, 13, 4, 33, 36).subtract(const Duration(seconds: 72));
    final a = withAberration(const Equatorial(41.5472, 49.3485, 1), utc);
    expect((a.raDeg - 41.5472) * 3600, closeTo(30.045, 0.1));
    expect((a.decDeg - 49.3485) * 3600, closeTo(6.697, 0.1));
  });
}
