import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/geomagnetic.dart';
import 'package:lookup/domain/sky/sun.dart';

void main() {
  // Nashville, TN
  const lat = 36.17, lon = -86.78;

  test('noon is up, midnight is down', () {
    expect(sunAltitudeDeg(DateTime.utc(2026, 10, 21, 18), lat, lon),
        greaterThan(35)); // ~1pm CDT, late October → ~42°
    expect(sunAltitudeDeg(DateTime.utc(2026, 10, 21, 6), lat, lon),
        lessThan(-40));
  });

  test('darkness threshold and next dark window', () {
    expect(isDark(DateTime.utc(2026, 10, 21, 6), lat, lon), isTrue);
    expect(isDark(DateTime.utc(2026, 10, 21, 18), lat, lon), isFalse);
    final w = nextDarkWindow(DateTime.utc(2026, 10, 21, 18), lat, lon)!;
    // Sunset ~23:00Z (6pm CDT); civil dark ~23:30Z. Sunrise ~12:00Z next day.
    expect(w.start.isAfter(DateTime.utc(2026, 10, 21, 23)), isTrue);
    expect(w.start.isBefore(DateTime.utc(2026, 10, 22, 0, 10)), isTrue);
    expect(w.end.isAfter(DateTime.utc(2026, 10, 22, 11)), isTrue);
    expect(w.end.isBefore(DateTime.utc(2026, 10, 22, 12, 30)), isTrue);
  });

  test('polar summer has no dark window', () {
    expect(nextDarkWindow(DateTime.utc(2026, 6, 21), 78.2, 15.6), isNull);
  });

  test('geomagnetic latitude is higher than geographic in North America', () {
    final gm = geomagneticLatitudeDeg(lat, lon);
    expect(gm, closeTo(46, 3));
    // Tromsø sits right under the oval.
    expect(geomagneticLatitudeDeg(69.65, 18.96), closeTo(67, 3));
  });
}
