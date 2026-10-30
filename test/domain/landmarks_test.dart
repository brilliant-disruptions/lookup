import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
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

  test('a real ISS pass gets landmark words from its own orbit, or none', () {
    final record = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync())).single;
    final from = DateTime.utc(2026, 10, 20, 16);
    final passes = PassPredictor(latitude: lat, longitude: lon).predict(
        record: record, type: SkyEventType.iss, from: from, to: from.add(const Duration(days: 21)), minPeakElevationDeg: 10);
    expect(passes, isNotEmpty);
    for (final p in passes) {
      final words = passLandmarkWords(p, catalog, lat, lon);
      if (words != null) expect(words, startsWith('passing '));
    }
    // Not a pass, or no elements: nothing claimed.
    final aurora = SkyEvent(
        id: 'aurora:x', type: SkyEventType.auroraNow, start: from, peak: from, end: from.add(const Duration(hours: 1)),
        peakElevationDeg: 20, riseAzimuthDeg: 0, peakAzimuthDeg: 0, setAzimuthDeg: 0);
    expect(passLandmarkWords(aurora, catalog, lat, lon), isNull);
    expect(passLandmarkWords(passes.first.copyWith(details: const {}), catalog, lat, lon), isNull);
  });

  test('landmarks ride on the event as words and points along the pass', () {
    final start = DateTime.utc(2026, 10, 30, 1);
    final e = SkyEvent(
        id: 'iss:x', type: SkyEventType.iss, start: start, peak: start.add(const Duration(minutes: 2)),
        end: start.add(const Duration(minutes: 4)), peakElevationDeg: 60, riseAzimuthDeg: 250, peakAzimuthDeg: 180, setAzimuthDeg: 100);
    final marks = [
      Landmark('Jupiter', start.add(const Duration(minutes: 1)), const Horizontal(200, 40), 1.2, above: false),
      Landmark('Vega', start.add(const Duration(minutes: 3)), const Horizontal(120, 30), 4),
    ];
    final withMarks = withLandmarks(e, marks);
    expect(withMarks.details['landmarks'], 'passing right by Jupiter, then close to Vega');
    final points = landmarkPoints(SkyEvent.fromJson(jsonDecode(jsonEncode(withMarks.toJson())) as Map<String, Object?>));
    expect(points.map((p) => p.name), ['Jupiter', 'Vega']);
    expect(points[0].f, closeTo(0.25, 1e-9));
    expect(points[0].above, isFalse);
    expect(points[0].close, isTrue);
    expect(points[1].f, closeTo(0.75, 1e-9));
    expect(points[1].above, isTrue);
    // Nothing nearby: the event is left alone.
    expect(identical(withLandmarks(e, const []), e), isTrue);
    expect(landmarkPoints(e), isEmpty);
  });

  test('where a landmark is: planets, the Moon and named stars', () {
    final jupiter = landmarkDirection('Jupiter', catalog, t, lat, lon)!;
    final want = planetHorizontal(Planet.jupiter, t, lat, lon);
    expect(jupiter.azimuthDeg, want.azimuthDeg);
    expect(jupiter.altitudeDeg, want.altitudeDeg);
    final vega = landmarkDirection('Vega', catalog, t, lat, lon)!;
    expect(vega.altitudeDeg, greaterThan(30)); // high in the west at 8 PM
    expect(landmarkDirection('the Moon', null, t, lat, lon), isNotNull);
    expect(landmarkDirection('Vega', null, t, lat, lon), isNull); // stars need the catalogue
    expect(landmarkDirection('Nowhere', catalog, t, lat, lon), isNull);
  });
}
