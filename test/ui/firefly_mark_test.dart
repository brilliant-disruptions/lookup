import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/kit/firefly_mark.dart';

void main() {
  group('fireflyCurl', () {
    const at = Offset(100, 100), from = Offset(0, 0);

    test('starts where it came from and runs up to the firefly, oldest first', () {
      final c = fireflyCurl(at, from);
      expect(c, hasLength(12));
      expect(c.first, from);
      // The firefly itself isn't a spark; the last spark is just short of it.
      expect((c.last - at).distance, inExclusiveRange(1, 20));
      for (var i = 1; i < c.length; i++) {
        expect((c[i] - at).distance, lessThan((c[i - 1] - at).distance), reason: 'spark $i');
      }
    });

    test('bends to the side asked for', () {
      // Travelling down-right; a positive curl bows to the left of travel (down-left, +y −x).
      final mid = fireflyCurl(at, from, curl: 0.3)[6];
      final straight = fireflyCurl(at, from, curl: 0)[6];
      expect(mid.dx, lessThan(straight.dx));
      expect(mid.dy, greaterThan(straight.dy));
      final other = fireflyCurl(at, from, curl: -0.3)[6];
      expect(other.dx, greaterThan(straight.dx));
    });

    test('nothing to draw when it has nowhere to come from', () {
      expect(fireflyCurl(at, at), isEmpty);
      expect(fireflyCurl(at, from, sparks: 0), isEmpty);
    });
  });

  test('firefly green is not the sun\'s orange or the app\'s status green', () {
    // Hue in degrees.
    double hue(Color c) {
      final r = c.r, g = c.g, b = c.b;
      final mx = [r, g, b].reduce((a, b) => a > b ? a : b), mn = [r, g, b].reduce((a, b) => a < b ? a : b);
      final d = mx - mn;
      final h = mx == r ? ((g - b) / d) % 6 : mx == g ? (b - r) / d + 2 : (r - g) / d + 4;
      return (h * 60 + 360) % 360;
    }

    final h = hue(fireflyGlow);
    expect(h, inInclusiveRange(70, 100)); // yellow-green
    expect((h - hue(const Color(0xFFFFB347))).abs(), greaterThan(40)); // the old amber
    expect((hue(const Color(0xFF3DD68C)) - h).abs(), greaterThan(40)); // LookUpColors.good
  });
}
