import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/sky/constellation_glow.dart';

void main() {
  const sky = Rect.fromLTRB(0, 0, 400, 500); // the horizon is at 500
  const name = Size(80, 16);

  test('beneath the constellation when there\'s room', () {
    final r = litNameRect(const [Offset(200, 100), Offset(220, 200)], name, sky);
    expect(r.top, 218);
    expect(r.center.dx, closeTo(210, 0.01));
  });

  test('above it when beneath would fall behind the ground', () {
    final r = litNameRect(const [Offset(200, 380), Offset(220, 490)], name, sky);
    expect(r.bottom, lessThanOrEqualTo(sky.bottom));
    expect(r.bottom, 380 - 18);
  });

  test('never cut off at the sides or the top', () {
    final left = litNameRect(const [Offset(5, 100)], name, sky);
    expect(left.left, greaterThanOrEqualTo(4));
    final right = litNameRect(const [Offset(398, 100)], name, sky);
    expect(right.right, lessThanOrEqualTo(396));
    // A constellation spanning the whole sky: it still lands inside.
    final tall = litNameRect(const [Offset(200, 2), Offset(200, 498)], name, sky);
    expect(sky.contains(tall.topLeft) && sky.contains(tall.bottomRight - const Offset(1, 1)), isTrue);
  });

  test('a plain name that would run into the lit one steps aside', () {
    const lit = Rect.fromLTWH(160, 380, 90, 16); // "Cepheus"
    expect(labelClashes(const Offset(200, 392), const Size(60, 14), [lit]), isTrue); // "Cygnus" on top of it
    expect(labelClashes(const Offset(200, 300), const Size(60, 14), [lit]), isFalse);
    expect(labelClashes(const Offset(200, 392), const Size(60, 14), const []), isFalse);
  });
}
