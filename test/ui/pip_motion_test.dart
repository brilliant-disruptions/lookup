import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/kit/pip_motion.dart';

void main() {
  List<PipPose> over(PipState s, double from, double to, {bool dim = false, double step = 1 / 60}) => [
        for (var t = from; t < to; t += step) pipPose(s, 10 + t, since: t, dim: dim),
      ];

  group('hello', () {
    test('drops in from above, faded and stretched by the fall', () {
      final first = pipPose(PipState.hello, 0, since: 0);
      expect(first.offset.dy, lessThan(-60), reason: 'starts well above its spot');
      expect(first.opacity, lessThan(0.2));
      expect(first.stretch, greaterThan(first.squash), reason: 'long in the direction it falls');
    });

    test('lands squashed, bounces once, and ends round on its spot', () {
      final land = pipPose(PipState.hello, 0, since: 0.56);
      expect(land.stretch, lessThan(1), reason: 'short along the fall');
      expect(land.squash, greaterThan(1), reason: 'wide across it');
      final bounce = over(PipState.hello, 0.55, 1.0).map((p) => p.offset.dy).reduce(math.min);
      expect(bounce, lessThan(-15));
      final settled = pipPose(PipState.hello, 0, since: 1.2);
      expect(settled.offset.distance, lessThan(4));
    });

    test('blinks twice to say hi, and only twice', () {
      final b = over(PipState.hello, 1.1, pipHelloLength).map((p) => p.blink).toList();
      var dips = 0;
      for (var i = 1; i < b.length; i++) {
        if (b[i] < 0.3 && b[i - 1] >= 0.3) dips++;
      }
      expect(dips, 2);
    });

    test('then rests, as Pip always does when it has arrived', () {
      final after = pipPose(PipState.hello, 7, since: pipHelloLength + 3);
      expect(after.offset, pipPose(PipState.resting, 7).offset);
      expect(after.blink, pipPose(PipState.resting, 7).blink);
    });
  });

  group('found', () {
    test('flares brighter and bigger first, then hops', () {
      final flare = pipPose(PipState.found, 0, since: 0.08);
      expect(flare.size, greaterThan(1.2));
      expect(flare.blink, 1);
      final top = over(PipState.found, 0.3, 0.62).map((p) => p.offset.dy).reduce(math.min);
      expect(top, lessThan(-10));
    });

    test('settles into a rest', () {
      expect(pipPose(PipState.found, 3, since: pipFoundLength + 1).stretch, pipPose(PipState.resting, 3).stretch);
    });
  });

  test('searching circles, stretched along the way it is going', () {
    for (var t = 0.0; t < 3; t += 0.37) {
      final p = pipPose(PipState.searching, t);
      expect(p.offset.distance, closeTo(pipSearchRadius, 1e-6));
      // The stretch points along the tangent: square to the line from the centre.
      final along = Offset(math.cos(p.angle), math.sin(p.angle));
      expect((along.dx * p.offset.dx + along.dy * p.offset.dy).abs(), lessThan(1e-6));
      expect(p.stretch, greaterThan(p.squash));
    }
  });

  test('resting sits a little flattened, dimmer than its glow, and glows now and then', () {
    final r = over(PipState.resting, 0, 10, step: 0.05);
    expect(r.every((p) => p.squash < 1 && p.angle == 0), isTrue, reason: 'flatter top to bottom');
    final b = r.map((p) => p.blink);
    expect(b.reduce(math.min), lessThan(0.75));
    expect(b.reduce(math.max), greaterThan(0.95));
  });

  test('can\'t see: smaller, dimmer, and looks one way then the other', () {
    final d = over(PipState.idle, 0, 4.4, dim: true, step: 0.05);
    final plain = over(PipState.idle, 0, 4.4, step: 0.05);
    expect(d.every((p) => p.size < 1), isTrue);
    for (var i = 0; i < d.length; i++) {
      expect(d[i].blink, lessThan(plain[i].blink + 1e-9));
    }
    final xs = [for (var i = 0; i < d.length; i++) d[i].offset.dx - plain[i].offset.dx];
    expect(xs.reduce(math.min), lessThan(-8));
    expect(xs.reduce(math.max), greaterThan(8));
  });

  test('blinking flashes quickly, before a tap', () {
    var peaks = 0;
    final quick = [for (var t = 0.0; t < 1; t += 0.02) pipPose(PipState.idle, t, blinking: true).blink];
    for (var i = 1; i + 1 < quick.length; i++) {
      if (quick[i] > quick[i - 1] && quick[i] >= quick[i + 1]) peaks++;
    }
    expect(peaks, greaterThanOrEqualTo(2), reason: 'about 2.5 a second');
  });

  test('Reduce Motion holds every mood still and round', () {
    for (final s in PipState.values) {
      for (final t in [0.0, 0.3, 1.5, 9.0]) {
        final p = pipPose(s, t, since: t, still: true);
        expect(p.offset, Offset.zero, reason: '$s at $t');
        expect(p.round, isTrue, reason: '$s at $t');
        expect(p.opacity, 1);
      }
    }
  });

  test('a flight in is stretched along the way, then lands with a squash', () {
    const from = Offset(-140, -120);
    final rest = pipPose(PipState.resting, 2);
    final mid = pipFlightPose(rest, from, 0.4, 0.9);
    expect(mid.stretch, greaterThan(mid.squash));
    // Pointing from where it set off towards home.
    expect(mid.angle, closeTo(math.atan2(120, 140), 1e-9));
    final land = pipFlightPose(rest, from, 0.91, 0.9);
    expect(land.stretch, lessThan(1));
    expect(pipFlightPose(rest, from, 2, 0.9).stretch, rest.stretch, reason: 'then it rests');
  });
}
