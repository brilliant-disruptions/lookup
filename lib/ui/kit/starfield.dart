import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A deterministic scatter of stars. Static (no per-frame work); density
/// and brightness are tunable.
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
    final field = IgnorePointer(
      child: CustomPaint(
        painter: _StarPainter(density: density, seed: seed, maxOpacity: maxOpacity),
        child: const SizedBox.expand(),
      ),
    );
    final masked = fadeBottom
        ? ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.transparent],
              stops: [0, 0.6],
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
      final r = 0.35 + mag * mag * 1.1;
      final a = (0.12 + mag * mag * 0.88) * maxOpacity;
      // A few stars carry a faint blue; most are warm-white.
      final tint = rnd.nextDouble() < 0.18 ? const Color(0xFFC4DAFF) : const Color(0xFFF6F2EA);
      paint.color = tint.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), r, paint);
      if (mag > 0.97) {
        paint.color = tint.withValues(alpha: 0.12);
        canvas.drawCircle(Offset(x, y), r * 3, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarPainter o) => o.density != density || o.seed != seed || o.maxOpacity != maxOpacity;
}
