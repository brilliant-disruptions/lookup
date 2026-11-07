import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/moon_times.dart';

/// The full-Moon moonrise alert fires at these times, so they're pinned to
/// published values: USNO full Moons and moonrises (aa.usno.navy.mil) and
/// JPL Horizons distances.
void main() {
  group('full Moons match USNO', () {
    // USNO full-Moon instants (UTC) and JPL Horizons distances (km) at them.
    final published = {
      DateTime.utc(2026, 1, 3, 10, 3): 362312,
      DateTime.utc(2026, 6, 29, 23, 56): 405255,
      DateTime.utc(2026, 10, 26, 4, 12): 368872,
      DateTime.utc(2026, 11, 24, 14, 53): 360766,
      DateTime.utc(2026, 12, 24, 1, 28): 356738,
      DateTime.utc(2027, 1, 22, 12, 17): 357644,
      DateTime.utc(2027, 7, 18, 15, 45): 405979,
    };
    final found = fullMoonsBetween(DateTime.utc(2026, 1, 1), DateTime.utc(2028, 1, 1));

    test('one a lunation, no doubles or gaps', () {
      // USNO lists 13 full Moons in 2026 and 12 in 2027.
      expect(found, hasLength(25));
    });

    test('to within 10 minutes', () {
      // Schlyter's Moon is good to a few arcminutes: measured worst case is
      // 8 min (2026-11-24). An alert says "rising tonight", not a minute.
      for (final e in published.entries) {
        final f = found.firstWhere((f) => f.at.difference(e.key).inHours.abs() < 12);
        expect(f.at.difference(e.key).inSeconds.abs(), lessThan(600), reason: '${e.key}');
      }
    });

    test('distance to within 500 km of JPL', () {
      // Measured: 100–440 km long across 2026–27.
      for (final e in published.entries) {
        final f = found.firstWhere((f) => f.at.difference(e.key).inHours.abs() < 12);
        expect(f.distanceKm, closeTo(e.value, 500), reason: '${e.key}');
      }
    });

    test('supermoons are only the two inside 360,000 km', () {
      // 2026-11-24 is 360,766 km: often called a supermoon elsewhere, but
      // outside our line, and it must not flip.
      final supers = found.where((f) => f.supermoon).map((f) => f.at.toIso8601String().substring(0, 10));
      expect(supers, ['2026-12-24', '2027-01-22']);
    });
  });

  group('moonrise matches USNO, Chicago', () {
    const lat = 41.88, lon = -87.63;
    // USNO rise times (UTC, to the minute) and the side of the sky it's in.
    final cases = {
      DateTime.utc(2026, 11, 24, 22, 8): 'north of east', // winter full Moon rises north
      DateTime.utc(2026, 12, 24, 23, 8): 'north of east',
      DateTime.utc(2027, 6, 18, 0, 50): 'south of east', // summer full Moon rises south
    };
    for (final e in cases.entries) {
      test('${e.key}', () {
        final day = DateTime.utc(e.key.year, e.key.month, e.key.day);
        final rises = moonrisesBetween(day, day.add(const Duration(days: 1)), lat, lon);
        expect(rises, hasLength(1));
        // USNO rounds to the minute; the finder is good to 30 s.
        expect(rises.single.at.difference(e.key).inSeconds.abs(), lessThan(90));
        final az = rises.single.azimuthDeg;
        expect(e.value == 'north of east' ? az < 90 : az > 90, isTrue, reason: 'azimuth $az');
      });
    }

    test('a day with no moonrise has none', () {
      // The Moon rises ~50 min later each day, so about once a month a day
      // has none. An invented rise would be an alert at the wrong time.
      // USNO: 23:07 on 2026-11-25 UTC, nothing on the 26th, 00:18 on the 27th.
      final rises = moonrisesBetween(DateTime.utc(2026, 11, 25), DateTime.utc(2026, 11, 28), lat, lon);
      expect(rises.map((r) => r.at.day), [25, 27]);
    });
  });
}
