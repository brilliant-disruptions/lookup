import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/kit/kit.dart';

/// Paints [mark] at the centre of a 64×64 transparent canvas and returns
/// its RGBA bytes.
Future<List<int>> render(void Function(ui.Canvas, ui.Offset) mark) async {
  final rec = ui.PictureRecorder();
  mark(ui.Canvas(rec), const ui.Offset(32, 32));
  final image = await rec.endRecording().toImage(64, 64);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  return bytes!.buffer.asUint8List();
}

/// Pixels a viewer could take for something in the sky: warm (planets are
/// gold, the Sun yellow) or a lit dot right where the phone points.
bool warm(List<int> px, int i) => px[i + 3] > 40 && px[i] > px[i + 2] + 40;

void main() {
  testWidgets('the pointing mark can\'t be read as the Sun or a planet', (t) async {
    await t.runAsync(() async {
      final mark = await render(paintPointingMark);
      final warmPixels = [for (var i = 0; i < mark.length; i += 4) if (warm(mark, i)) i];
      expect(warmPixels, isEmpty, reason: 'warm colours belong to the sky, not to "your phone"');
      final centre = (32 * 64 + 32) * 4;
      expect(mark[centre + 3], 0, reason: 'an open middle, so the star you aim at shows through');
      expect(mark.where((b) => b > 0), isNotEmpty, reason: 'it still draws something');

      // The firefly it replaced fails the same check: that's why it went.
      final firefly = await render((c, at) => paintFirefly(c, at));
      expect([for (var i = 0; i < firefly.length; i += 4) if (warm(firefly, i)) i], isNotEmpty);
      expect(firefly[centre + 3], greaterThan(0));
    });
  });
}
