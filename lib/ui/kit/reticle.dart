/// The ring: LookUp's one mark for "you", meaning where your phone points.
/// Its partner is the firefly (firefly_mark.dart), the one mark for the
/// thing you're looking for. Bring the firefly into the ring; the ring
/// glows firefly green once it's there. Never swap them.
///
/// Only `dart:ui`, like the firefly.
library;

import 'dart:ui';

import 'firefly_mark.dart';

const _white = Color(0xFFF4F6FA);
const _grey = Color(0xFFA0A8B8);

/// Paints the ring centred on [at]. [radius] 44 is the finder's size;
/// smaller pictures pass less. [onTarget] lights it up.
void paintReticle(Canvas canvas, Offset at, {double radius = 44, bool onTarget = false, double strength = 1}) {
  final ring = Paint()
    ..color = (onTarget ? fireflyGlow : _white).withValues(alpha: (onTarget ? 0.9 : 0.55) * strength)
    ..style = PaintingStyle.stroke
    ..strokeWidth = onTarget ? 2.5 : 1.5;
  canvas.drawCircle(at, radius, ring);
  final tick = Paint()
    ..color = _grey.withValues(alpha: 0.5 * strength)
    ..strokeWidth = 1.3;
  final inner = radius * 52 / 44, outer = radius * 64 / 44;
  for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
    canvas.drawLine(at + d * inner, at + d * outer, tick);
  }
}
