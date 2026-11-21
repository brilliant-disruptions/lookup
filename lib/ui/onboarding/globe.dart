/// "Finding your sky": the Earth turns until their place comes round to the
/// front, and a light comes on there. Grid lines only (no map data); the
/// place is where it really is on the globe.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

class FindingGlobe extends StatefulWidget {
  const FindingGlobe({super.key, required this.lat, required this.lon, this.place});
  final double lat, lon;
  final String? place;
  @override
  State<FindingGlobe> createState() => _FindingGlobeState();
}

class _FindingGlobeState extends State<FindingGlobe> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: widget.place == null ? 'Finding your sky' : 'Finding your sky: ${widget.place}',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _Globe(lat: widget.lat, lon: widget.lon, k: still ? 1 : Curves.easeInOutCubic.transform(_c.value), place: widget.place),
        ),
      ),
    );
  }
}

class _Globe extends CustomPainter {
  _Globe({required this.lat, required this.lon, required this.k, this.place});
  final double lat, lon, k;
  final String? place;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * (0.34 + 0.06 * k);
    // Turns from 140° west of them to them, tipping towards their latitude.
    const d = math.pi / 180;
    final lon0 = (lon - 140 * (1 - k)) * d, lat0 = lat * 0.6 * k * d;
    canvas.drawCircle(c, r * 1.4, Paint()..shader = RadialGradient(colors: [LookUpColors.blue.withValues(alpha: 0.16), LookUpColors.blue.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r * 1.4)));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(center: Alignment(-0.3, -0.3), colors: [Color(0xFF1D3F7A), Color(0xFF0A1A3A)])
              .createShader(Rect.fromCircle(center: c, radius: r)));
    // Orthographic projection from (lat0, lon0).
    Offset? at(double la, double lo) {
      final cosc = math.sin(lat0) * math.sin(la) + math.cos(lat0) * math.cos(la) * math.cos(lo - lon0);
      if (cosc < 0) return null;
      final x = math.cos(la) * math.sin(lo - lon0);
      final y = math.cos(lat0) * math.sin(la) - math.sin(lat0) * math.cos(la) * math.cos(lo - lon0);
      return c + Offset(x * r, -y * r);
    }

    final grid = Paint()
      ..color = const Color(0x2EA0BEFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var m = -180; m < 180; m += 20) {
      final path = Path();
      var pen = false;
      for (var la = -88; la <= 88; la += 4) {
        final p = at(la * d, m * d);
        if (p == null) {
          pen = false;
          continue;
        }
        pen ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        pen = true;
      }
      canvas.drawPath(path, grid);
    }
    for (var la = -60; la <= 60; la += 30) {
      final path = Path();
      var pen = false;
      for (var lo = -180; lo <= 180; lo += 4) {
        final p = at(la * d, lo * d);
        if (p == null) {
          pen = false;
          continue;
        }
        pen ? path.lineTo(p.dx, p.dy) : path.moveTo(p.dx, p.dy);
        pen = true;
      }
      canvas.drawPath(path, grid);
    }
    // Their place, lighting up as it comes round.
    final p = at(lat * d, lon * d);
    final on = ((k - 0.55) / 0.45).clamp(0.0, 1.0);
    if (p != null && on > 0) {
      canvas.drawCircle(p, 26 * on, Paint()..shader = RadialGradient(colors: [const Color(0xFFC4F55E).withValues(alpha: 0.6), const Color(0x00C4F55E)]).createShader(Rect.fromCircle(center: p, radius: 26 * on)));
      canvas.drawCircle(p, 4.5 * on, Paint()..color = const Color(0xFFF4FFD9));
      if (place case final name?) {
        final tp = TextPainter(
          text: TextSpan(text: name, style: display(14, weight: FontWeight.w600, color: LookUpColors.white.withValues(alpha: on))),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width / 2);
        tp.paint(canvas, p + Offset(10, -tp.height - 4));
      }
    }
  }

  @override
  bool shouldRepaint(_Globe o) => o.k != k;
}
