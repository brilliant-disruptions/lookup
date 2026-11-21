/// Pip saying hi, painted: a drop of the same green light. It wobbles like
/// water, sends out rings, opens into a soft orb with two small dark eyes,
/// and lifts a droplet off its top. No outline, no mouth, no hands: a light
/// with a little life in it, never a cartoon. With nothing going on it's
/// exactly the firefly.
///
/// Only `dart:ui`, like the firefly, so any painter can draw it.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'firefly_mark.dart';
import 'pip_motion.dart';

/// The night blue the eyes are drawn in: dark enough to read on the glow.
const _ink = Color(0xFF0B1328);

/// Paints Pip at [at] as [g] has it. [blink] and [scale] are as for
/// [paintFirefly]; [scale] 1 is a 48-pixel Pip.
void paintPipGreeting(Canvas canvas, Offset at, PipGreeting g, {double blink = 0.75, double scale = 1}) {
  if (g.dot) {
    paintFirefly(canvas, at, blink: blink, scale: scale);
    return;
  }
  // Rings on the water, behind everything.
  for (final (k, a) in g.ripples) {
    final out = 1 - math.pow(1 - k, 3).toDouble();
    canvas.drawCircle(
        at,
        (8 + out * 44) * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * scale
          ..color = fireflyGlow.withValues(alpha: 0.5 * a * (1 - k)));
  }
  final grown = g.grown.clamp(0.0, 1.0);
  final r = (4.5 + 5.5 * grown) * scale * g.size;
  canvas.drawCircle(
      at,
      r + 22 * scale,
      Paint()
        ..color = fireflyGlow.withValues(alpha: ((0.18 + 0.28 * blink) * g.eyes.glow).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 * scale));

  // The body: round, or wobbling like water.
  final body = Path();
  if (g.wobble == 0) {
    body.addOval(Rect.fromCircle(center: at, radius: r));
  } else {
    const n = 64;
    for (var i = 0; i <= n; i++) {
      final a = i / n * 2 * math.pi;
      // Gentler while it's still small, so the dot never looks spiky.
      final rr = r + g.wobble * scale * (0.3 + 0.7 * grown) * (0.6 * math.sin(3 * a + g.t * 5) + 0.4 * math.sin(5 * a - g.t * 7));
      final p = at + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? body.moveTo(p.dx, p.dy) : body.lineTo(p.dx, p.dy);
    }
    body.close();
  }
  canvas.drawPath(
      body,
      Paint()
        ..shader = Gradient.radial(
          at + Offset(-r * 0.15, -r * 0.2),
          r * 1.25,
          [fireflyCore, fireflyGlow, fireflyGlow.withValues(alpha: 0.75)],
          [0, 0.55, 1],
        ));
  // A soft highlight high on one side, as on a drop of water.
  if (grown > 0.2) {
    canvas.drawOval(
        Rect.fromCenter(center: at + Offset(-r * 0.4, -r * 0.48), width: r * 0.5, height: r * 0.28),
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.45 * grown)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.2 * scale));
  }

  // Two small eyes, nothing else. They look where Pip looks, and their
  // lids, size and glint say how it feels.
  if (g.open > 0) {
    final ink = Paint()..color = _ink.withValues(alpha: 0.88 * (g.open * 3).clamp(0.0, 1.0));
    final e = g.eyes;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(e.tilt);
    for (final side in const [-1.0, 1.0]) {
      final left = side < 0;
      final c = Offset(side * r * 0.3 + g.lookX * r * 0.18, -r * 0.05 + g.lookY * r * 0.15);
      _paintEye(
        canvas,
        c,
        w: 2.2 * scale * (left ? e.sizeL : e.sizeR),
        h: math.max(0.4, 3.4 * g.open) * scale * (left ? e.sizeL : e.sizeR),
        lid: e.lid,
        slant: e.slant * side,
        smile: left ? e.smileL : e.smileR,
        glint: g.open > 0.6 ? e.glint : 0,
        ink: ink,
      );
    }
    canvas.restore();
  }

  // The droplet lifted off the top.
  if (g.drop case final d?) {
    final c = at + Offset(0, -r - d.height * scale);
    final ds = d.size * scale;
    canvas.drawCircle(
        c,
        ds * 3,
        Paint()
          ..color = fireflyGlow.withValues(alpha: 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale));
    canvas.drawOval(Rect.fromCenter(center: c, width: ds * 1.8, height: ds * 2.2), Paint()..color = fireflyCore);
  }
}

/// One eye at [c]: an oval [w] by [h], its top lid down by [lid] and tilted
/// by [slant] (positive drops the outer corner), its lower lid pushed up
/// into a smile by [smile], and a glint of light.
void _paintEye(Canvas canvas, Offset c,
    {required double w, required double h, required double lid, required double slant, required double smile, required double glint, required Paint ink}) {
  final oval = Rect.fromCenter(center: c, width: w, height: h);
  var eye = Path()..addOval(oval);
  if (lid > 0.01 || slant.abs() > 0.01) {
    // Keep what's below the lid line, which tilts with the slant.
    final y = oval.top + h * lid;
    final dy = slant * h * 0.45;
    final below = Path()
      ..moveTo(c.dx - w * 2, y - dy)
      ..lineTo(c.dx + w * 2, y + dy)
      ..lineTo(c.dx + w * 2, c.dy + h * 2)
      ..lineTo(c.dx - w * 2, c.dy + h * 2)
      ..close();
    eye = Path.combine(PathOperation.intersect, eye, below);
  }
  if (smile > 0.02) {
    // A circle rising from below takes the bottom away: a crescent, like smiling eyes.
    final cr = w * 1.6;
    final cy = c.dy + h / 2 * (2.4 - 2.0 * smile) + cr * 0.45;
    eye = Path.combine(PathOperation.difference, eye, Path()..addOval(Rect.fromCircle(center: Offset(c.dx, cy), radius: cr)));
  }
  canvas.drawPath(eye, ink);
  if (glint > 0.05) {
    canvas.drawCircle(c + Offset(-w * 0.18, -h * 0.2), w * 0.19, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * glint));
  }
}

