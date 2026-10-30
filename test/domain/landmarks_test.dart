import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/landmarks.dart';

void main() {
  const lat = 36.17, lon = -86.78; // Nashville
  final t = DateTime.utc(2026, 10, 30, 1); // 8 PM CDT: Vega high in the west
  late SkyCatalog catalog;
  setUpAll(() {
    Map<String, Object?> read(String f) => jsonDecode(File('assets/sky/$f').readAsStringSync()) as Map<String, Object?>;
    catalog = SkyCatalog.fromJson(read('stars.json'), read('constellations.json'), read('proper_motion.json'));
  });

  /// A straight track at constant azimuth, from 10° up to 80°.
  List<({DateTime t, Horizontal h})> sweep(double az, {double offsetDeg = 0}) => [
        for (var i = 0; i <= 70; i++)
          (t: t.add(Duration(seconds: i * 3)), h: Horizontal(az + offsetDeg, 10.0 + i)),
      ];

  test('a pass through Vega is found by Vega, and words say so', () {
    final vega = catalog.stars.firstWhere((s) => s.name == 'Vega').horizontal(t, lat, lon);
    expect(vega.altitudeDeg, greaterThan(30));
    final marks = landmarksAlong(track: sweep(vega.azimuthDeg), catalog: catalog, lat: lat, lon: lon);
    expect(marks.map((m) => m.name), contains('Vega'));
    final v = marks.firstWhere((m) => m.name == 'Vega');
    expect(v.distanceDeg, lessThan(1.5));
    expect(landmarkWords([v]), 'passing right by Vega');
  });

  test('nothing nearby, nothing claimed', () {
    final vega = catalog.stars.firstWhere((s) => s.name == 'Vega').horizontal(t, lat, lon);
    // 40° of azimuth away from Vega: whatever else it passes must be close.
    final marks = landmarksAlong(track: sweep(vega.azimuthDeg + 40), catalog: catalog, lat: lat, lon: lon);
    expect(marks.where((m) => m.name == 'Vega'), isEmpty);
    for (final m in marks) {
      expect(m.distanceDeg, lessThanOrEqualTo(6));
    }
    expect(landmarkWords(const []), isNull);
  });

  test('in the order the pass reaches them, at most two', () {
    final a = Landmark('Altair', t.add(const Duration(minutes: 2)), const Horizontal(0, 40), 3);
    final b = Landmark('Vega', t, const Horizontal(0, 60), 1);
    expect(landmarkWords([b, a]), 'passing right by Vega, then close to Altair');
  });
}
