import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/transits/transit_finder.dart';
import 'package:satellite_observer/satellite_observer.dart';

void main() {
  late OmmRecord iss;
  late TransitFinder finder;
  final from = DateTime.utc(2026, 10, 20, 16), to = DateTime.utc(2026, 10, 27, 16);

  setUpAll(() {
    iss = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync())).single;
    finder = TransitFinder(record: iss);
  });

  /// Brute force: closest approach (deg) from a spot, sampled every 10 ms.
  double bruteMinSep(TransitBody body, double lat, double lon, DateTime around) {
    final sat = SatelliteObserver(elements: iss.toElements(), observer: Observer(latitudeDeg: lat, longitudeDeg: lon));
    var best = double.infinity;
    for (var ms = -3000; ms <= 3000; ms += 10) {
      final t = around.add(Duration(milliseconds: ms));
      final look = sat.lookAngleAt(t);
      final h = body == TransitBody.sun ? sunHorizontal(t, lat, lon) : moonHorizontal(t, lat, lon);
      final s = separationDeg(Horizontal(look.azimuthDeg, look.elevationDeg), h);
      if (s < best) best = s;
    }
    return best;
  }

  test('finds near-misses and sends people to a spot where the station crosses the disk', () {
    final london = finder.find(latDeg: 51.5, lonDeg: -0.12, from: from, to: to);
    expect(london, isNotEmpty);
    for (final t in london) {
      expect(t.travelKm, lessThanOrEqualTo(50));
      expect(t.crossing.inMilliseconds, inInclusiveRange(200, 6000));
      // Independent check at the recommended site.
      final s = bruteMinSep(t.body, t.siteLat, t.siteLon, t.time);
      expect(s, lessThan(t.radiusDeg * 0.5), reason: '${t.body.label} ${t.time}');
    }
  });

  test('standing on the centre line needs no travel', () {
    final t = finder.find(latDeg: 51.5, lonDeg: -0.12, from: from, to: to).first;
    final there = finder
        .find(latDeg: t.siteLat, lonDeg: t.siteLon, from: t.time.subtract(const Duration(hours: 1)), to: t.time.add(const Duration(hours: 1)))
        .where((x) => x.body == t.body)
        .single;
    expect(there.visibleHere, isTrue);
    expect(there.travelKm, 0);
    expect(there.time.difference(t.time).inMilliseconds.abs(), lessThan(200));
  });

  test('nothing when the Sun and Moon are never near a pass in reach', () {
    final tight = TransitFinder(record: iss, maxTravelKm: 1);
    final found = tight.find(latDeg: 36.17, lonDeg: -86.78, from: from, to: to);
    for (final t in found) {
      expect(t.travelKm, lessThanOrEqualTo(1));
    }
  });
}
