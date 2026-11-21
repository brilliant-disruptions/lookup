/// "Lighting up your sky": while LookUp works out their sky, Pip sends the
/// real stars over their place out to where they sit, brightest first, and
/// the horizon rises with the place's name on it. The last frame is the
/// first frame of the sky they then drag around (the same view and moment
/// as [FirstLookSky]'s start), so one becomes the other.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../domain/finder/pointing.dart';
import '../../domain/photo/framing.dart' show levelPose;
import '../../domain/sky/catalog.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// How long the stars take to fly out and the horizon to rise.
const lightUpTime = Duration(milliseconds: 2300);

class LightUpSky extends StatefulWidget {
  const LightUpSky({
    super.key,
    required this.catalog,
    required this.lat,
    required this.lon,
    required this.at,
    required this.look,
    this.place,
    this.onDone,
  });

  final SkyCatalog catalog;
  final double lat, lon;

  /// The moment and view of the sky they'll see next.
  final DateTime at;
  final SkyDir look;
  final String? place;
  final VoidCallback? onDone;

  @override
  State<LightUpSky> createState() => _LightUpSkyState();
}

class _LightUpSkyState extends State<LightUpSky> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: lightUpTime)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    });

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
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final r = levelPose(widget.look);
      // The stars in view, brightest first, where they'll be.
      final stars = <({Offset at, double mag})>[];
      for (final s in widget.catalog.stars) {
        if (s.mag > 4.6) break;
        final h = widget.catalog.place(s.raDeg, s.decDeg, widget.at, widget.lat, widget.lon);
        if (h.altitudeDeg < 0) continue;
        final p = projectToScreen(r, SkyDir(h.azimuthDeg, h.altitudeDeg), declinationDeg: 0, previewHeightPx: size.height);
        if (p == null || p.x.abs() > size.width / 2 + 10 || p.y.abs() > size.height / 2 + 10) continue;
        stars.add((at: Offset(size.width / 2 + p.x, size.height / 2 + p.y), mag: s.mag));
      }
      // The stick figures, which draw in once the stars are home.
      final lines = <List<Offset>>[];
      Offset? at(double ra, double dec) {
        final h = widget.catalog.place(ra, dec, widget.at, widget.lat, widget.lon);
        final p = projectToScreen(r, SkyDir(h.azimuthDeg, h.altitudeDeg), declinationDeg: 0, previewHeightPx: size.height);
        return p == null ? null : Offset(size.width / 2 + p.x, size.height / 2 + p.y);
      }

      for (final c in widget.catalog.constellations) {
        for (final seg in c.lines) {
          var run = <Offset>[];
          for (final (ra, dec) in seg) {
            final o = at(ra, dec);
            if (o == null || o.dx < -200 || o.dx > size.width + 200 || o.dy < -200 || o.dy > size.height + 200) {
              if (run.length > 1) lines.add(run);
              run = [];
              continue;
            }
            run.add(o);
          }
          if (run.length > 1) lines.add(run);
        }
      }
      final horizon = projectToScreen(r, SkyDir(widget.look.azimuthDeg, 0), declinationDeg: 0, previewHeightPx: size.height);
      final pip = Offset(size.width / 2, size.height * 0.38);
      return Stack(children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              key: const Key('light-up-sky'),
              painter: _LightUp(
                stars: stars,
                lines: lines,
                from: pip,
                k: still ? 1 : _c.value,
                horizonY: horizon == null ? size.height * 0.8 : size.height / 2 + horizon.y,
                place: widget.place,
              ),
            ),
          ),
        ),
        // Pip, sending them out; it fades as the sky takes over.
        Positioned(
          left: pip.dx - 45,
          top: pip.dy - 45,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) => Opacity(opacity: still ? 1 : (1 - ((_c.value - 0.82) / 0.18)).clamp(0.0, 1.0), child: child),
            child: const PipMark(size: 90, state: PipState.greet),
          ),
        ),
      ]);
    });
  }
}

class _LightUp extends CustomPainter {
  _LightUp({required this.stars, required this.lines, required this.from, required this.k, required this.horizonY, this.place});
  final List<({Offset at, double mag})> stars;
  final List<List<Offset>> lines;
  final Offset from;
  final double k, horizonY;
  final String? place;

  @override
  void paint(Canvas canvas, Size size) {
    // The night sky, as the sky page draws it.
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF03050C), Color(0xFF0B1328), Color(0xFF16213E)],
            stops: [0, 0.65, 1],
          ).createShader(Offset.zero & size));
    // Each star leaves Pip in turn, brightest first, and eases into place.
    final n = math.max(1, stars.length);
    for (var i = 0; i < stars.length; i++) {
      final s = stars[i];
      final start = 0.05 + 0.5 * (i / n);
      final t = ((k - start) / 0.35).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final e = Curves.easeOutCubic.transform(t);
      final p = Offset.lerp(from, s.at, e)!;
      final r = (3.0 - s.mag * 0.45).clamp(0.9, 3.4);
      final a = (0.5 + (4.6 - s.mag) * 0.14).clamp(0.45, 1.0);
      if (t < 1) {
        // A short streak behind it while it flies.
        final tail = Offset.lerp(from, s.at, math.max(0, e - 0.12))!;
        canvas.drawLine(
            tail,
            p,
            Paint()
              ..strokeWidth = r
              ..strokeCap = StrokeCap.round
              ..shader = LinearGradient(colors: [const Color(0x00C4F55E), Color.fromRGBO(244, 255, 217, a * 0.7)]).createShader(Rect.fromPoints(tail, p + const Offset(0.1, 0.1))));
      }
      canvas.drawCircle(p, r, Paint()..color = Color.fromRGBO(244, 246, 250, a));
    }
    // Then the stick figures draw in, as the sky page shows them.
    final l = ((k - 0.62) / 0.33).clamp(0.0, 1.0);
    if (l > 0) {
      final pen = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = LookUpColors.blue.withValues(alpha: 0.45 * l);
      for (final run in lines) {
        final path = Path()..moveTo(run.first.dx, run.first.dy);
        // Each line grows from its first star.
        for (var i = 1; i < run.length; i++) {
          final f = (l * (run.length - 1) - (i - 1)).clamp(0.0, 1.0);
          if (f <= 0) break;
          final to = Offset.lerp(run[i - 1], run[i], f)!;
          path.lineTo(to.dx, to.dy);
        }
        canvas.drawPath(path, pen);
      }
    }
    // The horizon rises with their place on it.
    final g = Curves.easeOutCubic.transform(((k - 0.55) / 0.4).clamp(0.0, 1.0));
    if (g > 0) {
      final y = size.height + (horizonY - size.height) * g;
      final path = Path()..moveTo(0, size.height);
      for (var x = 0.0; x <= size.width; x += 6) {
        path.lineTo(x, y - math.max(0, math.sin(x * 0.013) * 9 + math.sin(x * 0.041) * 5 + math.sin(x * 0.11) * 2));
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF04060B));
      if (place case final name?) {
        final tp = TextPainter(
          text: TextSpan(text: name, style: display(15, weight: FontWeight.w600, color: LookUpColors.grey.withValues(alpha: g))),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width - 40);
        tp.paint(canvas, Offset((size.width - tp.width) / 2, y + 22));
      }
    }
  }

  @override
  bool shouldRepaint(_LightUp o) => o.k != k;
}
