import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/alert_chart.dart';

void main() {
  test('a west-southwest to east pass runs left to right through the south, highest in the middle', () {
    // Rises WSW (247°), highest S (180°), sets E (95°): facing south, west is on the right.
    final c = AlertChart.forPass(riseAz: 247, peakAz: 180, setAz: 95, peakEl: 62);
    expect(c.rise.$1, greaterThan(c.set.$1)); // west on the right when facing south
    expect(c.centerAz, closeTo(171, 1));
    expect(c.peak.$2, closeTo(62 / c.topAlt, 1e-9));
    for (final p in c.path) {
      expect(p.$1, inInclusiveRange(0, 1));
      expect(p.$2, inInclusiveRange(0, 1));
      expect(p.$2, lessThanOrEqualTo(c.peak.$2 + 1e-9));
    }
    final words = [for (final w in c.compass) w.$1];
    expect(words, containsAll(['S', 'SE', 'SW']));
  });

  test('a pass across the north never jumps the 0°/360° seam', () {
    // Rises NW (300°), highest N (0°), sets NE (60°).
    final c = AlertChart.forPass(riseAz: 300, peakAz: 0, setAz: 60, peakEl: 30);
    expect(c.centerAz, closeTo(0, 1));
    for (var i = 1; i < c.path.length; i++) {
      // Monotonic and no big hops.
      expect(c.path[i].$1 - c.path[i - 1].$1, inInclusiveRange(0, 0.05));
    }
    expect([for (final w in c.compass) w.$1], contains('N'));
  });

  test('a near-overhead pass with a peak direction that disagrees still goes the short way', () {
    // Rises SW (225°), sets NE (45°); the peak azimuth jitters to 120° (opposite turn).
    final c = AlertChart.forPass(riseAz: 225, peakAz: 120, setAz: 45, peakEl: 86);
    expect(c.spanAz, lessThanOrEqualTo(360));
    for (final p in c.path) {
      expect(p.$1, inInclusiveRange(0, 1));
    }
    expect(c.topAlt, 95); // capped
  });

  test('low passes get a view tall enough to read, starting no higher than their peak', () {
    final c = AlertChart.forPass(riseAz: 200, peakAz: 180, setAz: 160, peakEl: 6);
    expect(c.topAlt, 35);
    expect(c.rise.$2, closeTo(6 / 35, 1e-9)); // starts at its peak height, not above it
    expect(c.spanAz, 120); // at least 120° wide
  });
}
