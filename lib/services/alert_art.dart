/// Paints the "where to look" picture that rides on a pass alert: the
/// horizon facing the pass, compass words, and the path with an arrow and
/// the time it appears. Android shows it as the expanded big picture; iOS as
/// the notification's attachment (long-press or pull down).
///
/// Only `dart:ui` (no widgets), so it also runs in the background refresh
/// isolate. Every failure returns null and the alert goes out as plain text.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../domain/models/sky_event.dart';
import '../domain/scheduling/alert_planner.dart';
import '../domain/sky/alert_chart.dart';
import '../domain/sky/direction.dart';
import '../ui/kit/firefly_mark.dart';

abstract final class AlertArt {
  /// Event kinds that cross the sky and get a picture.
  static const types = {SkyEventType.iss, SkyEventType.tiangong, SkyEventType.starlinkTrain};

  static const width = 1024, height = 512; // 2:1, what Android's big picture wants

  static bool wants(PlannedAlert a) => a.kind == AlertKind.headsUp && types.contains(a.event.type);

  /// Writes the picture for [a] and returns its path, or null (not a pass,
  /// or anything at all went wrong).
  static Future<String?> fileFor(PlannedAlert a) async {
    if (!wants(a)) return null;
    try {
      final bytes = await png(a.event, startLabel: _hm(a.event.start)).timeout(const Duration(seconds: 3));
      if (bytes == null) return null;
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/alert_art');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // iOS moves an attachment into its own store when the alert is added,
      // so each scheduling writes a fresh file.
      final f = File('${dir.path}/${a.notificationId}.png');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  static String _hm(DateTime utc) {
    final l = utc.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  /// The PNG for [e]. [startLabel] is the time it appears ("9:05 PM").
  static Future<List<int>?> png(SkyEvent e, {required String startLabel, bool titled = true}) async {
    final recorder = ui.PictureRecorder();
    paint(ui.Canvas(recorder), e, startLabel: startLabel, titled: titled);
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  static const _night = ui.Color(0xFF0B1328);
  static const _black = ui.Color(0xFF04060B);
  static const _white = ui.Color(0xFFF4F6FA);
  static const _grey = ui.Color(0xFFA0A8B8);

  static ui.Color _tint(SkyEventType t) => t == SkyEventType.starlinkTrain ? const ui.Color(0xFFA78BFA) : const ui.Color(0xFF5AA2FF);

  /// [titled] adds "Face …", the LookUp mark and the compass words (the
  /// alert); the home-screen widget sets its own words over the picture, so
  /// it leaves them off.
  static void paint(ui.Canvas canvas, SkyEvent e, {required String startLabel, bool titled = true}) {
    const w = 1024.0, h = 512.0;
    final tint = _tint(e.type);
    final chart = AlertChart.forPass(
      riseAz: e.riseAzimuthDeg,
      peakAz: e.peakAzimuthDeg,
      setAz: e.setAzimuthDeg,
      peakEl: e.peakElevationDeg,
    );
    const horizon = h * 0.78, skyTop = h * 0.16, left = 40.0, right = w - 40;
    ui.Offset at((double, double) p) => ui.Offset(left + (right - left) * p.$1, horizon - (horizon - skyTop) * p.$2);

    // Sky.
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..shader = ui.Gradient.linear(
          const ui.Offset(0, 0),
          const ui.Offset(0, horizon),
          [_black, _night, const ui.Color(0xFF1A2C50)],
          [0, 0.6, 1],
        ),
    );
    final rnd = math.Random(e.id.hashCode);
    for (var i = 0; i < 90; i++) {
      final p = ui.Offset(rnd.nextDouble() * w, rnd.nextDouble() * horizon * 0.95);
      canvas.drawCircle(p, 0.6 + rnd.nextDouble() * 1.6, ui.Paint()..color = _white.withValues(alpha: 0.15 + rnd.nextDouble() * 0.5));
    }

    // The path: faint full route, then the bright part with direction arrows.
    final pts = [for (final p in chart.path) at(p)];
    final route = ui.Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      route.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      route,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = tint.withValues(alpha: 0.18)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );
    canvas.drawPath(
      route,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = ui.StrokeCap.round
        ..shader = ui.Gradient.linear(pts.first, pts.last, [tint.withValues(alpha: 0.95), tint.withValues(alpha: 0.35)]),
    );
    for (final f in const [0.3, 0.7]) {
      final i = (f * (pts.length - 1)).round();
      _arrow(canvas, pts[i], pts[math.min(i + 2, pts.length - 1)], tint);
    }
    // Its best moment: a soft glow.
    final peak = at(chart.peak);
    canvas.drawCircle(
      peak,
      26,
      ui.Paint()..shader = ui.Gradient.radial(peak, 26, [tint.withValues(alpha: 0.5), tint.withValues(alpha: 0)]),
    );
    // Where it appears: the firefly, the app's "it'll be here" mark, its
    // sparks curling in from above on the side away from the labels.
    final rise = pts.first;
    final fromRight = rise.dx > w * 0.6; // labels go left of it then
    paintSparkTrail(canvas, fireflyCurl(rise, rise + ui.Offset(fromRight ? 70 : -70, -95), curl: fromRight ? -0.3 : 0.3), scale: 1.5);
    paintFirefly(canvas, rise, blink: 0.8, scale: 1.5);

    // Ground and compass words.
    final ground = ui.Path()
      ..moveTo(0, horizon + 4)
      ..quadraticBezierTo(w * 0.3, horizon - 8, w * 0.55, horizon + 2)
      ..quadraticBezierTo(w * 0.8, horizon + 10, w, horizon - 2)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      ground,
      ui.Paint()..shader = ui.Gradient.linear(const ui.Offset(0, horizon), const ui.Offset(0, h), [const ui.Color(0xFF0C1324), _black]),
    );
    if (titled) {
      for (final (word, x) in chart.compass) {
        _text(
          canvas,
          word,
          ui.Offset(left + (right - left) * x, horizon + 22),
          size: 24,
          color: _grey,
          weight: ui.FontWeight.w700,
          centre: true,
        );
      }
    }

    // Labels: when and where it appears, and which way to face.
    final riseLeft = rise.dx > w * 0.6;
    _text(
      canvas,
      startLabel,
      rise + ui.Offset(riseLeft ? -18 : 18, -46),
      size: 26,
      color: _white,
      weight: ui.FontWeight.w700,
      alignRight: riseLeft,
    );
    _text(canvas, 'appears here', rise + ui.Offset(riseLeft ? -18 : 18, -16), size: 20, color: _grey, alignRight: riseLeft);
    if (!titled) return;
    _text(canvas, 'Face ${compassWord(e.riseAzimuthDeg)}', const ui.Offset(40, 30), size: 34, color: _white, weight: ui.FontWeight.w700);
    _text(canvas, 'LookUp', const ui.Offset(w - 40, 34), size: 22, color: _grey, weight: ui.FontWeight.w700, alignRight: true);
  }

  static void _arrow(ui.Canvas canvas, ui.Offset from, ui.Offset to, ui.Color color) {
    final d = to - from;
    if (d.distance < 1) return;
    final u = d / d.distance;
    final n = ui.Offset(-u.dy, u.dx);
    final tip = from + u * 14;
    final path = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((from - u * 8 + n * 11).dx, (from - u * 8 + n * 11).dy)
      ..lineTo((from - u * 8 - n * 11).dx, (from - u * 8 - n * 11).dy)
      ..close();
    canvas.drawPath(path, ui.Paint()..color = color);
  }

  static void _text(
    ui.Canvas canvas,
    String s,
    ui.Offset at, {
    required double size,
    required ui.Color color,
    ui.FontWeight weight = ui.FontWeight.w500,
    bool centre = false,
    bool alignRight = false,
  }) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Inter', fontSize: size, fontWeight: weight))
      ..pushStyle(ui.TextStyle(color: color))
      ..addText(s);
    final p = b.build()..layout(const ui.ParagraphConstraints(width: 600));
    final tw = p.maxIntrinsicWidth;
    final dx = centre
        ? at.dx - tw / 2
        : alignRight
        ? at.dx - tw
        : at.dx;
    canvas.drawParagraph(p, ui.Offset(dx, at.dy));
  }
}
