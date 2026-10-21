import 'package:flutter/material.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/sky/direction.dart';
import '../format.dart';
import '../theme.dart';

/// rise → peak → set over a horizon line, with progress when live.
class PassTimeline extends StatelessWidget {
  const PassTimeline({super.key, required this.event, required this.now});
  final SkyEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final total = event.duration.inMilliseconds.toDouble();
    final elapsed = now.toUtc().difference(event.start).inMilliseconds.toDouble();
    final progress = total <= 0 ? 0.0 : (elapsed / total).clamp(0.0, 1.0);
    final peakFrac = total <= 0 ? 0.5 : event.peak.difference(event.start).inMilliseconds / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 70,
          child: CustomPaint(
            painter: _ArcPainter(
              peakFrac: peakFrac,
              peakElevation: event.peakElevationDeg,
              progress: progress,
              accent: c.primary,
              muted: c.onSurface.withValues(alpha: 0.3),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Label('Rises ${compassAbbrev(event.riseAzimuthDeg)}', fmtTime(event.start)),
            _Label('Peak ${event.peakElevationDeg.round()}° ${compassAbbrev(event.peakAzimuthDeg)}', fmtTime(event.peak),
                align: CrossAxisAlignment.center),
            _Label('Sets ${compassAbbrev(event.setAzimuthDeg)}', fmtTime(event.end),
                align: CrossAxisAlignment.end),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.top, this.bottom, {this.align = CrossAxisAlignment.start});
  final String top, bottom;
  final CrossAxisAlignment align;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: align,
        children: [
          Text(top.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10.5, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
          Text(bottom, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: LookUpColors.grey)),
        ],
      );
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.peakFrac, required this.peakElevation, required this.progress, required this.accent, required this.muted});
  final double peakFrac, peakElevation, progress;
  final Color accent, muted;

  Offset _pt(Size s, double f) {
    final x = f * s.width;
    final h = (peakElevation / 90).clamp(0.15, 1.0) * (s.height - 10);
    // Simple triangle-ish arc: parabola through (0,0), (peakFrac,h), (1,0).
    final denom = peakFrac * (1 - peakFrac);
    final y = denom <= 0 ? 0.0 : h * (f * (1 - f)) / denom;
    return Offset(x, s.height - 4 - y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(Offset(0, size.height - 4), Offset(size.width, size.height - 4),
        Paint()..color = muted..strokeWidth = 1);
    final path = Path()..moveTo(0, size.height - 4);
    for (var i = 1; i <= 60; i++) {
      final p = _pt(size, i / 60);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()..color = muted..style = PaintingStyle.stroke..strokeWidth = 2);
    if (progress > 0) {
      final done = Path()..moveTo(0, size.height - 4);
      final n = (progress * 60).round();
      for (var i = 1; i <= n; i++) {
        final p = _pt(size, i / 60);
        done.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(done, Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 3);
      canvas.drawCircle(_pt(size, progress), 6, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter o) => o.progress != progress || o.peakFrac != peakFrac;
}
