import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/sky_event.dart';
import '../theme.dart';

/// How full the ring is: fills over the last [window] before the start,
/// then drains as the event runs. Null when it's too far off to show.
double? ringProgress(SkyEvent e, DateTime now, {Duration window = const Duration(minutes: 15)}) {
  final u = now.toUtc();
  if (!u.isBefore(e.end)) return null;
  if (!u.isBefore(e.start)) {
    final total = e.end.difference(e.start).inMilliseconds;
    if (total <= 0) return null;
    return 1 - u.difference(e.start).inMilliseconds / total;
  }
  final until = e.start.difference(u);
  if (until > window) return null;
  return 1 - until.inMilliseconds / window.inMilliseconds;
}

/// A thin arc around [child] that fills as the moment approaches.
class CountdownRing extends StatelessWidget {
  const CountdownRing({super.key, required this.progress, required this.live, required this.child, this.size = 200});
  final double? progress;
  final bool live;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(progress, live),
          child: Center(child: child),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.live);
  final double? progress;
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress;
    if (p == null) return;
    final rect = Offset.zero & size;
    final r = rect.deflate(3);
    canvas.drawArc(r, 0, math.pi * 2, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = LookUpColors.line);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * p.clamp(0.0, 1.0), false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = live ? 4 : 3
          ..strokeCap = StrokeCap.round
          ..color = LookUpColors.blue);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.progress != progress || o.live != live;
}
