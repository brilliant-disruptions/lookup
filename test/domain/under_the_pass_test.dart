import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
import 'package:lookup/domain/satellites/under_the_pass.dart';

void main() {
  late OmmRecord iss;
  late List<Place> places;
  setUpAll(() {
    iss = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync())).single;
    places = Place.fromJson(jsonDecode(File('assets/sky/places.json').readAsStringSync()) as List<Object?>);
  });

  test('the station is 10° up within about 1,400 km of the point below it', () {
    expect(UnderThePass.footprintDeg(420) * 111.2, closeTo(1390, 40));
    expect(UnderThePass.footprintDeg(420, minElevationDeg: 0), greaterThan(UnderThePass.footprintDeg(420)));
  });

  test('a real pass over London: millions under it across Europe, London itself left out', () {
    final e = PassPredictor(latitude: 51.5, longitude: -0.12)
        .predict(
          record: iss,
          type: SkyEventType.iss,
          from: DateTime.utc(2026, 10, 20, 16),
          to: DateTime.utc(2026, 10, 22),
          minPeakElevationDeg: 10,
        )
        .first;
    expect(e.start.difference(DateTime.utc(2026, 10, 21, 4, 33)).inMinutes.abs(), lessThan(2));
    final u = UnderThePass.estimate(track: UnderThePass.trackOf(e), places: places, hereLat: 51.5, hereLon: -0.12)!;
    expect(u.people, greaterThan(50000000));
    expect(u.biggest, contains('Paris'));
    expect(u.biggest, isNot(contains('London')));
    expect(u.places, greaterThan(100));
  });

  test('nobody is counted in daylight', () {
    // The same track, moved to midday over Europe.
    final noon = DateTime.utc(2026, 6, 21, 12);
    final track = [
      for (var i = 0; i < 20; i++) (t: noon.add(Duration(seconds: 15 * i)), lat: 48.0 + i * 0.4, lon: 2.0 + i * 0.8, altKm: 420.0),
    ];
    expect(UnderThePass.estimate(track: track, places: places, hereLat: 51.5, hereLon: -0.12), isNull);
  });

  test('a pass with no elements has no track', () {
    final t = DateTime.utc(2026, 10, 21, 4, 33);
    final e = SkyEvent(
      id: 'iss:x',
      type: SkyEventType.iss,
      start: t,
      peak: t.add(const Duration(minutes: 2)),
      end: t.add(const Duration(minutes: 4)),
      peakElevationDeg: 50,
      riseAzimuthDeg: 250,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 100,
    );
    expect(UnderThePass.trackOf(e), isEmpty);
    expect(UnderThePass.estimate(track: const [], places: places, hereLat: 0, hereLon: 0), isNull);
  });

  test('words', () {
    expect(roundedPeople(3412000), '3.4 million');
    expect(roundedPeople(140123456), '140 million');
    expect(roundedPeople(10400000), '10 million');
    expect(roundedPeople(2000000), '2 million');
    expect(roundedPeople(872000), '870,000');
    expect(roundedPeople(50000), '50,000');
    expect(
      const UnderThePass(people: 1, places: 41, biggest: ['Atlanta', 'Louisville', 'Memphis']).placesWords,
      'Atlanta, Louisville, Memphis and 38 other places',
    );
    expect(const UnderThePass(people: 1, places: 2, biggest: ['Atlanta', 'Louisville']).placesWords, 'Atlanta and Louisville');
    expect(const UnderThePass(people: 1, places: 1, biggest: ['Atlanta']).placesWords, 'Atlanta');
    expect(const UnderThePass(people: 1, places: 4, biggest: ['A', 'B', 'C']).placesWords, 'A, B, C and 1 other place');
  });
}
