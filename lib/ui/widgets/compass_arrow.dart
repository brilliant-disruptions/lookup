import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A static compass rose with an arrow at [azimuthDeg]. (A live, magnetometer
/// driven version is a Phase 2 nicety; the words do the real work.)
class CompassArrow extends StatelessWidget {
  const CompassArrow({super.key, required this.azimuthDeg, this.size = 180});
  final double azimuthDeg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _Painter(azimuthDeg, c.primary, c.onSurface.withValues(alpha: 0.35), label),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.az, this.accent, this.muted, this.label);
  final double az;
  final Color accent;
  final Color muted;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final ring = Paint()
      ..color = muted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, r, ring);
    final tp = TextPainter(textDirection: TextDirection.ltr);
    const labels = ['N', 'E', 'S', 'W'];
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 - math.pi / 2;
      final p = center + Offset(math.cos(a), math.sin(a)) * (r - 16);
      tp.text = TextSpan(
          text: labels[i],
          style: label.copyWith(color: i == 0 ? accent : muted, fontSize: 13, fontWeight: FontWeight.w600));
      tp.layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    final a = az * math.pi / 180 - math.pi / 2;
    final tip = center + Offset(math.cos(a), math.sin(a)) * (r - 34);
    final tail = center - Offset(math.cos(a), math.sin(a)) * 18;
    final arrow = Paint()
      ..color = accent
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(tail, tip, arrow);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx + 14 * math.cos(a + 2.6), tip.dy + 14 * math.sin(a + 2.6))
      ..lineTo(tip.dx + 14 * math.cos(a - 2.6), tip.dy + 14 * math.sin(a - 2.6))
      ..close();
    canvas.drawPath(head, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_Painter old) => old.az != az || old.accent != accent;
}
