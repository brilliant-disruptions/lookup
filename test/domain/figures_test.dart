import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/figures.dart';

void main() {
  group('affineFrom3', () {
    // The whole picture hangs off this: if the anchors don't land exactly on
    // their stars, the art drifts away from the lines it's meant to explain.
    test('puts each anchor exactly on its star, sheared and rotated', () {
      const from = [(10.0, 20.0), (300.0, 40.0), (150.0, 400.0)];
      const to = [(-5.0, 7.0), (80.0, -60.0), (120.0, 90.0)];
      final (a, b, c, d, e, f) = affineFrom3(from, to)!;
      for (var i = 0; i < 3; i++) {
        final (x, y) = from[i];
        expect(a * x + c * y + e, closeTo(to[i].$1, 1e-9));
        expect(b * x + d * y + f, closeTo(to[i].$2, 1e-9));
      }
    });

    // Three anchors in a line fix nothing across them; the figure must be
    // skipped rather than smeared to infinity.
    test('gives up when the anchors are in a line', () {
      expect(affineFrom3(const [(0, 0), (1, 1), (2, 2)], const [(0, 0), (5, 0), (0, 5)]), isNull);
    });
  });

  group('distanceToTriangle', () {
    const tri = [(0.0, 0.0), (100.0, 0.0), (0.0, 100.0)];

    test('is zero inside, whichever way round the corners go', () {
      expect(distanceToTriangle((20, 20), tri), 0);
      expect(distanceToTriangle((20, 20), tri.reversed.toList()), 0);
    });

    test('measures to the nearest edge or corner outside', () {
      expect(distanceToTriangle((50, -30), tri), closeTo(30, 1e-9));
      expect(distanceToTriangle((-3, -4), tri), closeTo(5, 1e-9));
    });

    // The bug this replaced: the panorama brightened whichever picture's
    // image centre was nearest the middle, so with a tall rising Leo
    // centred on screen, little Leo Minor lit up instead. A point sitting on
    // a constellation's stars must beat one merely near a small image.
    test('a point on a big figure beats a small figure centred nearer', () {
      const mid = (304.0, 468.0);
      const leo = [(290.0, 380.0), (306.0, 507.0), (233.0, 810.0)]; // ε Leo, Regulus, Denebola
      const leoMinor = [(150.0, 300.0), (260.0, 330.0), (190.0, 400.0)];
      // Image centres as placed on screen (Leo's sits down by the Moon).
      double dist((double, double) c) => sqrt(pow(c.$1 - mid.$1, 2) + pow(c.$2 - mid.$2, 2));
      expect(dist((200, 330)), lessThan(dist((270, 660))), reason: 'the old rule picked Leo Minor');
      expect(distanceToTriangle(mid, leo), lessThan(distanceToTriangle(mid, leoMinor)));
    });
  });

  group('figures.json', () {
    late List<ConstellationFigure> figures;
    late SkyCatalog catalog;
    setUpAll(() {
      Map<String, Object?> read(String f) => jsonDecode(File('assets/sky/$f').readAsStringSync()) as Map<String, Object?>;
      figures = ConstellationFigure.listFromJson(read('figures.json'));
      catalog = SkyCatalog.fromJson(read('stars.json'), read('constellations.json'), read('proper_motion.json'));
    });

    // All 88, less Serpens (no art) and Puppis/Vela (drawn inside Carina's
    // Argo Navis), so a constellation going missing in a rebuild shows here.
    test('pictures every constellation that Stellarium draws', () {
      final ids = {for (final f in figures) f.id};
      expect(figures, hasLength(85));
      expect(ids, hasLength(85));
      final missing = {for (final c in catalog.constellations) c.id}.difference(ids);
      expect(missing, {'Ser', 'Pup', 'Vel'});
    });

    // The panorama names the picture it's showing ("Pictured: …") from the
    // catalog, and loads the file lazily: either missing would fail silently.
    test('every figure names a real constellation and ships its image', () {
      for (final f in figures) {
        expect(catalog.constellation(f.id), isNotNull, reason: f.id);
        expect(File('assets/sky/figures/${f.file}').existsSync(), isTrue, reason: f.file);
        expect(f.anchors, hasLength(3), reason: f.id);
        expect(affineFrom3([for (final a in f.anchors) (a.x, a.y)], const [(0, 0), (1, 0), (0, 1)]), isNotNull, reason: f.id);
      }
    });

    // Anchors resolved from Hipparcos numbers at build time; a mixed-up
    // catalogue would pin Orion's art to the wrong part of the sky.
    test('Orion is pinned to stars in Orion', () {
      final orion = figures.firstWhere((f) => f.id == 'Ori');
      for (final a in orion.anchors) {
        expect(a.raDeg, inInclusiveRange(70, 95));
        expect(a.decDeg, inInclusiveRange(-12, 23));
      }
    });
  });

  group('constellation pictures setting', () {
    // People who saved settings before the switch existed should still see
    // the pictures, and someone who turned them off must not get them back
    // after a restart.
    test('is on for settings saved before it existed', () {
      final old = const LookUpSettings().toJson()..remove('skyFigures');
      expect(LookUpSettings.fromJson(old).skyFigures, isTrue);
    });

    test('stays off once turned off', () {
      final off = const LookUpSettings().copyWith(skyFigures: false);
      final back = LookUpSettings.fromJson(jsonDecode(jsonEncode(off.toJson())) as Map<String, Object?>);
      expect(back.skyFigures, isFalse);
    });
  });
}
