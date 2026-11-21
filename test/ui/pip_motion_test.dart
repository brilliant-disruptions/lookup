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

  group('greet, as the light in a sky picture: it opens its eyes, then is the dot again', () {
    List<PipGreeting> over(double from, double to) => [for (var t = from; t < to; t += 1 / 60) pipGreeting(t, fromDot: true)];

    test('starts and ends as the plain dot', () {
      expect(pipGreeting(-1, fromDot: true).dot, isTrue);
      expect(pipGreeting(pipGreetLength, fromDot: true).dot, isTrue);
      expect(pipGreeting(pipGreetLength + 5, fromDot: true).dot, isTrue);
      expect(pipGreeting(0.02, fromDot: true).grown, 0, reason: 'it ripples before it opens');
    });

    test('like water: it wobbles and rings spread out as it wakes', () {
      final early = over(0.05, 0.5);
      expect(early.map((g) => g.wobble.abs()).reduce(math.max), greaterThan(0.5));
      expect(early.any((g) => g.ripples.isNotEmpty), isTrue);
      for (final g in over(0, pipGreetLength)) {
        for (final (k, a) in g.ripples) {
          expect(k, inInclusiveRange(0, 1));
          expect(a, inInclusiveRange(0, 1));
        }
      }
    });

    test('the eyes open only once it is an orb, and close before it shrinks', () {
      for (final g in over(0, pipGreetLength)) {
        if (g.open > 0) expect(g.grown, greaterThan(0.7));
      }
      expect(pipGreeting(1.2, fromDot: true).open, 1);
      expect(pipGreeting(2.8, fromDot: true).open, 0);
    });

    test('no mouth, no hands: just eyes, which glance aside and then follow the droplet up', () {
      expect(over(0.9, 1.4).map((g) => g.lookX).reduce(math.max), greaterThan(0.9));
      final withDrop = over(1.45, 2.15).where((g) => g.drop != null).toList();
      expect(withDrop, isNotEmpty);
      final top = withDrop.reduce((a, b) => a.drop!.height > b.drop!.height ? a : b);
      expect(top.drop!.height, greaterThan(18));
      expect(top.lookY, lessThan(-0.8), reason: 'looking up at it');
    });

    test('the droplet lands back with a splash: a second wobble and a ring', () {
      final after = over(2.16, 2.5);
      expect(after.map((g) => g.wobble.abs()).reduce(math.max), greaterThan(0.3));
      expect(after.any((g) => g.ripples.isNotEmpty), isTrue);
    });

    test('blinks once', () {
      final e = over(0.9, 2.4).map((g) => g.open).toList();
      var dips = 0;
      for (var i = 1; i < e.length; i++) {
        if (e[i] < 0.3 && e[i - 1] >= 0.3) dips++;
      }
      expect(dips, 1);
    });

    test('Reduce Motion: the orb and open eyes, without ripples or a droplet', () {
      for (final t in [0.0, 0.4, 1.7, 3.0]) {
        final g = pipGreeting(t, still: true, fromDot: true);
        expect(g.grown, 1, reason: '$t');
        expect(g.open, 1);
        expect(g.ripples, isEmpty);
        expect(g.drop, isNull);
        expect(g.wobble, 0);
      }
      expect(pipGreeting(pipGreetLength + 0.1, still: true, fromDot: true).dot, isTrue);
    });

    test('the light only hovers under it, and rests after', () {
      final p = pipPose(PipState.greet, 4, since: 1);
      expect(p.offset.distance, lessThan(4));
      expect(pipPose(PipState.greet, 7, since: pipGreetLength + 1).offset, pipPose(PipState.resting, 7).offset);
    });
  });

  group('greet, as the character: the same hello without ever being the dot', () {
    List<PipGreeting> over(double from, double to) => [for (var t = from; t < to; t += 1 / 60) pipGreeting(t)];

    test('eyes and body there from the first frame', () {
      for (final g in over(0, pipGreetLength)) {
        expect(g.grown, 1);
        expect(g.dot, isFalse);
      }
      expect(pipGreeting(0).open, greaterThan(0.9));
    });

    test('still ripples, still lifts the droplet', () {
      final all = over(0, pipGreetLength);
      expect(all.any((g) => g.ripples.isNotEmpty), isTrue);
      expect(all.any((g) => g.drop != null), isTrue);
    });
  });

  group('the character at rest', () {
    List<PipGreeting> over(double from, double to, {double poke = 1e9}) =>
        [for (var t = from; t < to; t += 1 / 60) pipCharacter(t, sincePoke: poke + (t - from))];

    test('always a character, never the dot, with no droplet or rings', () {
      for (final g in over(0, 30)) {
        expect(g.grown, 1);
        expect(g.dot, isFalse);
        expect(g.drop, isNull);
        expect(g.ripples, isEmpty);
      }
    });

    test('eyes open most of the time, with a blink every few seconds', () {
      final e = over(0, 30).map((g) => g.open).toList();
      final open = e.where((o) => o > 0.9).length / e.length;
      expect(open, greaterThan(0.85));
      var dips = 0;
      for (var i = 1; i < e.length; i++) {
        if (e[i] < 0.3 && e[i - 1] >= 0.3) dips++;
      }
      expect(dips, inInclusiveRange(6, 14), reason: 'about one every 3.7 s, sometimes a double');
    });

    test('glances around: the eyes go to several places, and stay in the eye', () {
      final looks = over(0, 30);
      final xs = looks.map((g) => g.lookX).toList();
      expect(xs.reduce(math.max), greaterThan(0.5));
      expect(xs.reduce(math.min), lessThan(-0.5));
      expect(looks.map((g) => g.lookY).reduce(math.min), lessThan(-0.3));
      for (final g in looks) {
        expect(g.lookX.abs(), lessThanOrEqualTo(1));
        expect(g.lookY.abs(), lessThanOrEqualTo(1));
      }
    });

    test('a little jiggle now and then, and breathes, but mostly sits calm', () {
      final all = over(0, 21);
      expect(all.map((g) => g.wobble.abs()).reduce(math.max), greaterThan(0.2));
      final calm = all.where((g) => g.wobble.abs() < 0.05).length / all.length;
      expect(calm, greaterThan(0.75));
      final sizes = all.map((g) => g.size);
      expect(sizes.reduce(math.max) - sizes.reduce(math.min), inInclusiveRange(0.02, 0.08));
    });

    test('a touch squishes it, wobbles it and makes it squint, then it settles', () {
      final touched = over(5, 5.8, poke: 0);
      expect(touched.map((g) => g.wobble.abs()).reduce(math.max), greaterThan(0.6));
      expect(touched.first.open, lessThan(0.6), reason: 'a happy squint');
      expect(touched.map((g) => (g.size - 1).abs()).reduce(math.max), greaterThan(0.05));
      final later = pipCharacter(5.9, sincePoke: 0.9);
      expect(later.size, closeTo(pipCharacter(5.9).size, 1e-9));
    });

    test('Reduce Motion: open eyes, looking ahead, still', () {
      for (final t in [0.0, 1.3, 7.2]) {
        final g = pipCharacter(t, still: true, sincePoke: 0.1);
        expect(g.open, 1);
        expect(g.wobble, 0);
        expect(g.lookX, 0);
        expect(g.size, 1);
      }
    });
  });
}
