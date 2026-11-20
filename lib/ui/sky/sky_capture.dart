/// The picture a catch makes: what the camera saw, the sky labels LookUp
/// drew over it, and a caption along the foot (what, when, where, "LookUp").
/// Photos can't be tagged by other apps, so the picture carries its own
/// words wherever it ends up.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Lays [photo] out as the camera preview did on a [screen]-sized view
/// (filling it, cropped at the edges), paints [overlay] over it at screen
/// scale, and adds the caption. PNG bytes, or null if the photo won't decode.
Future<Uint8List?> composeSkyPicture({
  required Uint8List photo,
  required Size screen,
  required CustomPainter overlay,
  required String title,
  required String line,
}) async {
  final ui.Image img;
  try {
    img = (await (await ui.instantiateImageCodec(photo)).getNextFrame()).image;
  } catch (_) {
    return null;
  }
  // A sideways frame (some cameras): turn it to match the screen.
  final turn = (img.width > img.height) != (screen.width > screen.height);
  final pw = (turn ? img.height : img.width).toDouble(), ph = (turn ? img.width : img.height).toDouble();
  // Screen pixels per photo pixel, filling the screen as the preview does.
  final s = math.max(screen.width / pw, screen.height / ph);
  final out = Size(screen.width / s, screen.height / s);

  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.save();
  c.translate(out.width / 2, out.height / 2);
  if (turn) c.rotate(math.pi / 2);
  c.drawImage(img, Offset(-img.width / 2, -img.height / 2), Paint()..filterQuality = FilterQuality.high);
  c.restore();

  c.save();
  c.scale(1 / s);
  overlay.paint(c, screen);
  c.restore();

  paintCaption(c, out, title, line);
  final picture = await rec.endRecording().toImage(out.width.round(), out.height.round());
  final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
  return bytes?.buffer.asUint8List();
}

/// The caption along a picture's foot: what, then when and where, and
/// "LookUp" on the right, over a soft dark fade.
void paintCaption(Canvas c, Size size, String title, String line) {
  final w = size.width, h = size.height;
  final unit = math.min(w, h) / 30;
  c.drawRect(
      Rect.fromLTWH(0, h - unit * 5, w, unit * 5),
      Paint()
        ..shader = ui.Gradient.linear(
            Offset(0, h - unit * 5), Offset(0, h), [const Color(0x00000000), const Color(0xB3000000)]));
  void text(String s, Offset at, double size, FontWeight weight, Color color, {bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: display(size, weight: weight, color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: w * 0.7);
    tp.paint(c, right ? at - Offset(tp.width, 0) : at);
  }

  text(title, Offset(unit, h - unit * 3.4), unit * 1.15, FontWeight.w700, Colors.white);
  text(line, Offset(unit, h - unit * 1.9), unit * 0.8, FontWeight.w500, const Color(0xCCFFFFFF));
  text('LookUp', Offset(w - unit, h - unit * 1.9), unit * 0.8, FontWeight.w700, const Color(0xCCFFFFFF), right: true);
}

/// [rgba] ([width]×[height]) with the caption along its foot, as PNG.
Future<Uint8List?> captionedPng(Uint8List rgba, int width, int height, {required String title, required String line}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
  final desc = ui.ImageDescriptor.raw(buffer, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
  final img = (await (await desc.instantiateCodec()).getNextFrame()).image;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawImage(img, Offset.zero, Paint());
  paintCaption(c, Size(width.toDouble(), height.toDouble()), title, line);
  final out = await rec.endRecording().toImage(width, height);
  final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
  return bytes?.buffer.asUint8List();
}
