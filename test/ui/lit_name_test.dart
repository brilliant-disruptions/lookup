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

  test('plain names step aside for each other: below, then above, else wait', () {
    final taken = <Rect>[];
    final first = placeLabel(const Offset(200, 100), name, taken)!;
    expect(first, const Offset(200, 100));
    // A neighbour aimed at almost the same spot goes just below.
    final second = placeLabel(const Offset(210, 104), name, taken)!;
    expect(second.dy, greaterThan(104));
    // A third tries below (taken), then above.
    final third = placeLabel(const Offset(205, 96), name, taken)!;
    expect(third.dy, lessThan(96));
    // None of the three overlap.
    final rects = [for (final o in [first, second, third]) Rect.fromCenter(center: o, width: name.width, height: name.height)];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
    // A fourth has nowhere to go and waits.
    expect(placeLabel(const Offset(200, 101), name, taken), isNull);
    expect(taken, hasLength(3));
  });

  test('planet names come first and step down or up for each other; never dropped', () {
    final taken = <Rect>[];
    const jupiter = Offset(200, 300), mars = Offset(212, 304);
    final j = placeBodyLabel(jupiter, 16, name, taken);
    expect(j, const Offset(200, 316));
    final m = placeBodyLabel(mars, 16, name, taken);
    expect(Rect.fromCenter(center: j, width: name.width, height: name.height)
        .overlaps(Rect.fromCenter(center: m, width: name.width, height: name.height)), isFalse);
    // A constellation name aimed at Jupiter's label steps aside, or waits.
    final leo = placeLabel(const Offset(205, 318), name, taken);
    if (leo != null) {
      for (final r in taken.take(2)) {
        expect(r.overlaps(Rect.fromCenter(center: leo, width: name.width, height: name.height)), isFalse);
      }
    }
    // Crowded out entirely, a planet is still named, beneath it.
    final crowded = [const Rect.fromLTRB(0, 0, 400, 500)];
    expect(placeBodyLabel(jupiter, 16, name, crowded), const Offset(200, 316));
  });

  test('the spotlight name goes above rather than sit on a planet', () {
    const stars = [Offset(200, 100), Offset(220, 200)];
    final jupiter = Rect.fromCircle(center: const Offset(210, 226), radius: 9);
    final r = litNameRect(stars, name, sky, avoid: [jupiter]);
    expect(r.overlaps(jupiter), isFalse);
    expect(r.bottom, lessThanOrEqualTo(100));
    // Nothing in the way: beneath, as before.
    expect(litNameRect(stars, name, sky).top, 218);
  });
}
