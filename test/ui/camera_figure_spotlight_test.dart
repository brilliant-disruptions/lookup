import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/figures.dart';
import 'package:lookup/ui/finder_camera.dart';
import 'package:lookup/ui/sky/constellation_glow.dart';

// In the camera view only the constellation in the middle shows its picture
// properly; the rest are faint. Pictures overlap (Pegasus and Andromeda share
// a star), so picking the wrong one, or two, muddles exactly where it matters.
void main() {
  const size = Size(400, 800);
  ConstellationFigure fig(String id) => ConstellationFigure(id: id, file: '$id.png', width: 10, height: 10, anchors: const []);
  final peg = fig('Peg'), and = fig('And'), ori = fig('Ori');

  test('the picture whose stars surround the middle is spotlit', () {
    final lit = SkyOverlayPainter.spotlitFigure(size, [
      (ori, const [Offset(10, 10), Offset(90, 10), Offset(50, 90)]),
      (peg, const [Offset(150, 350), Offset(260, 360), Offset(200, 470)]),
    ]);
    expect(lit, peg);
  });

  test('where triangles overlap, the one centred nearer the middle wins', () {
    final lit = SkyOverlayPainter.spotlitFigure(size, [
      (and, const [Offset(150, 420), Offset(390, 300), Offset(390, 500)]), // middle inside, near its tip
      (peg, const [Offset(120, 330), Offset(280, 330), Offset(200, 480)]), // middle near its centre
    ]);
    expect(lit, peg);
  });

  test('nothing is spotlit between constellations, so all stay faint', () {
    final lit = SkyOverlayPainter.spotlitFigure(size, [
      (ori, const [Offset(10, 10), Offset(90, 10), Offset(50, 90)]),
    ]);
    expect(lit, isNull);
  });

  // Tasteful means gentle and unsynchronised: a lit constellation's stars
  // shouldn't throb together like a sign.
  test('twinkle stays gentle and each star keeps its own beat', () {
    final rigel = [for (var i = 0; i < 200; i++) twinkleAt(78.63, -8.20, i * 0.05)];
    final betelgeuse = [for (var i = 0; i < 200; i++) twinkleAt(88.79, 7.41, i * 0.05)];
    expect(rigel.every((v) => v >= -1 && v <= 1), isTrue);
    var apart = 0;
    for (var i = 0; i < 200; i++) {
      if ((rigel[i] - betelgeuse[i]).abs() > 0.3) apart++;
    }
    expect(apart, greaterThan(50));
  });

  // A lit picture gathers round its stars instead of ending in a hard box;
  // the faint ones are left exactly as drawn.
  testWidgets('a lit picture softens at its edges, a faint one does not', (tester) async {
    await tester.runAsync(() async {
      Future<ui.Image> solid() {
        final r = ui.PictureRecorder();
        Canvas(r).drawRect(const Rect.fromLTWH(0, 0, 40, 40), Paint()..color = Colors.white);
        return r.endRecording().toImage(40, 40);
      }

      Future<(int, int)> centreAndCorner(double t) async {
        final img = await solid();
        final r = ui.PictureRecorder();
        final c = Canvas(r)..drawRect(const Rect.fromLTWH(0, 0, 40, 40), Paint()..color = Colors.black);
        paintFigure(c, img, Colors.white, t);
        final out = await r.endRecording().toImage(40, 40);
        final px = (await out.toByteData())!;
        int red(int x, int y) => px.getUint8((y * 40 + x) * 4);
        return (red(20, 20), red(1, 1));
      }

      final faint = await centreAndCorner(0);
      expect(faint.$2, faint.$1);
      final lit = await centreAndCorner(1);
      expect(lit.$1, greaterThan(240));
      expect(lit.$2, lessThan(lit.$1 * 0.4));
    });
  });
}
