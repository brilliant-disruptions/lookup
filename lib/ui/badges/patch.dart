/// A badge as an embroidered patch, like the ones on astronauts' sleeves:
/// a thread-coloured rim (bronze, silver or gold for levels), a stitched
/// ring, a deep-sky middle and its own picture. Locked patches are a faint
/// outline of the picture with a ring for how close you are; a secret is
/// a question mark until it's found.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart' hide Badge;

import '../../domain/log/sky_log.dart';
import '../theme.dart';
import '../kit/kit.dart' show fireflyGlow;

const _bronze = Color(0xFFD39A62), _silver = Color(0xFFCBD5E3), _gold = Color(0xFFF5C76B);
const _ink = Color(0xFF04060B), _night = Color(0xFF0B1328), _white = Color(0xFFF4F6FA);

/// The deep colour behind each picture, and its thread colour.
({Color ground, Color thread}) patchColours(BadgeArt a) => switch (a) {
      BadgeArt.pip => (ground: const Color(0xFF1C2A12), thread: fireflyGlow),
      BadgeArt.firstLight => (ground: const Color(0xFF2A2412), thread: _gold),
      BadgeArt.station || BadgeArt.overhead || BadgeArt.bothStations => (ground: const Color(0xFF0E2140), thread: LookUpColors.blue),
      BadgeArt.regular => (ground: const Color(0xFF14203A), thread: _gold),
      BadgeArt.planets => (ground: const Color(0xFF2A2112), thread: _gold),
      BadgeArt.moonPhases => (ground: const Color(0xFF151C2E), thread: _silver),
      BadgeArt.venus => (ground: const Color(0xFF2A2412), thread: _gold),
      BadgeArt.train => (ground: const Color(0xFF1E1640), thread: LookUpColors.violet),
      BadgeArt.aurora => (ground: const Color(0xFF0E2A22), thread: LookUpColors.good),
      BadgeArt.meteor => (ground: const Color(0xFF101C3A), thread: LookUpColors.cyan),
      BadgeArt.bloodMoon => (ground: const Color(0xFF2A1210), thread: LookUpColors.red),
      BadgeArt.eclipse => (ground: const Color(0xFF1A1408), thread: _gold),
      BadgeArt.rocket => (ground: const Color(0xFF22121A), thread: LookUpColors.orange),
      BadgeArt.owl || BadgeArt.upPastThree => (ground: const Color(0xFF16122A), thread: LookUpColors.violet),
      BadgeArt.transit => (ground: const Color(0xFF2A1A0E), thread: LookUpColors.orange),
      BadgeArt.doubleNight => (ground: const Color(0xFF101C3A), thread: LookUpColors.rose),
    };

Color tierColour(BadgeTier t) => switch (t) {
      BadgeTier.bronze => _bronze,
      BadgeTier.silver => _silver,
      BadgeTier.gold => _gold,
    };

class BadgePatch extends StatelessWidget {
  const BadgePatch({
    super.key,
    required this.art,
    this.tier,
    this.earned = true,
    this.secret = false,
    this.progress,
    this.size = 84,
    this.stitch = 1,
  });

  /// A patch for [b] as it stands.
  factory BadgePatch.of(Badge b, {Key? key, double size = 84, double stitch = 1}) {
    final p = b.progress;
    return BadgePatch(
      key: key,
      art: b.art,
      tier: b.tier,
      earned: b.earned,
      secret: b.hidden,
      progress: p == null ? null : p.got / p.of,
      size: size,
      stitch: stitch,
    );
  }

  final BadgeArt art;
  final BadgeTier? tier;
  final bool earned, secret;

  /// 0…1 towards the next step, drawn as a ring (locked or levelling).
  final double? progress;
  final double size;

  /// How much of the stitched ring is sewn (animates when earned).
  final double stitch;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PatchPainter(art, tier, earned, secret, progress, stitch)),
      );
}

class _PatchPainter extends CustomPainter {
  _PatchPainter(this.art, this.tier, this.earned, this.secret, this.progress, this.stitch);
  final BadgeArt art;
  final BadgeTier? tier;
  final bool earned, secret;
  final double? progress;
  final double stitch;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100);
    const c = Offset(50, 50);
    final col = patchColours(art);
    if (earned) {
      final rim = tier == null ? col.thread : tierColour(tier!);
      canvas.drawCircle(c + const Offset(0, 2), 46, Paint()..color = Colors.black.withValues(alpha: 0.35));
      canvas.drawCircle(c, 46, Paint()..color = rim);
      // A little sheen on the thread.
      canvas.drawCircle(
          c,
          46,
          Paint()
            ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)], center: const Alignment(-0.4, -0.6))
                .createShader(Rect.fromCircle(center: c, radius: 46)));
      canvas.drawCircle(
          c,
          40,
          Paint()
            ..shader = RadialGradient(colors: [col.ground, const Color(0xFF05070E)], center: const Alignment(-0.2, -0.3), radius: 0.95)
                .createShader(Rect.fromCircle(center: c, radius: 40)));
      _dashedArc(canvas, c, 43, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _ink.withValues(alpha: 0.55), sweep: 2 * math.pi * stitch.clamp(0, 1));
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: 39)));
      _emblem(canvas, art);
      canvas.restore();
      if (progress case final p? when p > 0 && p < 1) _ring(canvas, c, p);
    } else {
      canvas.drawCircle(c, 40, Paint()..color = Colors.white.withValues(alpha: 0.03));
      _dashedArc(canvas, c, 40, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.2));
      if (secret) {
        final tp = TextPainter(
          text: TextSpan(text: '?', style: display(40, weight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.35))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      } else {
        // The picture, faint and grey: you can see what you're hunting.
        canvas.saveLayer(Rect.fromCircle(center: c, radius: 40),
            Paint()..colorFilter = const ColorFilter.matrix([0.3, 0.5, 0.1, 0, 0, 0.3, 0.5, 0.1, 0, 0, 0.3, 0.5, 0.1, 0, 0, 0, 0, 0, 0.26, 0]));
        _emblem(canvas, art);
        canvas.restore();
      }
      if (progress case final p? when p > 0) _ring(canvas, c, p);
    }
    canvas.restore();
  }

  void _ring(Canvas canvas, Offset c, double p) {
    final r = Rect.fromCircle(center: c, radius: 48);
    canvas.drawArc(r, 0, 2 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.08));
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * p.clamp(0, 1), false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = fireflyGlow);
  }

  static void _dashedArc(Canvas canvas, Offset c, double r, Paint p, {double sweep = 2 * math.pi}) {
    const dash = 0.13, gap = 0.1;
    for (var a = 0.0; a < sweep; a += dash + gap) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2 + a, math.min(dash, sweep - a), false, p);
    }
  }

  static Paint _fill(Color c) => Paint()..color = c;
  static Paint _line(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static void _star(Canvas canvas, Offset at, double r, Color c) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rr = i.isEven ? r : r * 0.45;
      final o = at + Offset(math.cos(a) * rr, math.sin(a) * rr);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(p..close(), _fill(c));
  }

  static void _moon(Canvas canvas, Offset at, double r, double lit, {Color colour = _white}) {
    // lit: 0 new … 1 full; the dark part is a shifted disc.
    canvas.drawCircle(at, r, _fill(colour.withValues(alpha: 0.18)));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: at, radius: r)));
    canvas.drawCircle(at, r, _fill(colour));
    if (lit < 1) canvas.drawCircle(at - Offset(r * 2 * lit, 0), r * (lit < 0.5 ? 1 : 1.0), _fill(const Color(0xFF0D1324)));
    canvas.restore();
  }

  static void _stationShape(Canvas canvas, Offset at, double s, {Color panel = LookUpColors.blue}) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(s);
    canvas.drawRect(const Rect.fromLTWH(-12, -2, 24, 4), _fill(const Color(0xFFE8ECF4)));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-6, -6, 12, 12), const Radius.circular(2)), _fill(const Color(0xFFE8ECF4)));
    for (final x in const [-32.0, 10.0]) {
      canvas.drawRect(Rect.fromLTWH(x, -12, 22, 8), _fill(panel));
      canvas.drawRect(Rect.fromLTWH(x, 4, 22, 8), _fill(panel));
    }
    canvas.restore();
  }

  static void _emblem(Canvas canvas, BadgeArt a) {
    switch (a) {
      case BadgeArt.pip:
        canvas.drawCircle(const Offset(50, 52), 30, _fill(fireflyGlow.withValues(alpha: 0.18)));
        canvas.drawCircle(const Offset(50, 52), 20, _fill(fireflyGlow));
        for (final x in const [43.0, 57.0]) {
          canvas.drawOval(Rect.fromCenter(center: Offset(x, 49), width: 5.2, height: 7.6), _fill(_night));
        }
      case BadgeArt.firstLight:
        canvas.drawCircle(const Offset(50, 50), 16, _line(_white, 4));
        canvas.drawCircle(const Offset(50, 50), 6, _fill(fireflyGlow));
        for (var i = 0; i < 6; i++) {
          final t = i * math.pi / 3;
          canvas.drawLine(Offset(50 + math.cos(t) * 22, 50 + math.sin(t) * 22), Offset(50 + math.cos(t) * 30, 50 + math.sin(t) * 30), _line(_gold, 3));
        }
      case BadgeArt.station:
        _stationShape(canvas, const Offset(50, 50), 1);
      case BadgeArt.regular:
        _star(canvas, const Offset(30, 56), 9, _white);
        _star(canvas, const Offset(50, 42), 12, _gold);
        _star(canvas, const Offset(70, 56), 9, _white);
      case BadgeArt.planets:
        canvas.drawCircle(const Offset(50, 50), 16, _fill(_gold));
        canvas.save();
        canvas.translate(50, 50);
        canvas.rotate(-0.32);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 62, height: 16), _line(const Color(0xFFE8D3A0), 3));
        canvas.restore();
        canvas.drawCircle(const Offset(24, 30), 3.5, _fill(const Color(0xFFE0784F)));
        canvas.drawCircle(const Offset(76, 72), 2.8, _fill(_white));
      case BadgeArt.moonPhases:
        for (final (i, lit) in const [0.25, 0.5, 0.75, 1.0].indexed) {
          _moon(canvas, Offset(23 + i * 18.0, 50), 7.5, lit);
        }
      case BadgeArt.overhead:
        canvas.drawLine(const Offset(50, 78), const Offset(50, 32), _line(_white, 4));
        canvas.drawPath(Path()
          ..moveTo(38, 44)
          ..lineTo(50, 30)
          ..lineTo(62, 44), _line(_white, 4));
        canvas.drawCircle(const Offset(50, 20), 5, _fill(fireflyGlow));
      case BadgeArt.venus:
        final p = Path()
          ..moveTo(50, 20)
          ..lineTo(54, 46)
          ..lineTo(80, 50)
          ..lineTo(54, 54)
          ..lineTo(50, 80)
          ..lineTo(46, 54)
          ..lineTo(20, 50)
          ..lineTo(46, 46)
          ..close();
        canvas.drawPath(p, _fill(const Color(0xFFFFF8E0)));
        canvas.drawCircle(const Offset(50, 50), 7, _fill(Colors.white));
      case BadgeArt.train:
        for (var i = 0; i < 9; i++) {
          canvas.drawCircle(Offset(20 + i * 7.5, 72 - i * 5.5), 2.7, _fill(_white.withValues(alpha: 1 - i * 0.07)));
        }
      case BadgeArt.aurora:
        canvas.drawPath(
            Path()
              ..moveTo(12, 70)
              ..cubicTo(30, 40, 44, 70, 58, 44)
              ..cubicTo(68, 30, 80, 52, 88, 36),
            _line(LookUpColors.good.withValues(alpha: 0.9), 7));
        canvas.drawPath(
            Path()
              ..moveTo(12, 80)
              ..cubicTo(32, 58, 46, 80, 60, 58)
              ..cubicTo(70, 46, 80, 64, 88, 50),
            _line(LookUpColors.rose.withValues(alpha: 0.8), 5));
      case BadgeArt.meteor:
        for (final (from, to, col, w) in const [
          (Offset(20, 24), Offset(54, 58), _white, 3.0),
          (Offset(44, 18), Offset(70, 44), LookUpColors.cyan, 2.5),
          (Offset(16, 50), Offset(36, 70), _gold, 2.0),
        ]) {
          canvas.drawLine(from, to, _line(col.withValues(alpha: 0.55), w));
          canvas.drawCircle(to, w + 1, _fill(col));
        }
      case BadgeArt.bloodMoon:
        canvas.drawCircle(const Offset(50, 50), 24, _fill(const Color(0xFFB8432F)));
        for (final (x, y, r) in const [(42.0, 44.0, 5.0), (58.0, 58.0, 4.0), (56.0, 40.0, 2.6)]) {
          canvas.drawCircle(Offset(x, y), r, _fill(const Color(0xFF8E2F22)));
        }
      case BadgeArt.eclipse:
        canvas.drawCircle(const Offset(50, 50), 28, _fill(_gold.withValues(alpha: 0.35)));
        canvas.drawCircle(const Offset(50, 50), 22, _fill(const Color(0xFFFFF3C9)));
        canvas.drawCircle(const Offset(50, 50), 21, _fill(_ink));
      case BadgeArt.rocket:
        canvas.drawPath(
            Path()
              ..moveTo(50, 16)
              ..cubicTo(60, 26, 62, 44, 60, 62)
              ..lineTo(40, 62)
              ..cubicTo(38, 44, 40, 26, 50, 16)
              ..close(),
            _fill(const Color(0xFFE8ECF4)));
        canvas.drawCircle(const Offset(50, 38), 5, _fill(LookUpColors.blue));
        canvas.drawPath(
            Path()
              ..moveTo(40, 50)
              ..lineTo(30, 66)
              ..lineTo(40, 63)
              ..close()
              ..moveTo(60, 50)
              ..lineTo(70, 66)
              ..lineTo(60, 63)
              ..close(),
            _fill(LookUpColors.red));
        canvas.drawPath(
            Path()
              ..moveTo(44, 63)
              ..quadraticBezierTo(50, 86, 56, 63)
              ..close(),
            _fill(LookUpColors.orange));
      case BadgeArt.bothStations:
        canvas.drawLine(const Offset(16, 74), const Offset(84, 30), _line(LookUpColors.blue.withValues(alpha: 0.5), 2));
        canvas.drawLine(const Offset(16, 30), const Offset(84, 74), _line(LookUpColors.red.withValues(alpha: 0.5), 2));
        _stationShape(canvas, const Offset(36, 61), 0.5);
        _stationShape(canvas, const Offset(66, 62), 0.5, panel: LookUpColors.red);
      case BadgeArt.owl:
        canvas.drawPath(
            Path.combine(PathOperation.difference, Path()..addOval(Rect.fromCircle(center: const Offset(46, 50), radius: 24)),
                Path()..addOval(Rect.fromCircle(center: const Offset(58, 42), radius: 20))),
            _fill(_gold));
        _star(canvas, const Offset(72, 30), 4, _white);
        _star(canvas, const Offset(78, 54), 3, _white);
      case BadgeArt.transit:
        canvas.drawCircle(const Offset(50, 50), 26, _fill(LookUpColors.orange.withValues(alpha: 0.95)));
        _stationShape(canvas, const Offset(50, 50), 0.62, panel: _ink);
      case BadgeArt.upPastThree:
        canvas.drawCircle(const Offset(50, 50), 24, _line(_white, 3.5));
        canvas.drawLine(const Offset(50, 50), const Offset(50, 34), _line(_white, 3.5));
        canvas.drawLine(const Offset(50, 50), const Offset(64, 50), _line(LookUpColors.violet, 3.5));
        canvas.drawCircle(const Offset(50, 50), 2.8, _fill(_white));
      case BadgeArt.doubleNight:
        _star(canvas, const Offset(36, 46), 12, _white);
        _star(canvas, const Offset(64, 56), 12, LookUpColors.rose);
        canvas.drawLine(const Offset(36, 46), const Offset(64, 56), _line(_white.withValues(alpha: 0.4), 1.5));
    }
  }

  @override
  bool shouldRepaint(_PatchPainter o) =>
      o.art != art || o.tier != tier || o.earned != earned || o.secret != secret || o.progress != progress || o.stitch != stitch;
}
