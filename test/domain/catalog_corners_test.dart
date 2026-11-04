import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/catalog.dart';

void main() {
  // A lit constellation draws each corner as the star it really is: bright
  // stars bigger, and in their own colour. That only works if every corner
  // finds its star.
  test('constellation corners find the stars they sit on', () {
    Map<String, Object?> read(String f) => jsonDecode(File('assets/sky/$f').readAsStringSync()) as Map<String, Object?>;
    final cat = SkyCatalog.fromJson(read('stars.json'), read('constellations.json'), read('proper_motion.json'));
    final ori = cat.constellations.firstWhere((c) => c.id == 'Ori');
    final stars = {for (final seg in ori.lines) for (final (ra, dec) in seg) cat.starAt(ra, dec)};
    expect(stars, isNot(contains(null)));
    final betelgeuse = stars.firstWhere((s) => s!.name == 'Betelgeuse')!;
    final rigel = stars.firstWhere((s) => s!.name == 'Rigel')!;
    expect(betelgeuse.bv, greaterThan(1.3)); // amber
    expect(rigel.bv, lessThan(0)); // blue-white
    expect(cat.starAt(0, -89.9), isNull);
  });
}
