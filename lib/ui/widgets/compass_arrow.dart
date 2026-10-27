import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A static compass dial with a needle at [azimuthDeg]. (A live, magnetometer
/// driven version is the finder's job; the words do the real work.)
class CompassArrow extends StatelessWidget {
  const CompassArrow({super.key, required this.azimuthDeg, this.size = 180});
  final double azimuthDeg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelLarge ?? const TextStyle();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _Painter(azimuthDeg, label)),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.az, this.label);
  final double az;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;

    // Dial: a faint disc, lit a little from above.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(center: Alignment(0, -0.4), colors: [Color(0x1AFFFFFF), Color(0x08FFFFFF)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawCircle(c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = LookUpColors.line);

    // Ticks every 15°, longer on the cardinals.
    final tick = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2;
    for (var d = 0; d < 360; d += 15) {
      final a = d * math.pi / 180 - math.pi / 2;
      final major = d % 90 == 0;
      final len = major ? 9.0 : 5.0;
      tick.color = major ? LookUpColors.grey : LookUpColors.greyDim.withValues(alpha: 0.6);
      final u = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + u * (r - 6), c + u * (r - 6 - len), tick);
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    const labels = ['N', 'E', 'S', 'W'];
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2 - math.pi / 2;
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 28);
      tp.text = TextSpan(
          text: labels[i],
          style: label.copyWith(
              color: i == 0 ? LookUpColors.blue : LookUpColors.grey, fontSize: 13, fontWeight: FontWeight.w600));
      tp.layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }

    // Needle: a slim tapered blade toward the target, a short grey tail.
    final a = az * math.pi / 180 - math.pi / 2;
    final u = Offset(math.cos(a), math.sin(a));
    final n = Offset(-u.dy, u.dx);
    final tip = c + u * (r - 44);
    final tail = c - u * (r * 0.32);
    const w = 6.0;
    final blade = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(c.dx + n.dx * w, c.dy + n.dy * w)
      ..lineTo(c.dx - n.dx * w, c.dy - n.dy * w)
      ..close();
    final back = Path()
      ..moveTo(tail.dx, tail.dy)
      ..lineTo(c.dx + n.dx * w, c.dy + n.dy * w)
      ..lineTo(c.dx - n.dx * w, c.dy - n.dy * w)
      ..close();
    canvas.drawPath(
        blade,
        Paint()
          ..color = LookUpColors.blue.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawPath(back, Paint()..color = LookUpColors.greyDim.withValues(alpha: 0.7));
    canvas.drawPath(blade, Paint()..color = LookUpColors.blue);
    canvas.drawCircle(c, 5, Paint()..color = LookUpColors.white);
  }

  @override
  bool shouldRepaint(_Painter old) => old.az != az;
}
