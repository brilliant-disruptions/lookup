import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/sun.dart' as sun;

void main() {
  test('the Moon is opposite the Sun at every NASA lunar eclipse 2026–2030', () {
    // Greatest eclipse times, NASA GSFC eclipse pages.
    final eclipses = [
      DateTime.utc(2026, 3, 3, 11, 34), DateTime.utc(2026, 8, 28, 4, 13),
      DateTime.utc(2027, 2, 20, 23, 13), DateTime.utc(2027, 7, 18, 16, 3),
      DateTime.utc(2027, 8, 17, 7, 14), DateTime.utc(2028, 1, 12, 4, 13),
      DateTime.utc(2028, 7, 6, 18, 20), DateTime.utc(2028, 12, 31, 16, 52),
      DateTime.utc(2029, 6, 26, 3, 22), DateTime.utc(2029, 12, 20, 22, 42),
      DateTime.utc(2030, 6, 15, 18, 33), DateTime.utc(2030, 12, 9, 22, 28),
    ];
    for (final t in eclipses) {
      expect(moonElongationDeg(t), greaterThan(178), reason: '$t');
      expect(moonIllumination(t), greaterThan(0.99), reason: '$t');
    }
    // And a new moon is dark.
    expect(moonIllumination(DateTime.utc(2026, 11, 9, 7, 2)), lessThan(0.01));
  });

  test('Venus and Jupiter: the 2025-08-12 conjunction', () {
    double sep(DateTime t) =>
        equatorialSeparationDeg(planetEquatorial(Planet.venus, t), planetEquatorial(Planet.jupiter, t));
    expect(sep(DateTime.utc(2025, 8, 12, 10)), lessThan(1.2));
    expect(sep(DateTime.utc(2025, 7, 15)), greaterThan(4));
  });

  test('sun position agrees with the existing altitude model', () {
    for (final t in [DateTime.utc(2026, 10, 21, 18), DateTime.utc(2026, 6, 21, 3), DateTime.utc(2027, 1, 5, 12)]) {
      final h = toHorizontal(sunEquatorial(t), t, 36.17, -86.78);
      expect(h.altitudeDeg, closeTo(sun.sunAltitudeDeg(t, 36.17, -86.78), 0.3), reason: '$t');
    }
  });

  test('solar longitude: equinox and solstice', () {
    expect(solarLongitudeDeg(DateTime.utc(2027, 3, 20, 20, 25)), anyOf(closeTo(0, 0.05), closeTo(360, 0.05)));
    expect(solarLongitudeDeg(DateTime.utc(2026, 12, 21, 20, 50)), closeTo(270, 0.05));
  });

  test('Polaris-ish: a pole-star position sits at the observer latitude', () {
    final t = DateTime.utc(2026, 10, 25, 4);
    final h = toHorizontal(const Equatorial(0, 89.99, 1), t, 36.17, -86.78);
    expect(h.altitudeDeg, closeTo(36.17, 0.05));
    expect(h.azimuthDeg % 360, anyOf(closeTo(0, 1), closeTo(360, 1)));
  });
}
