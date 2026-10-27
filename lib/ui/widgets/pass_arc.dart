import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/sky/direction.dart';
import '../format.dart';
import '../kit/event_style.dart';
import '../theme.dart';

/// Where on the pass [now] falls: 0 at rise, 1 at set; null before it starts.
double? passProgress(SkyEvent e, DateTime now) {
  final u = now.toUtc();
  if (u.isBefore(e.start)) return null;
  final total = e.end.difference(e.start).inMilliseconds;
  if (total <= 0) return 1;
  return (u.difference(e.start).inMilliseconds / total).clamp(0.0, 1.0);
}

/// The pass drawn across the card: where it rises, how high it climbs,
/// where it sets. The arc draws itself in; before the pass a light runs the
/// route once so you see which way it goes, then waits where it will rise.
/// Once it's up the dot is where it is right now. Words and times only.
class LivePassArc extends StatefulWidget {
  const LivePassArc({super.key, required this.event, required this.now});
  final SkyEvent event;
  final DateTime now;

  @override
  State<LivePassArc> createState() => _LivePassArcState();
}

class _LivePassArcState extends State<LivePassArc> with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _comet = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _draw.value = 1;
        return;
      }
      _draw.forward().whenComplete(() {
        if (mounted && passProgress(widget.event, widget.now) == null) _comet.forward();
      });
    });
  }

  @override
  void dispose() {
    _draw.dispose();
    _comet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final tint = eventStyle(e.type, details: e.details).color;
    final progress = passProgress(e, widget.now);
    final total = e.duration.inMilliseconds;
    final peakFrac = total <= 0 ? 0.5 : e.peak.difference(e.start).inMilliseconds / total;
    final height = elevationWord(e.peakElevationDeg);
    return Semantics(
      label: 'Rises in the ${compassWord(e.riseAzimuthDeg)} at ${fmtTime(e.start)}, '
          'climbs $height, sets in the ${compassWord(e.setAzimuthDeg)} at ${fmtTime(e.end)}.',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 96,
          child: AnimatedBuilder(
            animation: Listenable.merge([_draw, _comet]),
            builder: (context, _) => CustomPaint(
              painter: _ArcPainter(
                draw: Curves.easeOutCubic.transform(_draw.value),
                comet: _comet.isAnimating ? Curves.easeInOutSine.transform(_comet.value) : null,
                progress: progress,
                peakFrac: peakFrac,
                peakElevation: e.peakElevationDeg,
                tint: tint,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _End(compassAbbrev(e.riseAzimuthDeg), fmtTime(e.start), CrossAxisAlignment.start),
          Expanded(
            child: _End('${height[0].toUpperCase()}${height.substring(1)}', fmtTime(e.peak), CrossAxisAlignment.center,
                small: true),
          ),
          _End(compassAbbrev(e.setAzimuthDeg), fmtTime(e.end), CrossAxisAlignment.end),
        ]),
      ]),
    );
  }
}

class _End extends StatelessWidget {
  const _End(this.top, this.bottom, this.align, {this.small = false});
  final String top, bottom;
  final CrossAxisAlignment align;
  final bool small;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: align, children: [
        // A fixed-height first line so the times below line up across all three.
        SizedBox(
          height: 20,
          child: Align(
            alignment: Alignment.bottomCenter,
            widthFactor: 1,
            child: Text(top,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: small
                    ? const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LookUpColors.grey)
                    : const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 2),
        Text(bottom, style: numeric(size: 12.5, color: LookUpColors.greyDim)),
      ]);
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.draw,
    required this.comet,
    required this.progress,
    required this.peakFrac,
    required this.peakElevation,
    required this.tint,
  });

  /// 0…1 as the arc draws itself in.
  final double draw;

  /// 0…1 while the preview light runs the route; null otherwise.
  final double? comet;

  /// 0…1 during the pass; null before it.
  final double? progress;
  final double peakFrac, peakElevation;
  final Color tint;

  static const _inset = 6.0;

  /// A parabola through rise, peak and set, higher for higher passes.
  Offset _pt(Size s, double f) {
    final base = s.height - 4;
    final h = (peakElevation / 90).clamp(0.3, 1.0) * (s.height - 16);
    final pf = peakFrac.clamp(0.15, 0.85);
    // Two half-parabolas meeting at the peak, so a lopsided pass looks lopsided.
    final local = f < pf ? 1 - (pf - f) / pf : 1 - (f - pf) / (1 - pf);
    final y = h * (1 - (1 - local) * (1 - local));
    return Offset(_inset + f * (s.width - 2 * _inset), base - y);
  }

  Path _path(Size s, double to, {double from = 0}) {
    final p = Path();
    const n = 80;
    for (var i = 0; i <= n; i++) {
      final f = from + (to - from) * i / n;
      final o = _pt(s, f);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size s) {
    final base = s.height - 4;
    final horizon = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    for (var x = 0.0; x < s.width; x += 6) {
      canvas.drawLine(Offset(x, base), Offset(x + 3, base), horizon);
    }
    if (draw <= 0) return;

    // A soft wash under the arc, fading in as it draws.
    final under = _path(s, draw)
      ..lineTo(_pt(s, draw).dx, base)
      ..lineTo(_inset, base)
      ..close();
    canvas.drawPath(
        under,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, 0), Offset(0, base),
              [tint.withValues(alpha: 0.18 * draw), tint.withValues(alpha: 0)]));

    // The route, then the part already flown in full colour.
    canvas.drawPath(
        _path(s, draw),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = tint.withValues(alpha: 0.45));
    final p = progress;
    if (p != null && p > 0) {
      canvas.drawPath(
          _path(s, p * draw),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = tint);
    }

    // Rise and set markers.
    final end = Paint()..color = tint.withValues(alpha: 0.9);
    canvas.drawCircle(_pt(s, 0), 3, end);
    if (draw >= 1) canvas.drawCircle(_pt(s, 1), 3, end);

    // Where it is: the live dot, the preview light with a short tail, or,
    // once the preview is done, waiting where it will rise.
    final at = p ?? comet ?? 0;
    if (draw >= 1) {
      if (p == null && comet != null) {
        for (var i = 1; i <= 10; i++) {
          final f = (at - i * 0.012).clamp(0.0, 1.0);
          canvas.drawCircle(_pt(s, f), 3.2 - i * 0.25, Paint()..color = tint.withValues(alpha: 0.5 - i * 0.045));
        }
      }
      final o = _pt(s, at);
      canvas.drawCircle(
          o,
          13,
          Paint()
            ..color = tint.withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
      canvas.drawCircle(o, 5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter o) =>
      o.draw != draw || o.comet != comet || o.progress != progress || o.peakFrac != peakFrac || o.tint != tint;
}
