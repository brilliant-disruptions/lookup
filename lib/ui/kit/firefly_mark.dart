/// The firefly: LookUp's one mark for "it appears here" and "you're
/// pointing here". Firefly yellow-green round a pale core, with a curl of
/// sparks behind it while it's on its way. Nothing in the night sky is that
/// colour, so it never reads as the Sun, the Moon, a planet or a star.
/// The finder flies it; everywhere else it rests. Once you're lined up the
/// trail is gone, so nothing busy sits on the sky you're looking at.
///
/// Only `dart:ui`, so the alert art can paint it in the background isolate.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Firefly yellow-green: yellower than the app's "good" green, so it
/// doesn't read as a status light.
const fireflyGlow = Color(0xFFC4F55E);
const fireflyCore = Color(0xFFF4FFD9);

/// Paints the firefly at [at]. [blink] 0…1 is how bright it is right now
/// (the finder pulses it; at rest it's 0.5). [scale] sizes it for bigger
/// canvases such as the alert picture.
void paintFirefly(Canvas canvas, Offset at, {double blink = 0.5, double scale = 1}) {
  canvas.drawCircle(
      at,
      30 * scale,
      Paint()
        ..color = fireflyGlow.withValues(alpha: 0.18 + 0.32 * blink)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 * scale));
  canvas.drawCircle(
      at,
      10 * scale,
      Paint()
        ..color = fireflyGlow.withValues(alpha: 0.5 + 0.4 * blink)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * scale));
  canvas.drawCircle(at, 4.5 * scale, Paint()..color = fireflyCore.withValues(alpha: 0.75 + 0.25 * blink));
}

/// The sparks it leaves behind, oldest first: small and faint at the tail,
/// bigger and brighter toward the firefly. [strength] fades the whole trail
/// (the finder pulls it in as it lands).
void paintSparkTrail(Canvas canvas, List<Offset> sparks, {double scale = 1, double strength = 1}) {
  if (strength <= 0) return;
  for (var i = 0; i < sparks.length; i++) {
    final f = (i + 1) / (sparks.length + 1);
    canvas.drawCircle(
        sparks[i],
        (1.5 + f * 4) * scale,
        Paint()
          ..color = fireflyGlow.withValues(alpha: (0.06 + f * 0.34) * strength)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale));
  }
}

/// A still curl of sparks arriving at [at] from the direction of [from],
/// for pictures that can't move (the alert picture, the Look up now dial).
/// Oldest first; the firefly itself sits at [at] and isn't included.
/// [curl] bends it sideways as a share of its length.
List<Offset> fireflyCurl(Offset at, Offset from, {int sparks = 12, double curl = 0.3}) {
  final d = at - from;
  final len = d.distance;
  if (len < 1 || sparks <= 0) return const [];
  final n = Offset(-d.dy / len, d.dx / len);
  final mid = from + d / 2 + n * (len * curl);
  return [
    for (var i = 0; i < sparks; i++)
      () {
        final t = i / sparks;
        final u = 1 - t;
        return from * (u * u) + mid * (2 * u * t) + at * (t * t);
      }(),
  ];
}

/// The moment it lines up, [since] seconds after: a small burst of sparks
/// going out once, and the lock ring popping out with a little overshoot
/// before it holds.
void paintFireflyLanding(Canvas canvas, Offset at, double since, {double scale = 1}) {
  if (since < 0) return;
  const burst = 0.7;
  if (since < burst) {
    final p = since / burst;
    final out = 1 - math.pow(1 - p, 3).toDouble();
    for (var i = 0; i < 9; i++) {
      final a = i / 9 * 2 * math.pi + 0.3;
      canvas.drawCircle(
          at + Offset(math.cos(a), math.sin(a)) * (10 + 30 * out) * scale,
          3 * scale,
          Paint()
            ..color = fireflyGlow.withValues(alpha: 0.7 * (1 - p))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * scale));
    }
  }
  final pop = math.min(1.0, since / 0.35);
  final r = 18 * (1 + 0.25 * math.sin(pop * math.pi)) * (0.6 + 0.4 * pop) * scale;
  canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale
        ..color = fireflyGlow.withValues(alpha: 0.9));
}
