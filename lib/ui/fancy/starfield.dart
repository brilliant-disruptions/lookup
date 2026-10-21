import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A deterministic scatter of stars: the dark-sky answer to Dearly's warm
/// paper. Static (no per-frame work); density and brightness are tunable.
class Starfield extends StatelessWidget {
  const Starfield({
    super.key,
    this.density = 0.00035,
    this.seed = 7,
    this.maxOpacity = 0.9,
    this.fadeBottom = true,
    this.child,
  });

  /// Stars per logical pixel² (≈ 140 stars on a 390×1000 canvas at 0.00035).
  final double density;
  final int seed;
  final double maxOpacity;

  /// Fade the field out toward the bottom so content stays readable.
  final bool fadeBottom;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final field = CustomPaint(
      painter: _StarPainter(density: density, seed: seed, maxOpacity: maxOpacity),
      child: const SizedBox.expand(),
    );
    final masked = fadeBottom
        ? ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.45, 1],
            ).createShader(r),
            child: field,
          )
        : field;
    if (child == null) return masked;
    return Stack(fit: StackFit.passthrough, children: [Positioned.fill(child: masked), child!]);
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter({required this.density, required this.seed, required this.maxOpacity});
  final double density;
  final int seed;
  final double maxOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final n = (size.width * size.height * density).round();
    final paint = Paint();
    for (var i = 0; i < n; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final mag = rnd.nextDouble(); // 0 faint … 1 bright
      final r = 0.4 + mag * mag * 1.3;
      final a = (0.15 + mag * 0.85) * maxOpacity;
      // A few stars carry a faint blue; most are warm-white.
      final tint = rnd.nextDouble() < 0.15 ? const Color(0xFFBFD9FF) : const Color(0xFFF4F1EA);
      paint.color = tint.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), r, paint);
      if (mag > 0.96) {
        // Bright star: soft halo + a tiny cross flare.
        paint.color = tint.withValues(alpha: 0.18);
        canvas.drawCircle(Offset(x, y), r * 3.2, paint);
        paint.color = tint.withValues(alpha: 0.5);
        paint.strokeWidth = 0.6;
        canvas.drawLine(Offset(x - r * 4, y), Offset(x + r * 4, y), paint);
        canvas.drawLine(Offset(x, y - r * 4), Offset(x, y + r * 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarPainter o) =>
      o.density != density || o.seed != seed || o.maxOpacity != maxOpacity;
}
