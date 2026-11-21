import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/photo/frame_stack.dart';
import 'package:lookup/domain/photo/shot_plan.dart';

void main() {
  const w = 64, h = 48;
  final rnd = math.Random(3);

  // A dark sky with a few stars, plus noise; [blur] smears it (a shaky frame).
  Uint8List frame({double noise = 8, bool blur = false, int? star}) {
    final y = Uint8List(w * h);
    for (var i = 0; i < y.length; i++) {
      y[i] = (20 + rnd.nextDouble() * noise).round();
    }
    for (final (sx, sy) in [(10, 10), (40, 20), (25, 35)]) {
      y[sy * w + sx] = 230;
    }
    if (star != null) y[5 * w + star] = 250;
    if (!blur) return y;
    final out = Uint8List(y.length);
    for (var yy = 1; yy < h - 1; yy++) {
      for (var xx = 1; xx < w - 1; xx++) {
        var s = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            s += y[(yy + dy) * w + xx + dx];
          }
        }
        out[yy * w + xx] = s ~/ 9;
      }
    }
    return out;
  }

  double noiseOf(Uint8List y) {
    final m = y.fold<int>(0, (a, b) => a + b) / y.length;
    return math.sqrt(y.fold<double>(0, (a, b) => a + (b - m) * (b - m)) / y.length);
  }

  test('a sharp frame scores higher than a shaky one', () {
    expect(sharpness(frame(), w), greaterThan(sharpness(frame(blur: true), w) * 2));
  });

  test('average: the noise falls, the stars stay', () {
    final s = FrameStack(StackKind.average, w, h);
    for (var i = 0; i < 16; i++) {
      s.add(frame(noise: 40));
    }
    final y = s.planes().y;
    expect(y[10 * w + 10], greaterThan(200), reason: 'the star is still there');
    final sky = Uint8List.fromList([for (var i = 0; i < w * 4; i++) y[30 * w + i % w]]);
    expect(noiseOf(sky), lessThan(noiseOf(frame(noise: 40)) / 2));
  });

  test('lighten: each pixel its brightest, so a moving star leaves a trail', () {
    final s = FrameStack(StackKind.lighten, w, h);
    for (var x = 5; x < 45; x++) {
      s.add(frame(star: x));
    }
    final y = s.planes().y;
    for (var x = 5; x < 45; x++) {
      expect(y[5 * w + x], greaterThanOrEqualTo(250), reason: 'trail at $x');
    }
  });

  test('sharpest: only the steadiest frames go in', () {
    final s = FrameStack(StackKind.sharpest, w, h, keep: 3);
    for (var i = 0; i < 12; i++) {
      s.add(frame(blur: i % 4 != 0));
    }
    expect(s.frames, 12);
    final y = s.planes().y;
    expect(y[10 * w + 10], greaterThan(200), reason: 'a blurred star would be about a ninth as bright');
  });

  test('to RGBA: grey stays grey, and it turns with the phone', () {
    final s = FrameStack(StackKind.average, w, h)..add(Uint8List(w * h)..fillRange(0, w * h, 100));
    final r = s.rgba(quarterTurns: 1);
    expect(r.width, h);
    expect(r.height, w);
    expect(r.rgba.sublist(0, 4), [100, 100, 100, 255]);
  });
}
