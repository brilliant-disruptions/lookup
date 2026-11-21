/// The ring: where your phone points while you're finding something (the
/// finder, Catch it). Its partner there is the firefly
/// (firefly_mark.dart), the thing you're looking for: bring the firefly
/// into the ring, and the ring glows firefly green once it's there. (On the
/// Sky tab, with nothing to find, the firefly itself marks where you point.)
///
/// Only `dart:ui`, like the firefly.
library;

import 'dart:ui';

import 'firefly_mark.dart';

const _white = Color(0xFFF4F6FA);

/// Paints the ring centred on [at]. [radius] 44 is the finder's size;
/// smaller pictures pass less. [onTarget] lights it up. Just a soft circle,
/// no crosshair or ticks: nothing on screen points a direction but Pip.
void paintReticle(Canvas canvas, Offset at, {double radius = 44, bool onTarget = false, double strength = 1}) {
  final ring = Paint()
    ..color = (onTarget ? fireflyGlow : _white).withValues(alpha: (onTarget ? 0.9 : 0.55) * strength)
    ..style = PaintingStyle.stroke
    ..strokeWidth = onTarget ? 2.5 : 1.2;
  canvas.drawCircle(at, radius, ring);
}
