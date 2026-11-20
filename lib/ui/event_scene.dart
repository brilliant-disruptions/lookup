import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../domain/models/sky_event.dart';
import 'kit/kit.dart';
import 'theme.dart';

/// A small living picture of what the event will look like, with Pip standing
/// where you will look. It replaces the compass as the first thing on an
/// event sheet: no labels on the picture, the words go under it.
class EventScene extends StatefulWidget {
  const EventScene({
    super.key,
    required this.event,
    required this.live,
    required this.over,
    this.progress,
    this.height = 200,
  });

  final SkyEvent event;
  final bool live, over;

  /// 0..1 through the wait, null when there is no countdown (past events).
  final double? progress;
  final double height;

  @override
  State<EventScene> createState() => _EventSceneState();
}

class _EventSceneState extends State<EventScene> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (still) {
      _c.stop();
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final color = eventStyle(e.type).color;
    final p = widget.progress;
    final pip = _pipSpot(e.type);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: 'A picture of ${e.type.label.toLowerCase()}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: SizedBox(
          height: widget.height,
          child: Stack(fit: StackFit.expand, children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) => CustomPaint(
                  painter: _ScenePainter(e.type, _c.value, color, e.details['supermoon'] == true),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
            ),
            Align(
              alignment: pip,
              // Pip marks where to look in the picture: the dot of light.
              child: PipMark(
                asDot: true,
                size: 64,
                state: widget.over ? PipState.resting : (widget.live ? PipState.found : PipState.idle),
                blinking: !widget.live && !widget.over && p != null && p > 0.93,
              ),
            ),
            if (p != null && !widget.over)
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: widget.live ? 1 : p.clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 3,
                    color: color.withValues(alpha: widget.live ? 0.9 : 0.7),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Where Pip waits in each picture: at the place you will look.
Alignment _pipSpot(SkyEventType t) => switch (t) {
      SkyEventType.iss || SkyEventType.tiangong || SkyEventType.starlinkTrain || SkyEventType.satellitePass => const Alignment(-0.72, 0.5),
      SkyEventType.auroraNow || SkyEventType.auroraOutlook => const Alignment(0, 0.45),
      SkyEventType.meteorShower => const Alignment(0, -0.3),
      SkyEventType.fullMoonRise => const Alignment(0.74, -0.2),
      SkyEventType.lunarEclipse => const Alignment(0, -0.62),
      SkyEventType.solarEclipse => const Alignment(0.74, -0.66),
      SkyEventType.planetPairing || SkyEventType.planetHighlight => const Alignment(0, -0.62),
      SkyEventType.occultation || SkyEventType.occultationNear => const Alignment(0.36, -0.66),
      SkyEventType.rocketLaunch => const Alignment(-0.74, 0.48),
      SkyEventType.comet => const Alignment(-0.55, -0.35),
      SkyEventType.nova => const Alignment(0.35, -0.55),
      SkyEventType.issTransit => const Alignment(0.7, -0.6),
      SkyEventType.skyObject => const Alignment(0, 0),
    };

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.type, this.t, this.color, this.supermoon);
  final SkyEventType type;
  final double t; // 0..1 loop
  final Color color;
  final bool supermoon;

  static const _warm = [Color(0xFF0A0F22), Color(0xFF2A2548), Color(0xFF6B3A45)];
  static const _dusk = [Color(0xFF050816), Color(0xFF16213F), Color(0xFF3A3556)];
  static const _night = [Color(0xFF03050D), Color(0xFF0F1730)];

  @override
  void paint(Canvas canvas, Size s) {
    switch (type) {
      case SkyEventType.iss:
      case SkyEventType.tiangong:
      case SkyEventType.satellitePass:
        _sky(canvas, s, _dusk, 3, 46);
        _pass(canvas, s, 1);
        _hills(canvas, s, 2, const Color(0xFF080C17));
      case SkyEventType.starlinkTrain:
        _sky(canvas, s, _dusk, 3, 46);
        _pass(canvas, s, 7);
        _hills(canvas, s, 2, const Color(0xFF080C17));
      case SkyEventType.issTransit:
        _sky(canvas, s, _night, 5, 14);
        _transit(canvas, s);
      case SkyEventType.auroraNow:
      case SkyEventType.auroraOutlook:
        _sky(canvas, s, _night, 9, 60);
        _aurora(canvas, s);
        _hills(canvas, s, 7, const Color(0xFF04060C), trees: true);
      case SkyEventType.meteorShower:
        _sky(canvas, s, _night, 5, 70);
        _meteors(canvas, s);
        _hills(canvas, s, 4, const Color(0xFF06080F));
      case SkyEventType.fullMoonRise:
        _sky(canvas, s, _warm, 11, 26);
        _moonrise(canvas, s);
        _hills(canvas, s, 6, const Color(0xFF0A0710), trees: true);
      case SkyEventType.lunarEclipse:
        _sky(canvas, s, _night, 13, 48);
        _lunar(canvas, s);
      case SkyEventType.solarEclipse:
        canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF03040A));
        _stars(canvas, s, 17, 30, 0.6);
        _solar(canvas, s);
      case SkyEventType.planetPairing:
        _sky(canvas, s, _dusk, 21, 34);
        _planets(canvas, s, 2);
        _hills(canvas, s, 8, const Color(0xFF080B14));
      case SkyEventType.planetHighlight:
        _sky(canvas, s, _dusk, 21, 34);
        _planets(canvas, s, 1);
        _hills(canvas, s, 8, const Color(0xFF080B14));
      case SkyEventType.occultation:
      case SkyEventType.occultationNear:
        _sky(canvas, s, _night, 25, 40);
        _occult(canvas, s);
      case SkyEventType.rocketLaunch:
        _sky(canvas, s, _warm, 29, 30);
        _rocket(canvas, s);
        _hills(canvas, s, 12, const Color(0xFF09060C));
      case SkyEventType.comet:
        _sky(canvas, s, _night, 31, 60);
        _comet(canvas, s);
      case SkyEventType.nova:
        _sky(canvas, s, _night, 33, 60);
        _nova(canvas, s);
      case SkyEventType.skyObject:
        _sky(canvas, s, _night, 35, 60);
    }
  }

  // ---- shared pieces -----------------------------------------------------

  void _sky(Canvas c, Size s, List<Color> cols, int seed, int stars) {
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height), cols, cols.length == 3 ? const [0, 0.7, 1] : null),
    );
    _stars(c, s, seed, stars, 1);
  }

  void _stars(Canvas c, Size s, int seed, int n, double a) {
    final r = math.Random(seed);
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final x = r.nextDouble() * s.width, y = r.nextDouble() * s.height * 0.8;
      final big = r.nextDouble() > 0.88;
      final base = 0.35 + r.nextDouble() * 0.6;
      final tw = big ? 0.65 + 0.35 * math.sin(t * 2 * math.pi * 2 + i) : 1.0;
      p.color = Colors.white.withValues(alpha: (base * tw * a).clamp(0.0, 1.0));
      c.drawCircle(Offset(x, y), big ? 1.3 : 0.7, p);
    }
  }

  void _hills(Canvas c, Size s, int seed, Color fill, {bool trees = false}) {
    final r = math.Random(seed);
    final base = s.height * 0.84;
    final path = Path()..moveTo(0, s.height)..lineTo(0, base);
    for (double x = 0; x <= s.width; x += 6) {
      path.lineTo(x, base + math.sin(x / (s.width / 8.4) + seed) * 4 + math.sin(x / 12) * 1.5);
    }
    path..lineTo(s.width, s.height)..close();
    final p = Paint()..color = fill;
    c.drawPath(path, p);
    if (trees) {
      for (var i = 0; i < 30; i++) {
        final x = r.nextDouble() * s.width, h = 12 + r.nextDouble() * 18, y = base + 5;
        c.drawPath(Path()..moveTo(x - 5, y)..lineTo(x, y - h)..lineTo(x + 5, y)..close(), p);
      }
    }
  }

  void _glow(Canvas c, Offset o, double r, Color col, double a) {
    c.drawCircle(
      o,
      r,
      Paint()
        ..shader = ui.Gradient.radial(o, r, [col.withValues(alpha: a), col.withValues(alpha: 0)]),
    );
  }

  // ---- satellites --------------------------------------------------------

  Offset _quad(Offset a, Offset b, Offset c2, double u) {
    final m = 1 - u;
    return Offset(m * m * a.dx + 2 * m * u * b.dx + u * u * c2.dx, m * m * a.dy + 2 * m * u * b.dy + u * u * c2.dy);
  }

  void _pass(Canvas c, Size s, int count) {
    final a = Offset(s.width * 0.08, s.height * 0.82), b = Offset(s.width * 0.5, -s.height * 0.3), d = Offset(s.width * 0.92, s.height * 0.72);
    final dot = Paint()..color = const Color(0xFF7CB4FF).withValues(alpha: 0.5);
    for (var i = 0; i <= 26; i++) {
      c.drawCircle(_quad(a, b, d, i / 26), 1.4, dot);
    }
    final head = (t * 1.15) % 1.15;
    for (var k = 0; k < count; k++) {
      final u = head - k * 0.035;
      if (u < 0 || u > 1) continue;
      final o = _quad(a, b, d, u);
      final fade = math.min(1.0, math.min(u * 8, (1 - u) * 8)) * (1 - k * 0.1);
      _glow(c, o, 12, const Color(0xFF7CB4FF), 0.45 * fade);
      c.drawCircle(o, count > 1 ? 2.2 : 3, Paint()..color = Colors.white.withValues(alpha: fade));
    }
  }

  void _transit(Canvas c, Size s) {
    final o = Offset(s.width / 2, s.height * 0.5), r = s.height * 0.3;
    _glow(c, o, r * 2.2, const Color(0xFFFFE9A8), 0.25);
    c.drawCircle(o, r, Paint()..shader = ui.Gradient.radial(o, r, [const Color(0xFFFFF4D6), const Color(0xFFFFD98A)]));
    final u = ((t * 2) % 1.0);
    final x = ui.lerpDouble(o.dx - r * 1.3, o.dx + r * 1.3, Curves.easeInOut.transform(u))!;
    final y = o.dy + r * 0.25 * (u - 0.5);
    c.drawCircle(Offset(x, y), 3.2, Paint()..color = const Color(0xFF0B0F1C));
  }

  // ---- aurora ------------------------------------------------------------

  void _aurora(Canvas c, Size s) {
    final shader = ui.Gradient.linear(Offset(0, s.height * 0.86), Offset(0, s.height * 0.1), [
      const Color(0xFF5CF2B0).withValues(alpha: 0.9),
      const Color(0xFF3BC9A0).withValues(alpha: 0.4),
      const Color(0xFF8A5CF2).withValues(alpha: 0.0),
    ], const [0, 0.55, 1]);
    final mag = ui.Gradient.linear(Offset(0, s.height * 0.86), Offset(0, s.height * 0.2), [
      const Color(0xFFFF5CCF).withValues(alpha: 0.6),
      const Color(0xFF8A5CF2).withValues(alpha: 0.0),
    ]);
    final soft = Paint()
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final ph = t * 2 * math.pi;
    for (var i = 0; i < 46; i++) {
      final f = i / 45;
      final x = s.width * (0.04 + 0.92 * f) + math.sin(ph + f * 5) * 10;
      final topY = s.height * (0.18 + 0.3 * (0.5 + 0.5 * math.sin(f * 7 + ph * 0.8)) + 0.08 * math.sin(f * 17));
      soft
        ..strokeWidth = 8
        ..shader = f > 0.74 ? mag : shader;
      c.drawLine(Offset(x, s.height * 0.86), Offset(x, topY), soft);
    }
  }

  // ---- meteors -----------------------------------------------------------

  void _meteors(Canvas c, Size s) {
    final radiant = Offset(s.width * 0.5, s.height * 0.34);
    const dirs = [-2.7, -1.95, -0.9, -0.2, 0.4, 1.15, 2.0, 2.75];
    for (var k = 0; k < dirs.length; k++) {
      final ph = (t * 1.0 + k * 0.137) % 1.0;
      if (ph > 0.3) continue;
      final u = ph / 0.3;
      final d = Offset(math.cos(dirs[k]), math.sin(dirs[k]));
      final head = radiant + d * (24 + u * s.width * 0.34);
      final tail = head - d * (28 * math.sin(u * math.pi) + 4);
      final a = math.sin(u * math.pi);
      c.drawLine(
        tail,
        head,
        Paint()
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(tail, head, [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: a)]),
      );
    }
  }

  // ---- moon --------------------------------------------------------------

  void _moonrise(Canvas c, Size s) {
    final u = 0.5 - 0.5 * math.cos(t * 2 * math.pi);
    final r = s.height * (supermoon ? 0.27 : 0.22);
    final o = Offset(s.width * 0.45, ui.lerpDouble(s.height * 1.0, s.height * 0.42, Curves.easeOut.transform(u))!);
    final col = Color.lerp(const Color(0xFFFFA25C), const Color(0xFFFFF0D6), u)!;
    _glow(c, o, r * 2.6, const Color(0xFFFFB066), 0.5 * (1 - u * 0.6));
    c.drawCircle(o, r, Paint()..color = col);
    final m = Paint()..color = const Color(0x14000000);
    c.drawCircle(o + Offset(-r * 0.3, -r * 0.2), r * 0.22, m);
    c.drawCircle(o + Offset(r * 0.25, r * 0.28), r * 0.16, m);
  }

  void _lunar(Canvas c, Size s) {
    final xs = [0.12, 0.31, 0.5, 0.69, 0.88];
    final ys = [0.62, 0.46, 0.4, 0.46, 0.62];
    final off = [1.35, 0.7, 0.0, -0.7, -1.35];
    final r = s.height * 0.115;
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final o = Offset(s.width * xs[i], s.height * ys[i]);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    for (var i = 0; i < 5; i++) {
      final o = Offset(s.width * xs[i], s.height * ys[i]);
      final total = i == 2;
      if (total) {
        final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
        _glow(c, o, r * 2.8, const Color(0xFFE1704A), 0.35 + 0.25 * pulse);
        c.drawCircle(o, r, Paint()..shader = ui.Gradient.radial(o - Offset(r * 0.3, r * 0.3), r * 1.6, const [Color(0xFFE1704A), Color(0xFF7A2A1C)]));
      } else {
        c.drawCircle(o, r, Paint()..color = const Color(0xFFE6E0CF));
        c.save();
        c.clipPath(Path()..addOval(Rect.fromCircle(center: o, radius: r)));
        c.drawCircle(o + Offset(off[i] * r, -off[i] * r * 0.2), r, Paint()..color = const Color(0xE02A1410));
        c.restore();
      }
    }
  }

  void _solar(Canvas c, Size s) {
    final o = Offset(s.width / 2, s.height * 0.5), r = s.height * 0.2;
    _glow(c, o, r * 3.4, const Color(0xFFCFD8FF), 0.55 + 0.1 * math.sin(t * 2 * math.pi));
    final ray = Paint()..strokeCap = StrokeCap.round;
    final rot = t * 2 * math.pi * 0.08;
    for (var i = 0; i < 36; i++) {
      final a = i * math.pi / 18 + rot;
      final long = i % 3 == 0 ? 2.2 : (i.isOdd ? 1.6 : 1.9);
      ray
        ..strokeWidth = i % 3 == 0 ? 1.6 : 0.9
        ..color = const Color(0xFFE8EEFF).withValues(alpha: i % 3 == 0 ? 0.55 : 0.3);
      c.drawLine(o + Offset(math.cos(a), math.sin(a)) * r * 1.15, o + Offset(math.cos(a), math.sin(a)) * r * long, ray);
    }
    c.drawCircle(o, r, Paint()..color = Colors.black);
    c.drawCircle(
      o,
      r * 1.03,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFFFFF6D8).withValues(alpha: 0.8),
    );
  }

  // ---- planets -----------------------------------------------------------

  void _planets(Canvas c, Size s, int n) {
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    if (n == 2) {
      final a = Offset(s.width * 0.42, s.height * 0.5), b = Offset(s.width * 0.58, s.height * 0.46);
      final r = RRect.fromRectAndRadius(Rect.fromLTRB(s.width * 0.3, s.height * 0.32, s.width * 0.7, s.height * 0.64), const Radius.circular(40));
      _dashed(c, Path()..addRRect(r), Colors.white.withValues(alpha: 0.25 + 0.3 * pulse));
      _glow(c, a, 24, Colors.white, 0.4);
      c.drawCircle(a, 5.5, Paint()..color = const Color(0xFFFFFDF4));
      _glow(c, b, 20, const Color(0xFFFFE4B0), 0.35);
      c.drawCircle(b, 4.4, Paint()..color = const Color(0xFFFFE4B0));
    } else {
      final a = Offset(s.width * 0.5, s.height * 0.5);
      _glow(c, a, 34 + 6 * pulse, const Color(0xFFFFE4B0), 0.4);
      c.drawCircle(a, 6, Paint()..color = const Color(0xFFFFE4B0));
    }
  }

  void _dashed(Canvas c, Path p, Color col) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = col;
    for (final m in p.computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        c.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
      }
    }
  }

  // ---- occultation -------------------------------------------------------

  void _occult(Canvas c, Size s) {
    final r = s.height * 0.27;
    final star = Offset(s.width * 0.68, s.height * 0.5);
    final u = Curves.easeInOut.transform((t / 0.8).clamp(0.0, 1.0));
    final mo = Offset(ui.lerpDouble(-r, s.width + r, u)!, s.height * 0.5);
    final covered = (mo - star).distance < r;
    if (!covered) {
      final tw = 0.75 + 0.25 * math.sin(t * 2 * math.pi * 6);
      _glow(c, star, 18, const Color(0xFFCFE2FF), 0.5 * tw);
      c.drawCircle(star, 3, Paint()..color = Colors.white);
    }
    c.drawCircle(mo, r, Paint()..color = const Color(0xFFE6E0CF));
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: mo, radius: r)));
    c.drawCircle(mo + Offset(r * 0.55, 0), r * 1.05, Paint()..color = const Color(0xE00A0F1E));
    c.restore();
  }

  // ---- rocket ------------------------------------------------------------

  void _rocket(Canvas c, Size s) {
    final path = Path()
      ..moveTo(s.width * 0.2, s.height * 0.82)
      ..cubicTo(s.width * 0.25, s.height * 0.5, s.width * 0.45, s.height * 0.3, s.width * 0.8, s.height * 0.16);
    final m = path.computeMetrics().first;
    final u = (t * 1.25).clamp(0.0, 1.0);
    final fade = t < 0.8 ? 1.0 : 1 - (t - 0.8) / 0.2;
    if (u > 0.02) {
      final seg = m.extractPath(0, m.length * u);
      c.drawPath(
        seg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
          ..color = const Color(0xFFFFB066).withValues(alpha: 0.3 * fade),
      );
      c.drawPath(
        seg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFE9C4).withValues(alpha: 0.85 * fade),
      );
      final head = m.getTangentForOffset(m.length * u)!.position;
      c.drawCircle(head, 3, Paint()..color = Colors.white.withValues(alpha: fade));
    }
    if (t > 0.4) {
      final g = math.sin(((t - 0.4) / 0.6) * math.pi);
      _glow(c, Offset(s.width * 0.8, s.height * 0.2), s.height * 0.55, const Color(0xFFFF8FB0), 0.3 * g);
    }
  }

  // ---- rare events -------------------------------------------------------

  void _comet(Canvas c, Size s) {
    final drift = math.sin(t * 2 * math.pi) * 6;
    final head = Offset(s.width * 0.7 + drift, s.height * 0.36);
    const dir = Offset(-0.86, 0.5);
    final tail = head + dir * (s.width * 0.5);
    final perp = Offset(-dir.dy, dir.dx);
    final path = Path()
      ..moveTo(head.dx + perp.dx * 6, head.dy + perp.dy * 6)
      ..lineTo(tail.dx + perp.dx * 30, tail.dy + perp.dy * 30)
      ..lineTo(tail.dx - perp.dx * 30, tail.dy - perp.dy * 30)
      ..lineTo(head.dx - perp.dx * 6, head.dy - perp.dy * 6)
      ..close();
    c.drawPath(
      path,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
        ..shader = ui.Gradient.linear(head, tail, [const Color(0xFFBFE8FF).withValues(alpha: 0.65), const Color(0xFF8AA0FF).withValues(alpha: 0)]),
    );
    _glow(c, head, 26, const Color(0xFFDFF4FF), 0.6);
    c.drawCircle(head, 4, Paint()..color = Colors.white);
  }

  void _nova(Canvas c, Size s) {
    final o = Offset(s.width * 0.5, s.height * 0.45);
    final f = 0.6 + 0.4 * math.sin(t * 2 * math.pi);
    _glow(c, o, 44 * f + 10, const Color(0xFFFFD9A0), 0.5);
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.75);
    for (final a in [0.0, math.pi / 2]) {
      final d = Offset(math.cos(a), math.sin(a)) * (26 * f + 8);
      c.drawLine(o - d, o + d, p);
    }
    c.drawCircle(o, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.t != t || old.type != type || old.supermoon != supermoon;
}
