import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/plan/where_to_go.dart';
import 'package:lookup/domain/sky/direction.dart';
import 'package:lookup/domain/sky/skyglow.dart';
import 'package:lookup/domain/sky/visibility.dart';

void main() {
  late SkyGlowMap map;
  setUpAll(() {
    map = SkyGlowMap.decode(Uint8List.fromList(gzip.decode(File('assets/sky/skyglow.bin.gz').readAsBytesSync())));
  });

  SkyDarkness? at(double lat, double lon) {
    final m = map.sqmAt(lat, lon);
    return m == null ? null : darknessForSqm(m);
  }

  test('known skies come out the right class', () {
    expect(at(36.16, -86.78), SkyDarkness.city); // downtown Nashville
    expect(at(40.758, -73.985), SkyDarkness.city); // Times Square
    expect(at(36.55, -84.80), SkyDarkness.dark); // Pickett CCC, a dark-sky park
    expect(at(41.663, -77.823), SkyDarkness.dark); // Cherry Springs, PA
    expect(at(29.25, -103.25), SkyDarkness.dark); // Big Bend
  });

  test('a lakefront city is judged by its land, not the lake', () {
    final m = map.sqmNear(41.88, -87.63); // the Loop, Chicago
    expect(m, isNotNull);
    expect(darknessForSqm(m!), SkyDarkness.city);
  });

  test('water is never a place to go', () {
    expect(map.sqmAt(30, -40), isNull); // mid-Atlantic
    expect(map.sqmAt(43.8, -87.0), isNull); // Lake Michigan
    expect(map.darkerSpots(30, -40), isEmpty);
  });

  test('from Nashville: real dark skies within reach, nearest first, spread out, all on land', () {
    final spots = map.darkerSpots(36.16, -86.78);
    expect(spots, isNotEmpty);
    final here = map.sqmAt(36.16, -86.78)!;
    for (final s in spots) {
      expect(s.sqm, greaterThanOrEqualTo(here + 0.5));
      expect(s.distanceKm, lessThanOrEqualTo(150));
      expect(map.sqmAt(s.lat, s.lon), isNotNull);
    }
    expect([for (final s in spots) s.distanceKm], orderedEquals([...spots.map((s) => s.distanceKm)]..sort()));
    for (final (i, a) in spots.indexed) {
      for (final b in spots.skip(i + 1)) {
        expect(distanceKm(a.lat, a.lon, b.lat, b.lon), greaterThanOrEqualTo(40));
      }
    }
    expect(spots.any((s) => s.sqm >= darkSkySqm), isTrue);
  });

  test('already under a dark sky: nothing much darker to suggest', () {
    expect(map.darkerSpots(29.25, -103.25), isEmpty); // Big Bend
  });

  test('spots report where they are in words', () {
    final s = map.darkerSpots(40.758, -73.985); // Manhattan
    expect(s, isNotEmpty);
    for (final x in s) {
      expect(compassWord(x.bearingDeg), isNotEmpty);
      expect(x.bearingDeg, inInclusiveRange(0, 360));
    }
  });

  test('rejects a file that is not a sky glow map', () {
    expect(() => SkyGlowMap.decode(Uint8List.fromList(List.filled(40, 0))), throwsFormatException);
  });
}
