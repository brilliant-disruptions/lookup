/// Pip grown out of the dot: a small drop of the same green light, lit from
/// inside and a little see-through, with two dark eyes, a small smile and
/// two soft hands. No outline, no fingers, no limbs to speak of: it stays a
/// light that has briefly taken a shape, so it reads as friendly without
/// becoming a cartoon. At [PipFigure.grown] 0 this is exactly the firefly.
///
/// Only `dart:ui`, like the firefly, so any painter can draw it.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'firefly_mark.dart';
import 'pip_motion.dart';

/// The night blue the face is drawn in: dark enough to read on the glow.
const _ink = Color(0xFF0B1328);

/// Paints Pip at [at] as [f] has it. [blink] and [scale] are as for
/// [paintFirefly]; [scale] 1 is a 48-pixel Pip.
void paintPipFigure(Canvas canvas, Offset at, PipFigure f, {double blink = 0.5, double scale = 1}) {
  if (f.dot) {
    paintFirefly(canvas, at, blink: blink, scale: scale);
    return;
  }
  final g = f.grown.clamp(0.0, 1.2);
  // The body swells from the firefly's core (4.5) to a drop 13 across.
  final r = (4.5 + (13 - 4.5) * g) * scale;
  canvas
    ..save()
    ..translate(at.dx, at.dy)
    ..rotate(f.lean);

  // The halo the firefly always has, a little wider round the bigger body.
  canvas.drawCircle(
      Offset.zero,
      r + 18 * scale,
      Paint()
        ..color = fireflyGlow.withValues(alpha: 0.16 + 0.22 * blink)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * scale));

  final hands = ((g - 0.35) / 0.5).clamp(0.0, 1.0);
  if (hands > 0) _paintHands(canvas, r, f.hand, hands, scale);

  // The body: a drop, a touch taller than wide, bright at the heart and
  // softer at the rim, so it looks lit from inside rather than painted.
  final body = Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 2.16);
  canvas.drawOval(
      body,
      Paint()
        ..shader = Gradient.radial(
          Offset(-r * 0.15, -r * 0.2),
          r * 1.25,
          [fireflyCore, fireflyGlow, fireflyGlow.withValues(alpha: 0.75)],
          [0, 0.55, 1],
        ));
  // The rim a shade deeper than the heart, so it reads as a lit drop.
  canvas.drawOval(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * scale
        ..color = const Color(0xFF7FB83A).withValues(alpha: 0.35 * g.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.4 * scale));
  // A soft highlight high on one side, as on a drop of water.
  canvas.drawOval(
      Rect.fromCenter(center: Offset(-r * 0.38, -r * 0.5), width: r * 0.55, height: r * 0.32),
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55 * g.clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.2 * scale));

  final face = ((g - 0.5) / 0.4).clamp(0.0, 1.0);
  if (face > 0) _paintFace(canvas, r, f.eyes, face, scale);
  canvas.restore();
}

void _paintHands(Canvas canvas, double r, double tip, double k, double scale) {
  // Each hand is the body's own light budding out: a soft capsule from the
  // rim with a rounder end, the same green, drawn under the body so the
  // join melts away. No fingers, no stick arms.
  void bud(Offset from, double angle, double length) {
    final w = 4.4 * scale * k;
    final len = length * scale * k;
    final paint = Paint()
      ..color = fireflyGlow.withValues(alpha: 0.95 * k)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.5 * scale);
    canvas
      ..save()
      ..translate(from.dx, from.dy)
      ..rotate(angle)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2, -w / 2, len + w / 2, w), Radius.circular(w / 2)), paint)
      ..drawCircle(Offset(len, 0), w * 0.68, paint)
      ..restore();
  }

  // Resting hand: low on the left, held a little out.
  bud(Offset(-r * 0.7, r * 0.35), math.pi * 0.82, 5);
  // Waving hand: up on the right, tipping either side of upright.
  bud(Offset(r * 0.68, -r * 0.1), -math.pi / 3 + tip, 8.5);
}

void _paintFace(Canvas canvas, double r, double eyes, double k, double scale) {
  final ink = Paint()..color = _ink.withValues(alpha: 0.9 * k);
  for (final side in const [-1.0, 1.0]) {
    final c = Offset(side * r * 0.34, -r * 0.1);
    canvas.drawOval(
        Rect.fromCenter(center: c, width: 2.3 * scale, height: math.max(0.5, 3.2 * eyes) * scale), ink);
    if (eyes > 0.5) {
      canvas.drawCircle(c + Offset(-0.45, -0.7) * scale, 0.55 * scale,
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.8 * k));
    }
  }
  final smile = Paint()
    ..color = _ink.withValues(alpha: 0.8 * k)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3 * scale
    ..strokeCap = StrokeCap.round;
  canvas.drawArc(Rect.fromCenter(center: Offset(0, r * 0.22), width: r * 0.42, height: r * 0.3), 0.25, math.pi - 0.5,
      false, smile);
}
