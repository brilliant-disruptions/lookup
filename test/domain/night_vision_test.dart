import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/night_vision.dart';

void main() {
  group('Auto, from lux', () {
    test('a dark sky gets full deep red, so dark adaptation is never traded away', () {
      for (final lux in [0.0, 0.001, 0.3, 1.0, darkLux]) {
        expect(redStrengthFromLux(lux), 1, reason: '$lux lux');
      }
    });

    test('a lit room shows the true colours: red indoors only costs readability', () {
      for (final lux in [brightLux, 300.0, 1000.0, 100000.0]) {
        expect(redStrengthFromLux(lux), 0, reason: '$lux lux');
      }
    });

    test('the darker it gets, the redder, without ever going backwards', () {
      var last = 0.0;
      for (var lux = brightLux; lux >= darkLux; lux /= 1.2) {
        final s = redStrengthFromLux(lux);
        expect(s, greaterThanOrEqualTo(last), reason: '$lux lux');
        last = s;
      }
      // A dim room or TV light (~15 lux) is clearly red, but not all the way.
      expect(redStrengthFromLux(15), inInclusiveRange(0.5, 0.7));
    });

    test('a broken reading falls back to full red', () {
      expect(redStrengthFromLux(double.nan), 1);
    });
  });

  group('Auto, from screen brightness (iOS)', () {
    test('a dimmed screen means dark surroundings: full red', () {
      expect(redStrengthFromScreen(0), 1);
      expect(redStrengthFromScreen(darkScreen), 1);
    });

    test('a bright screen means a lit room: true colours', () {
      expect(redStrengthFromScreen(brightScreen), 0);
      expect(redStrengthFromScreen(1), 0);
    });

    test('in between rises steadily as the screen dims', () {
      var last = 0.0;
      for (var b = 1.0; b >= 0; b -= 0.05) {
        final s = redStrengthFromScreen(b);
        expect(s, greaterThanOrEqualTo(last), reason: 'brightness $b');
        last = s;
      }
      expect(redStrengthFromScreen(0.4), inExclusiveRange(0, 1));
    });
  });

  test('steps are coarse enough that sensor jitter does not repaint', () {
    expect(redStrengthFromLux(50), redStrengthFromLux(51));
    final s = redStrengthFromLux(37) * 20;
    expect(s, closeTo(s.roundToDouble(), 1e-9));
  });

  group('How red, like Auto-Brightness', () {
    test('Auto alone is what the light says', () {
      expect(nightVisionStrength(auto: true, autoRed: 0.6, nudge: 0, level: 0.2), 0.6);
    });

    test('a nudge moves Auto from where it is, and follows the light from there', () {
      final nudge = nudgeFor(target: 0.3, autoRed: 0.6); // a bit less red in the dim room
      expect(nightVisionStrength(auto: true, autoRed: 0.6, nudge: nudge, level: 1), closeTo(0.3, 1e-9));
      // Outside in the dark: still less red than full, by the same amount.
      expect(nightVisionStrength(auto: true, autoRed: 1, nudge: nudge, level: 1), closeTo(0.7, 1e-9));
      // Back indoors with the lights on: true colours, never "negative red".
      expect(nightVisionStrength(auto: true, autoRed: 0, nudge: nudge, level: 1), 0);
    });

    test('someone who wants red even in a lit room can have it', () {
      final nudge = nudgeFor(target: 0.4, autoRed: 0);
      expect(nightVisionStrength(auto: true, autoRed: 0, nudge: nudge, level: 0), closeTo(0.4, 1e-9));
      expect(nightVisionStrength(auto: true, autoRed: 1, nudge: nudge, level: 0), 1);
    });

    test('Auto off is a fixed level whatever the light', () {
      for (final light in [0.0, 0.6, 1.0]) {
        expect(nightVisionStrength(auto: false, autoRed: light, nudge: 0.5, level: 0.45), 0.45);
      }
    });

    test('always between true colours and full red', () {
      expect(nightVisionStrength(auto: true, autoRed: 1, nudge: 1, level: 0), 1);
      expect(nightVisionStrength(auto: true, autoRed: 0, nudge: -1, level: 0), 0);
      expect(nightVisionStrength(auto: false, autoRed: 0, nudge: 0, level: 3), 1);
      expect(nudgeFor(target: 5, autoRed: 0), 1);
      expect(nudgeFor(target: -2, autoRed: 1), -1);
    });
  });
}
