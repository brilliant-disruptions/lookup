/// The real sky around one moment, framed on a pass: the stars and
/// constellation figures that were really there, the Moon in its phase, the
/// horizon, and the pass's own track through them. Share posters use it, so
/// each one is a true snapshot of that minute over that place.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/sky/astro.dart';
import '../domain/sky/backdrop.dart';
import '../domain/sky/catalog.dart';
import 'real_sky.dart';

class SkySnapshot extends StatelessWidget {
  const SkySnapshot({
    super.key,
    required this.catalog,
    required this.utc,
    required this.lat,
    required this.lon,
    required this.centerAz,
    required this.centerAlt,
    this.track = const [],
    this.mark,
    this.tint = const Color(0xFF5AA2FF),
    this.labels = const [],
  });

  final SkyCatalog catalog;
  final DateTime utc;
  final double lat, lon;

  /// Where to look: the frame is centred here, then widened to fit [track].
  final double centerAz, centerAlt;

  /// The pass, rise to set; empty for things that don't move across.
  final List<Horizontal> track;

  /// Something to ring when there's no track (a planet pairing, the Moon).
  final Horizontal? mark;
  final Color tint;

  /// Names to write beside things in the frame ("Vega", "Jupiter").
  final List<(String, Horizontal)> labels;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _SnapshotPainter(this),
        child: const SizedBox.expand(),
      );
}

class _SnapshotPainter extends CustomPainter {
  _SnapshotPainter(this.w);
  final SkySnapshot w;

  @override
  void paint(Canvas canvas, Size size) {
    ({double x, double y})? at(Horizontal h) =>
        backdropProject(h, centerAz: w.centerAz, centerAlt: w.centerAlt);
    Offset? toScreen(({double x, double y})? p, double scale, Offset origin) =>
        p == null ? null : origin + Offset(p.x * scale, -p.y * scale);

    // Fit the track (and the mark) with a margin; never tighter than 50°
    // across or wider than 150°.
    final pts = [for (final h in w.track) at(h)].nonNulls.toList();
    if (w.mark case final m?) {
      if (at(m) case final p?) pts.add(p);
    }
    double fov2(double deg) => 2 * math.tan(deg * math.pi / 360);
    var minX = -fov2(25), maxX = fov2(25), minY = -fov2(25) * 0.8, maxY = fov2(25) * 0.8;
    for (final p in pts) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final scale = math.max(
      math.min(size.width * 0.84 / (maxX - minX), size.height * 0.78 / (maxY - minY)),
      size.width / 2 / fov2(75),
    );
    final origin = Offset(size.width / 2 - (minX + maxX) / 2 * scale, size.height / 2 + (minY + maxY) / 2 * scale);
    Offset? o(Horizontal h) => toScreen(at(h), scale, origin);
    final bounds = (Offset.zero & size).inflate(6);

    // Horizon, and the ground below it.
    final horizon = <Offset>[
      for (var d = -100.0; d <= 100; d += 4)
        ?o(Horizontal((w.centerAz + d + 360) % 360, 0)),
    ];
    if (horizon.length > 1) {
      final ground = Path()..moveTo(horizon.first.dx, size.height + 10);
      for (final p in horizon) {
        ground.lineTo(p.dx, p.dy);
      }
      ground
        ..lineTo(horizon.last.dx, size.height + 10)
        ..close();
      canvas.drawPath(ground, Paint()..color = const Color(0xE604060B));
      final line = Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 1;
      for (var i = 1; i < horizon.length; i++) {
        canvas.drawLine(horizon[i - 1], horizon[i], line);
      }
    }

    final lines = Paint()
      ..color = const Color(0xFF5AA2FF).withValues(alpha: 0.16)
      ..strokeWidth = 0.8;
    for (final con in w.catalog.constellations) {
      for (final seg in con.lines) {
        Offset? prev;
        for (final (ra, dec) in seg) {
          final p = o(w.catalog.place(ra, dec, w.utc, w.lat, w.lon));
          if (p != null && prev != null && (bounds.contains(p) || bounds.contains(prev))) canvas.drawLine(prev, p, lines);
          prev = p;
        }
      }
    }

    final dot = Paint();
    for (final st in w.catalog.stars) {
      if (st.mag > 5) continue;
      final p = o(st.horizontal(w.utc, w.lat, w.lon));
      if (p == null || !bounds.contains(p)) continue;
      final bright = ((5 - st.mag) / 6.5).clamp(0.0, 1.0);
      dot.color = Colors.white.withValues(alpha: 0.25 + bright * 0.75);
      canvas.drawCircle(p, 0.5 + bright * bright * 2.4, dot);
    }

    final mh = moonHorizontal(w.utc, w.lat, w.lon);
    if (o(mh) case final mp? when bounds.contains(mp)) {
      final step = o(stepToward(mh, sunHorizontal(w.utc, w.lat, w.lon), 2));
      final dir = step == null ? 0.0 : math.atan2(step.dy - mp.dy, step.dx - mp.dx);
      paintMoonPhase(canvas, mp, moonIllumination(w.utc), dir, r: 8);
    }

    for (final (name, h) in w.labels) {
      if (o(h) case final p? when bounds.contains(p)) {
        canvas.drawCircle(
            p,
            7,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = Colors.white70);
        _label(canvas, name, p + const Offset(4, 0));
      }
    }

    // The pass itself: a glow, the line, its peak, and which way it went.
    final path = [for (final h in w.track) if (h.altitudeDeg >= 0) o(h)].nonNulls.toList();
    if (path.length > 1) {
      final p = Path()..moveTo(path.first.dx, path.first.dy);
      for (final q in path.skip(1)) {
        p.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(
          p,
          Paint()
            ..color = w.tint.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawPath(
          p,
          Paint()
            ..color = w.tint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round);
      final a = path[path.length - 2], b = path.last;
      final ang = math.atan2(b.dy - a.dy, b.dx - a.dx);
      final head = Path()
        ..moveTo(b.dx + 9 * math.cos(ang), b.dy + 9 * math.sin(ang))
        ..lineTo(b.dx + 7 * math.cos(ang + 2.4), b.dy + 7 * math.sin(ang + 2.4))
        ..lineTo(b.dx + 7 * math.cos(ang - 2.4), b.dy + 7 * math.sin(ang - 2.4))
        ..close();
      canvas.drawPath(head, Paint()..color = w.tint);
      final high = w.track.reduce((x, y) => y.altitudeDeg > x.altitudeDeg ? y : x);
      if (o(high) case final hp?) {
        canvas.drawCircle(
            hp,
            11,
            Paint()
              ..color = w.tint.withValues(alpha: 0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        canvas.drawCircle(hp, 4.2, Paint()..color = Colors.white);
      }
    } else if (w.mark case final m?) {
      if (o(m) case final mp?) {
        canvas.drawCircle(
            mp,
            16,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = w.tint);
      }
    }
  }

  static void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white, shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at + const Offset(7, -7) - Offset(0, tp.height / 2));
  }

  @override
  bool shouldRepaint(_SnapshotPainter o) => o.w != w;
}
