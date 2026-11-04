// A lit constellation, drawn the same on the Sky tab and through the camera:
// the rest of the sky steps back, its lines glow, its stars come forward.

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' hide TextStyle;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import '../../domain/sky/catalog.dart';

/// One corner of a constellation's lines: where it is on screen (null when
/// off it), the star it sits on, and how high that is in the sky.
typedef ShapePoint = ({Offset? at, double ra, double dec, Star? star, double altDeg});

/// The cool white the lit lines and stars rise to.
const litStarColor = Color(0xFFDCE6FF);

/// A star's colour from its B–V index: blue-white Rigel, amber Betelgeuse.
Color starColor(double? bv) {
  final b = bv ?? 0.6;
  if (b < 0) return const Color(0xFFBFD4FF);
  if (b < 0.4) return const Color(0xFFF2F5FF);
  if (b < 0.9) return const Color(0xFFFFF4E0);
  if (b < 1.3) return const Color(0xFFFFDDB0);
  return const Color(0xFFFFC28A);
}

/// How long a constellation takes to light up as you turn onto it, or to
/// let go as you turn away: picture, lines and stars together.
const figureFade = Duration(milliseconds: 450);

/// How much of itself the rest of the sky keeps while something is lit
/// (`lit` is the brightest level showing, 0 to 1).
double skyRecede(double lit) => 1 - 0.22 * lit;

/// A gentle twinkle, -1 to 1: each star (by its position) has its own
/// period of 2.6–4.2 s and phase, so they never pulse in step.
double twinkleAt(double raDeg, double decDeg, double secs) {
  final h = ((raDeg * 12.9898 + decDeg * 78.233).abs() * 43.7585) % 1.0;
  return sin(2 * pi * (secs / (2.6 + 1.6 * h) + h * 7));
}

/// Draws a constellation's picture, already placed on [canvas] in image
/// pixels, added to the sky in [tint]. Lit ([t] > 0) it warms a touch and
/// its edges soften, so the drawing gathers round its stars, not in a box.
void paintFigure(Canvas canvas, Image img, Color tint, double t) {
  final warm = Color.from(alpha: tint.a, red: tint.r, green: tint.g * 0.96, blue: tint.b * 0.88);
  final paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = ColorFilter.mode(Color.lerp(tint, warm, t)!, BlendMode.modulate);
  if (t <= 0) {
    canvas.drawImage(img, Offset.zero, paint..blendMode = BlendMode.plus);
    return;
  }
  final (w, h) = (img.width.toDouble(), img.height.toDouble());
  final box = Offset.zero & Size(w, h);
  canvas.saveLayer(box, Paint()..blendMode = BlendMode.plus);
  canvas.drawImage(img, Offset.zero, paint);
  // An oval fading from the middle out to the edges, stretched to the picture.
  final oval = Float64List.fromList([w / 2, 0, 0, 0, 0, h / 2, 0, 0, 0, 0, 1, 0, w / 2, h / 2, 0, 1]);
  final edge = const Color(0xFFFFFFFF).withValues(alpha: 1 - 0.75 * t);
  canvas.drawRect(
      box,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = Gradient.radial(Offset.zero, 1, [const Color(0xFFFFFFFF), edge], [0.55, 1], TileMode.clamp, oval));
  canvas.restore();
}

/// Draws a constellation at level [t] (0 to 1, eased): a soft glow under
/// its lines, the lines themselves in [base], and a halo and core
/// on each of its stars, sized by brightness and in its own colour. [secs]
/// is the twinkle clock (null keeps them steady); like real starlight, stars
/// low in the sky twinkle more than those overhead.
/// Its [name], in [nameStyle], fades in beneath it, the letters easing apart:
/// above it instead when there's no room below inside [bounds] (the sky
/// above the horizon), and always kept inside them. Returns where the name
/// went, so other labels can keep clear of it.
/// Lines longer than [maxJump] wrap round the view and are skipped.
Rect? paintLitConstellation(
  Canvas canvas,
  List<List<ShapePoint>> shape, {
  required double t,
  required Color base,
  required double maxJump,
  double? secs,
  String? name,
  TextStyle? nameStyle,
  Rect? bounds,
  Iterable<Rect> avoid = const [],
}) {
  if (t <= 0) return null;
  final under = Paint()
    ..color = base.withValues(alpha: 0.12 * t)
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
  final over = Paint()
    ..color = base // the usual blue, so the stars stand out against it
    ..strokeWidth = 1.2 + 0.2 * t
    ..strokeCap = StrokeCap.round;
  for (final pass in [under, over]) {
    for (final seg in shape) {
      for (var i = 1; i < seg.length; i++) {
        final (a, b) = (seg[i - 1].at, seg[i].at);
        if (a != null && b != null && (a - b).distance < maxJump) canvas.drawLine(a, b, pass);
      }
    }
  }

  final halo = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  final core = Paint();
  final seen = <(double, double)>{};
  for (final seg in shape) {
    for (final p in seg) {
      if (!seen.add((p.ra, p.dec)) || p.at == null) continue;
      final mag = p.star?.mag ?? 4.0;
      final hue = starColor(p.star?.bv);
      // Each magnitude is a clear step: Rigel beside a 4th-magnitude star.
      final r = (3.6 - 0.6 * mag).clamp(0.9, 4.2);
      final depth = 1.3 - 0.7 * (p.altDeg / 90).clamp(0.0, 1.0);
      final beat = secs == null ? 0.0 : depth * twinkleAt(p.ra, p.dec, secs);
      halo.color = hue.withValues(alpha: t * ((0.5 - 0.05 * mag).clamp(0.25, 0.55) + 0.12 * beat).clamp(0.0, 1.0));
      canvas.drawCircle(p.at!, r * 2.8 + 0.8 * beat, halo);
      // Its true tone, with a little white left at the heart.
      core.color = Color.lerp(const Color(0xFFFFFFFF), hue, 0.7)!.withValues(alpha: 0.95 * t);
      canvas.drawCircle(p.at!, r, core);
    }
  }

  final on = [for (final seg in shape) for (final p in seg) ?p.at];
  if (name == null || nameStyle == null || on.isEmpty) return null;
  final tp = TextPainter(
    text: TextSpan(
      text: name,
      style: nameStyle.copyWith(
          color: (nameStyle.color ?? const Color(0xFFFFFFFF)).withValues(alpha: 0.85 * t), letterSpacing: 0.5 + 2.5 * t),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final rect = litNameRect(on, Size(tp.width, tp.height), bounds, avoid: avoid);
  tp.paint(canvas, rect.topLeft);
  return rect;
}

/// Where a lit constellation's name goes, given its stars [on] screen and
/// the name's [size]: centred beneath the lowest star; above the highest
/// when that would run past the bottom of [bounds] (behind the ground);
/// nudged in from the sides and top so it's never cut off.
///
/// When beneath would sit on something in [avoid] (a planet, the Moon) it
/// goes above instead, if that's clear; never below the ground for it.
Rect litNameRect(List<Offset> on, Size size, Rect? bounds, {Iterable<Rect> avoid = const []}) {
  const gap = 18.0;
  final x = on.fold(0.0, (a, o) => a + o.dx) / on.length;
  final lowest = on.fold(double.negativeInfinity, (a, o) => max(a, o.dy));
  final highest = on.fold(double.infinity, (a, o) => min(a, o.dy));
  Rect at(double top) {
    var left = x - size.width / 2;
    if (bounds != null) {
      left = left.clamp(bounds.left + 4, max(bounds.left + 4, bounds.right - 4 - size.width));
      top = top.clamp(bounds.top + 4, max(bounds.top + 4, bounds.bottom - 4 - size.height));
    }
    return Offset(left, top) & size;
  }

  final beneath = lowest + gap, above = highest - gap - size.height;
  final fitsBeneath = bounds == null || beneath + size.height <= bounds.bottom;
  final first = at(fitsBeneath ? beneath : above);
  if (!fitsBeneath || !avoid.any(first.overlaps)) return first;
  final second = at(above);
  return avoid.any(second.overlaps) ? first : second;
}

/// Whether a label of [size] centred at [at] would run into [taken].
bool labelClashes(Offset at, Size size, Iterable<Rect> taken) {
  final r = Rect.fromCenter(center: at, width: size.width, height: size.height).inflate(4);
  return taken.any(r.overlaps);
}

/// Where to put a plain name of [size] meant for [at], clear of every
/// label in [taken]: there, else just below, else just above. Records the
/// spot in [taken] and returns its centre, or null when all three are
/// taken (the name waits rather than sitting on another).
Offset? placeLabel(Offset at, Size size, List<Rect> taken) {
  final step = size.height + 4; // clear of labelClashes' margin
  return _firstClear([at, at + Offset(0, step), at - Offset(0, step)], size, taken);
}

/// A planet's or the Moon's name, [gap] beneath its centre; else above it,
/// else further down. Bodies are what people look for, so the name is
/// always drawn: when nowhere is clear it goes beneath anyway. Place these
/// before constellation names so the names step around them.
///
/// [disc] is the body's own, ignored: its name is meant to sit by it.
Offset placeBodyLabel(Offset body, double gap, Size size, List<Rect> taken, {Rect? disc}) {
  if (disc != null) taken.remove(disc);
  try {
    return _placeBodyLabel(body, gap, size, taken);
  } finally {
    if (disc != null) taken.add(disc);
  }
}

Offset _placeBodyLabel(Offset body, double gap, Size size, List<Rect> taken) {
  final beneath = body + Offset(0, gap);
  final spot = _firstClear([beneath, body - Offset(0, gap), beneath + Offset(0, size.height + 4)], size, taken);
  if (spot != null) return spot;
  taken.add(Rect.fromCenter(center: beneath, width: size.width, height: size.height));
  return beneath;
}

Offset? _firstClear(List<Offset> spots, Size size, List<Rect> taken) {
  for (final o in spots) {
    if (labelClashes(o, size, taken)) continue;
    taken.add(Rect.fromCenter(center: o, width: size.width, height: size.height));
    return o;
  }
  return null;
}
