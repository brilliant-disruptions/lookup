import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models/sky_event.dart';
import 'kit/kit.dart';
import 'theme.dart';

/// The first thing anyone sees: the product working, not a list about it.
/// Over a dark horizon the space station glides across, then a Starlink
/// train, then an aurora rises in the north, and each time the tap LookUp
/// sends drops in at the top, worded the way real alerts are. One loop is
/// about 16 seconds. With reduced motion it holds the station mid-pass.
class IntroScene extends StatefulWidget {
  const IntroScene({super.key, this.animate = true});

  /// Off in tests that need a still frame.
  final bool animate;

  static const scenes = <_Scene>[
    _Scene(SkyEventType.iss, 'ISS flyover in 10 min', 'Brighter than any star. Face west-southwest; it climbs high in the sky.', (
      'WSW',
      'E',
    )),
    _Scene(SkyEventType.starlinkTrain, 'Starlink train in 10 min', 'A line of lights, one after another. Face southwest.', ('SW', 'NE')),
    _Scene(SkyEventType.auroraNow, 'Aurora now', 'Find a dark spot and look north. Clear skies.', (null, 'N')),
  ];

  @override
  State<IntroScene> createState() => _IntroSceneState();
}

class _Scene {
  const _Scene(this.type, this.title, this.body, this.labels);
  final SkyEventType type;
  final String title;
  final String body;

  /// Compass words on the horizon: (left, right), or (null, centre).
  final (String?, String) labels;
}

class _IntroSceneState extends State<IntroScene> with SingleTickerProviderStateMixin {
  static const _perScene = Duration(milliseconds: 5500);
  late final AnimationController _c = AnimationController(vsync: this, duration: _perScene * IntroScene.scenes.length);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !widget.animate || MediaQuery.of(context).disableAnimations;
    if (still) {
      _c.stop();
      _c.value = 0.55 / IntroScene.scenes.length; // the station near its best
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) {
      final n = IntroScene.scenes.length;
      final v = _c.value * n;
      final i = v.floor().clamp(0, n - 1);
      final p = v - i;
      final scene = IntroScene.scenes[i];
      final shown = _smooth(0.08, 0.2, p) * (1 - _smooth(0.88, 0.97, p));
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _ScenePainter(scene: scene, p: p),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 6,
            child: Opacity(
              opacity: shown,
              child: Transform.translate(
                offset: Offset(0, -26 * (1 - shown)),
                child: _Banner(scene: scene),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var k = 0; k < n; k++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: k == i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: k == i ? eventStyle(scene.type).color : LookUpColors.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// A lock-screen notification, as the phone draws it.
class _Banner extends StatelessWidget {
  const _Banner({required this.scene});
  final _Scene scene;

  @override
  Widget build(BuildContext context) {
    final tint = eventStyle(scene.type).color;
    return Semantics(
      label: 'Example alert: ${scene.title}. ${scene.body}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xD9262B38),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: LookUpColors.line),
          boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.30), blurRadius: 34, spreadRadius: -8)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [LookUpColors.night, LookUpColors.black],
                ),
              ),
              alignment: Alignment.center,
              child: EventGlyph.forType(scene.type, size: 28),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'LOOKUP',
                          style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: LookUpColors.grey),
                        ),
                      ),
                      Text('now', style: TextStyle(fontSize: 11.5, color: LookUpColors.grey)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    scene.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: LookUpColors.white),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    scene.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.3, color: LookUpColors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({required this.scene, required this.p});
  final _Scene scene;
  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final horizon = h * 0.80;
    // Keep the sky's action below the notification.
    final skyTop = math.min(h * 0.42, 132.0);

    switch (scene.type) {
      case SkyEventType.auroraNow:
        _aurora(canvas, w, horizon, skyTop);
      case SkyEventType.starlinkTrain:
        _train(canvas, w, horizon, skyTop);
      default:
        _station(canvas, w, horizon, skyTop);
    }
    _ground(canvas, size, horizon);
  }

  /// Where along a pass, 0 at rise to 1 at set.
  Offset _arc(double s, double w, double horizon, double peakY, {double x0 = 0.06, double x1 = 0.94}) {
    final x = w * (x0 + (x1 - x0) * s);
    final y = horizon - math.sin(math.pi * s) * (horizon - peakY);
    return Offset(x, y);
  }

  void _station(Canvas canvas, double w, double horizon, double skyTop) {
    final s = ((p - 0.1) / 0.78).clamp(0.0, 1.0);
    final fade = _smooth(0.0, 0.06, s) * (1 - _smooth(0.94, 1.0, s));
    // The route ahead, faint and dashed.
    final ahead = Paint()
      ..color = LookUpColors.blue.withValues(alpha: 0.22)
      ..strokeWidth = 1.4;
    for (var k = 0.0; k < 1.0; k += 0.03) {
      if (k + 0.015 < s) continue;
      canvas.drawLine(_arc(k, w, horizon, skyTop), _arc(k + 0.015, w, horizon, skyTop), ahead);
    }
    if (s <= 0 || fade <= 0) return;
    // The trail it leaves.
    const steps = 22;
    for (var k = 0; k < steps; k++) {
      final a = s - k * 0.009;
      if (a < 0) break;
      final b = a - 0.009;
      final alpha = (1 - k / steps) * 0.55 * fade;
      canvas.drawLine(
        _arc(a, w, horizon, skyTop),
        _arc(math.max(0, b), w, horizon, skyTop),
        Paint()
          ..color = LookUpColors.blue.withValues(alpha: alpha)
          ..strokeWidth = 3.2 * (1 - k / steps) + 0.4
          ..strokeCap = StrokeCap.round,
      );
    }
    final at = _arc(s, w, horizon, skyTop);
    canvas.drawCircle(
      at,
      22,
      Paint()
        ..shader = RadialGradient(
          colors: [
            LookUpColors.blue.withValues(alpha: 0.55 * fade),
            LookUpColors.blue.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: at, radius: 22)),
    );
    canvas.drawCircle(at, 4.2, Paint()..color = Colors.white.withValues(alpha: fade));
  }

  void _train(Canvas canvas, double w, double horizon, double skyTop) {
    final peak = skyTop + (horizon - skyTop) * 0.35; // lower and flatter
    final head = ((p - 0.1) / 0.62).clamp(0.0, 1.45);
    const cars = 14;
    for (var k = 0; k < cars; k++) {
      final s = head - k * 0.034;
      if (s < 0 || s > 1) continue;
      final fade = _smooth(0.0, 0.06, s) * (1 - _smooth(0.92, 1.0, s));
      final at = _arc(s, w, horizon, peak, x0: 0.04, x1: 0.96);
      canvas.drawCircle(
        at,
        9,
        Paint()
          ..shader = RadialGradient(
            colors: [
              LookUpColors.violet.withValues(alpha: 0.4 * fade),
              LookUpColors.violet.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: 9)),
      );
      canvas.drawCircle(at, 2.3, Paint()..color = Colors.white.withValues(alpha: 0.95 * fade));
    }
  }

  void _aurora(Canvas canvas, double w, double horizon, double skyTop) {
    final glow = _smooth(0.1, 0.4, p) * (1 - _smooth(0.86, 0.98, p));
    if (glow <= 0) return;
    final t = p * math.pi * 2;
    for (final (color, height, phase, alpha) in [
      (LookUpColors.good, 0.85, 0.0, 0.36),
      (LookUpColors.good, 0.6, 1.7, 0.30),
      (LookUpColors.violet, 1.0, 3.1, 0.18),
    ]) {
      final path = Path()..moveTo(w * 0.04, horizon);
      for (var x = 0.04; x <= 0.96 + 1e-9; x += 0.01) {
        final edge = math.sin(math.pi * (x - 0.04) / 0.92); // tallest in the north (centre)
        final ripple = 0.75 + 0.25 * math.sin(x * 17 + t * 1.3 + phase) * math.sin(x * 5 - t * 0.7 + phase);
        final y = horizon - (horizon - skyTop) * height * edge * ripple * (0.35 + 0.65 * glow);
        path.lineTo(w * x, y);
      }
      path
        ..lineTo(w * 0.96, horizon)
        ..close();
      final bounds = Rect.fromLTRB(0, skyTop, w, horizon);
      canvas.drawPath(
        path,
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              color.withValues(alpha: alpha * glow),
              color.withValues(alpha: 0),
            ],
          ).createShader(bounds),
      );
    }
      // Rays: the curtain's vertical folds.
    final rays = Paint()
      ..strokeWidth = 2.6
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    for (var x = 0.07; x <= 0.93; x += 0.014) {
      final edge = math.sin(math.pi * (x - 0.04) / 0.92);
      final flicker = 0.5 + 0.5 * math.sin(x * 41 + t * 2.3) * math.sin(x * 13 - t * 1.1);
      final top = horizon - (horizon - skyTop) * edge * (0.45 + 0.6 * flicker) * (0.35 + 0.65 * glow);
      rays.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [LookUpColors.good.withValues(alpha: 0.6 * glow * flicker), LookUpColors.good.withValues(alpha: 0)],
      ).createShader(Rect.fromLTRB(0, top, w, horizon));
      canvas.drawLine(Offset(w * x, horizon), Offset(w * x, top), rays);
    }
  }

  void _ground(Canvas canvas, Size size, double horizon) {
    final w = size.width, h = size.height;
    // Runs past the page padding to the screen's edges, and fades out below
    // instead of ending in a line.
    const bleed = 40.0;
    final ridge = Path()
      ..moveTo(-bleed, horizon + 4)
      ..quadraticBezierTo(w * 0.18, horizon - 10, w * 0.36, horizon + 2)
      ..quadraticBezierTo(w * 0.55, horizon + 10, w * 0.72, horizon - 4)
      ..quadraticBezierTo(w * 0.88, horizon - 12, w + bleed, horizon + 2);
    final hill = Path.from(ridge)
      ..lineTo(w + bleed, h)
      ..lineTo(-bleed, h)
      ..close();
    canvas.drawPath(
      hill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1020), Color(0x0004060B)],
        ).createShader(Rect.fromLTRB(0, horizon - 12, w, h)),
    );
    canvas.drawPath(
      ridge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          colors: [
            LookUpColors.blue.withValues(alpha: 0),
            LookUpColors.blue.withValues(alpha: 0.22),
            LookUpColors.blue.withValues(alpha: 0.22),
            LookUpColors.blue.withValues(alpha: 0),
          ],
          stops: const [0, 0.2, 0.8, 1],
        ).createShader(Rect.fromLTRB(-bleed, 0, w + bleed, h)),
    );
    void label(String text, double x) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: LookUpColors.grey,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, horizon + 14));
    }

    final (left, right) = scene.labels;
    if (left == null) {
      label(right, w / 2);
    } else {
      label(left, w * 0.09);
      label(right, w * 0.91);
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.p != p || old.scene != scene;
}
