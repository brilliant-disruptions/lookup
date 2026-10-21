import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/aurora/aurora_rules.dart';

void main() {
  test('Kp needed drops as geomagnetic latitude rises', () {
    expect(kpNeededForGeomagneticLatitude(70), 0);
    expect(kpNeededForGeomagneticLatitude(61), closeTo(3, 0.01));
    expect(kpNeededForGeomagneticLatitude(55), closeTo(5, 0.01));
    expect(kpNeededForGeomagneticLatitude(56.5), closeTo(4.5, 0.01));
    expect(kpNeededForGeomagneticLatitude(40), closeTo(9, 0.01));
    expect(kpNeededForGeomagneticLatitude(30), greaterThan(9));
    expect(kpNeededForGeomagneticLatitude(-61), closeTo(3, 0.01));
  });

  test('Nashville needs a severe storm; Minneapolis a moderate one', () {
    expect(kpNeededAt(36.17, -86.78), inInclusiveRange(7, 9));
    expect(kpNeededAt(44.98, -93.27), inInclusiveRange(5, 7));
  });

  test('outlook uses only the dark window', () {
    final now = DateTime.utc(2026, 10, 21, 18); // afternoon in Minneapolis
    List<KpForecastPoint> f(double nightKp, double dayKp) => [
          for (var h = 0; h < 48; h += 3)
            KpForecastPoint(
              time: now.add(Duration(hours: h)),
              // 03Z–09Z is deep night; make those the storm bins
              kp: (now.add(Duration(hours: h)).hour >= 3 &&
                      now.add(Duration(hours: h)).hour <= 9)
                  ? nightKp
                  : dayKp,
              kind: 'predicted',
            ),
        ];
    final likely = auroraOutlook(
        now: now, latDeg: 44.98, lonDeg: -93.27, forecast: f(7.67, 2));
    expect(likely.level, AuroraOutlookLevel.likely);
    expect(likely.maxKpTonight, 7.67);

    final none = auroraOutlook(
        now: now, latDeg: 44.98, lonDeg: -93.27, forecast: f(2, 2));
    expect(none.level, AuroraOutlookLevel.none);
  });

  test('ovation grid lookup is lon-major with a scan fallback', () {
    final grid = <List<num>>[];
    for (var lon = 0; lon < 360; lon++) {
      for (var lat = -90; lat <= 90; lat++) {
        grid.add([lon, lat, lon == 273 && lat == 45 ? 37 : 0]);
      }
    }
    expect(ovationProbabilityAt(grid, 44.98, -86.78), 37); // -86.78 → 273
    expect(ovationProbabilityAt(grid, 10, 10), 0);
    final shuffled = [...grid.reversed];
    expect(ovationProbabilityAt(shuffled, 44.98, -86.78), 37);
  });

  test('aurora-now gate', () {
    final night = DateTime.utc(2026, 10, 22, 4);
    final day = DateTime.utc(2026, 10, 21, 18);
    const lat = 44.98, lon = -93.27;
    expect(
        auroraNow(now: day, latDeg: lat, lonDeg: lon, estimatedKp: 8,
                ovationProbability: 60)
            .alert,
        isFalse);
    expect(
        auroraNow(now: night, latDeg: lat, lonDeg: lon, estimatedKp: 2,
                ovationProbability: 60)
            .alert,
        isFalse);
    expect(
        auroraNow(now: night, latDeg: lat, lonDeg: lon, estimatedKp: 6,
                ovationProbability: 5)
            .alert,
        isFalse);
    expect(
        auroraNow(now: night, latDeg: lat, lonDeg: lon, estimatedKp: 6,
                ovationProbability: 40, cloudCoverPercent: 90)
            .alert,
        isFalse);
    expect(
        auroraNow(now: night, latDeg: lat, lonDeg: lon, estimatedKp: 6,
                ovationProbability: 40, cloudCoverPercent: 10)
            .alert,
        isTrue);
  });
}
