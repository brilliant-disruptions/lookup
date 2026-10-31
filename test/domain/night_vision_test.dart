import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/night_vision.dart';

void main() {
  group('from lux', () {
    test('a dark sky gets full deep red, so dark adaptation is never traded away', () {
      for (final lux in [0.0, 0.001, 0.3, 1.0, darkLux]) {
        expect(redStrengthFromLux(lux), 1, reason: '$lux lux');
      }
    });

    test('a lit room only tints, but night vision never switches itself off', () {
      for (final lux in [brightLux, 1000.0, 100000.0]) {
        expect(redStrengthFromLux(lux), minRedStrength, reason: '$lux lux');
      }
      expect(minRedStrength, greaterThan(0));
    });

    test('the darker it gets, the redder, without ever going backwards', () {
      var last = 0.0;
      for (var lux = brightLux; lux >= darkLux; lux /= 1.2) {
        final s = redStrengthFromLux(lux);
        expect(s, greaterThanOrEqualTo(last), reason: '$lux lux');
        last = s;
      }
      // A dim room (~20 lux) is clearly between the two ends.
      expect(redStrengthFromLux(20), inExclusiveRange(minRedStrength, 1));
    });

    test('a broken reading falls back to full red', () {
      expect(redStrengthFromLux(double.nan), 1);
    });
  });

  group('from screen brightness (iOS)', () {
    test('a dimmed screen means dark surroundings: full red', () {
      expect(redStrengthFromScreen(0), 1);
      expect(redStrengthFromScreen(darkScreen), 1);
    });

    test('a bright screen means a lit room: a light tint', () {
      expect(redStrengthFromScreen(brightScreen), minRedStrength);
      expect(redStrengthFromScreen(1), minRedStrength);
    });

    test('in between rises steadily as the screen dims', () {
      var last = 0.0;
      for (var b = 1.0; b >= 0; b -= 0.05) {
        final s = redStrengthFromScreen(b);
        expect(s, greaterThanOrEqualTo(last), reason: 'brightness $b');
        last = s;
      }
      expect(redStrengthFromScreen(0.4), inExclusiveRange(minRedStrength, 1));
    });
  });

  test('steps are coarse enough that sensor jitter does not repaint', () {
    expect(redStrengthFromLux(50), redStrengthFromLux(51));
    final s = redStrengthFromLux(37) * 20;
    expect(s, closeTo(s.roundToDouble(), 1e-9));
  });
}
