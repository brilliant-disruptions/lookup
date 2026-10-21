import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Barely-there film grain, Dearly's paper texture translated to night.
/// Felt, not seen: default 4% opacity, deterministic, painted once.
class Grain extends StatelessWidget {
  const Grain({super.key, this.opacity = 0.04, this.seed = 3, this.borderRadius});
  final double opacity;
  final int seed;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final p = IgnorePointer(
      child: CustomPaint(painter: _GrainPainter(opacity, seed), child: const SizedBox.expand()),
    );
    return borderRadius == null ? p : ClipRRect(borderRadius: borderRadius!, child: p);
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.opacity, this.seed);
  final double opacity;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final light = Paint()..color = Colors.white.withValues(alpha: opacity);
    final dark = Paint()..color = Colors.black.withValues(alpha: opacity * 1.5);
    final n = (size.width * size.height * 0.08).round();
    for (var i = 0; i < n; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), rnd.nextBool() ? light : dark);
    }
  }

  @override
  bool shouldRepaint(_GrainPainter o) => o.opacity != opacity || o.seed != seed;
}
