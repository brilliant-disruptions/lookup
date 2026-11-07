import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/astro.dart';

/// Where the Moon is from the ground, against JPL Horizons (topocentric,
/// apparent, airless). This is the audit behind docs/moon-accuracy.md: it
/// decides whether LookUp can say the Moon will cover a star or planet.
/// history_test.dart checks the geocentric Moon; this checks the parallax
/// on top, which is up to a degree and the whole of an occultation.
void main() {
  // (lat, lon, UTC, Horizons azimuth, Horizons elevation). Sampled from the
  // full audit (4 sites, every 53 h, Nov 2026 – Nov 2028), with the worst
  // row above the horizon at each of Chicago and Sydney.
  final rows = [
    (41.88, -87.63, DateTime.utc(2026, 11, 5, 10), 104.919221378, 13.156806804),
    (41.88, -87.63, DateTime.utc(2027, 5, 12, 3), 263.157648989, 36.001525368),
    (41.88, -87.63, DateTime.utc(2027, 11, 22, 11), 138.938140404, 40.851868362),
    (41.88, -87.63, DateTime.utc(2028, 6, 8, 5), 156.268619157, 17.822713513),
    (41.88, -87.63, DateTime.utc(2026, 11, 25, 7), 215.492684598, 72.170079226), // worst here
    (51.5, -0.13, DateTime.utc(2026, 11, 1), 82.566915667, 23.144072139),
    (51.5, -0.13, DateTime.utc(2027, 5, 23, 4), 204.563491180, 7.210396117),
    (51.5, -0.13, DateTime.utc(2027, 12, 10, 3), 284.733463009, 9.280539636),
    (51.5, -0.13, DateTime.utc(2028, 6, 25, 21), 279.895234714, 9.098155115),
    (-33.87, 151.21, DateTime.utc(2026, 11, 9, 20), 109.651897333, 12.246976114),
    (-33.87, 151.21, DateTime.utc(2027, 5, 16, 13), 302.482942278, 47.716893148),
    (-33.87, 151.21, DateTime.utc(2027, 11, 29, 2), 42.875286011, 80.123211564),
    (-33.87, 151.21, DateTime.utc(2028, 6, 14, 20), 350.473595468, 55.010295994),
    (-33.87, 151.21, DateTime.utc(2028, 3, 9, 16), 304.401672102, 26.557033060), // worst of all
    (-0.18, -78.47, DateTime.utc(2026, 11, 5, 10), 91.450107332, 28.685461250),
    (-0.18, -78.47, DateTime.utc(2027, 5, 9, 22), 322.204265877, 54.731921712),
    (-0.18, -78.47, DateTime.utc(2027, 11, 20, 6), 74.391830766, 19.364553427),
    (-0.18, -78.47, DateTime.utc(2028, 5, 23, 18), 320.590904719, 58.279585585),
  ];

  test('the Moon from the ground is within 7 arcminutes of Horizons', () {
    // Measured over 648 rows above the horizon: median 1.7′, 95% under 3.7′,
    // worst 6.3′. Nearly all of it is Schlyter's Moon (geocentric worst
    // 6.1′); the parallax adds under 0.5′. An occultation needs the limb
    // to well under 1′, so this is why LookUp doesn't predict them yet.
    for (final (lat, lon, utc, az, el) in rows) {
      final sep = separationDeg(moonHorizontal(utc, lat, lon), Horizontal(az, el)) * 60;
      expect(sep, lessThan(7), reason: '$utc at $lat, $lon');
    }
  });
}
