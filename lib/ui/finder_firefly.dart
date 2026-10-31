/// The firefly over the finder: flies to the target on a spring, waits at
/// the edge on the side to turn, blinks (and ticks the phone) faster as you
/// close in, and glows steady when you're on it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../domain/finder/firefly.dart';
import '../domain/finder/pointing.dart';
import '../domain/sky/direction.dart';
import 'kit/firefly_mark.dart';

export 'kit/firefly_mark.dart' show fireflyWarm, fireflyCore;


class FireflyLayer extends StatefulWidget {
  const FireflyLayer({
    super.key,
    required this.target,
    required this.toward,
    required this.distanceDeg,
    required this.onTarget,
    this.label,
  });

  /// Where the target is on this layer, from its centre (x right, y down);
  /// null when it's behind you.
  final ({double x, double y})? target;

  /// Which way to turn when it isn't on screen.
  final ({double x, double y}) toward;
  final double distanceDeg;
  final bool onTarget;

  /// Shown under the firefly once it's on the target ("Comes up here 7:41").
  final String? label;

  @override
  State<FireflyLayer> createState() => _FireflyLayerState();
}

class _FireflyLayerState extends State<FireflyLayer> with SingleTickerProviderStateMixin {
  final _motion = FireflyMotion();
  final _trail = <Offset>[];
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  Duration _clock = Duration.zero;
  double _phase = 0; // 0…1 through the current blink
  Size _size = Size.zero;
  bool _placed = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.of(context).disableAnimations;
    if (_still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  ({double x, double y, bool waiting}) _goal() => fireflyGoal(
        width: _size.width,
        height: _size.height,
        target: widget.target,
        toward: widget.toward,
      );

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _clock = elapsed;
    if (_size.isEmpty) return;
    final g = _goal();
    if (!_placed) {
      _motion.jumpTo((x: g.x, y: g.y));
      _placed = true;
    }
    _motion.step((x: g.x, y: g.y), dt);
    _trail.add(Offset(_motion.x, _motion.y));
    if (_trail.length > 14) _trail.removeAt(0);
    // Blink, and tick the phone at the top of each blink.
    final period = fireflyBlink(widget.distanceDeg);
    if (period == null) {
      _phase = 0;
    } else {
      _phase += dt / (period.inMicroseconds / 1e6);
      if (_phase >= 1) {
        _phase %= 1;
        HapticFeedback.selectionClick();
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        _size = c.biggest;
        if (_still || !_placed) {
          final g = _goal();
          _motion.jumpTo((x: g.x, y: g.y));
        }
        final at = _size.center(Offset(_motion.x, _motion.y));
        final label = widget.onTarget || (widget.target != null && !_goal().waiting) ? widget.label : null;
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FireflyPainter(
                  at: at,
                  trail: [for (final p in _trail) _size.center(p)],
                  blink: fireflyBlink(widget.distanceDeg) == null ? 1 : 0.55 + 0.45 * math.cos(_phase * 2 * math.pi),
                  wobble: _still || widget.onTarget ? Offset.zero : Offset(math.sin(_seconds * 2.3) * 4, math.cos(_seconds * 3.1) * 3),
                  landed: widget.onTarget,
                ),
              ),
            ),
          ),
          if (label != null)
            Positioned(
              // Under the firefly, but kept on screen near the edges.
              left: (at.dx - 90).clamp(8.0, math.max(8.0, _size.width - 188)),
              width: 180,
              top: at.dy + 24,
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: fireflyCore, fontSize: 13, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
            ),
        ]);
      });

  double get _seconds => _clock.inMicroseconds / 1e6;
}

class _FireflyPainter extends CustomPainter {
  _FireflyPainter({required this.at, required this.trail, required this.blink, required this.wobble, required this.landed});
  final Offset at;
  final List<Offset> trail;
  final double blink; // 0…1
  final Offset wobble;
  final bool landed;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < trail.length; i++) {
      final f = (i + 1) / (trail.length + 1);
      canvas.drawCircle(
          trail[i],
          1.5 + f * 3,
          Paint()
            ..color = fireflyWarm.withValues(alpha: 0.06 + f * 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    final p = at + wobble;
    paintFirefly(canvas, p, blink: blink);
    if (landed) {
      canvas.drawCircle(
          p,
          18,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = fireflyWarm.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(_FireflyPainter o) => true;
}

/// The whole route as a small map: the horizon, the arc from where it
/// rises to where it sets, where the ghost (or the pass) is on it, and which
/// way you're facing. Tap it to fly the route again.
class RouteMap extends StatelessWidget {
  const RouteMap({super.key, required this.route, this.at, this.facingAzimuth, this.onReplay});
  final List<SkyDir> route;

  /// How far along the route the firefly or the pass is (0…1).
  final double? at;
  final double? facingAzimuth;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onReplay != null,
        label: 'The route: rises in the ${compassWord(route.first.azimuthDeg)}, '
            'sets in the ${compassWord(route.last.azimuthDeg)}. Tap to see it again.',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onReplay,
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xCC080C1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x1FFFFFFF)),
            ),
            child: CustomPaint(painter: _RoutePainter(route, at, facingAzimuth), size: Size.infinite),
          ),
        ),
      );
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.route, this.at, this.facing);
  final List<SkyDir> route;
  final double? at;
  final double? facing;

  @override
  void paint(Canvas canvas, Size size) {
    // Azimuth unrolled along the way it travels, so the arc never jumps.
    final xs = <double>[0];
    for (var i = 1; i < route.length; i++) {
      xs.add(xs.last + azimuthDelta(route[i - 1].azimuthDeg, route[i].azimuthDeg));
    }
    final lo = xs.reduce(math.min), hi = xs.reduce(math.max);
    final span = math.max(hi - lo, 30.0);
    final mid = (lo + hi) / 2;
    const padX = 30.0, top = 8.0;
    final base = size.height - 18;
    double x(double unrolled) => padX + ((unrolled - mid) / span + 0.5) * (size.width - 2 * padX);
    double y(double el) => base - (el.clamp(0, 90) / 90) * (base - top);

    canvas.drawLine(Offset(12, base), Offset(size.width - 12, base), Paint()..color = const Color(0x4DFFFFFF));
    final arc = Path();
    for (var i = 0; i < route.length; i++) {
      final p = Offset(x(xs[i]), y(route[i].elevationDeg));
      i == 0 ? arc.moveTo(p.dx, p.dy) : arc.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = fireflyWarm.withValues(alpha: 0.55));

    void label(String s, double cx) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFA0A8B8))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, base + 3));
    }

    label(compassAbbrev(route.first.azimuthDeg), x(xs.first));
    label(compassAbbrev(route.last.azimuthDeg), x(xs.last));

    // Which way you're facing, if it's along the route.
    final f = facing;
    if (f != null) {
      final u = azimuthDelta(route.first.azimuthDeg, f);
      if (u >= lo - 15 && u <= hi + 15) {
        final cx = x(u).clamp(8.0, size.width - 8);
        canvas.drawPath(
            Path()
              ..moveTo(cx, base - 2)
              ..lineTo(cx - 5, base + 5)
              ..lineTo(cx + 5, base + 5)
              ..close(),
            Paint()..color = Colors.white);
      }
    }

    final a = at;
    if (a != null) {
      final i = (a.clamp(0.0, 1.0) * (route.length - 1));
      final j = math.min(i.floor(), route.length - 2);
      final u = i - j;
      final p = Offset(
        x(xs[j] + (xs[j + 1] - xs[j]) * u),
        y(route[j].elevationDeg + (route[j + 1].elevationDeg - route[j].elevationDeg) * u),
      );
      canvas.drawCircle(
          p,
          9,
          Paint()
            ..color = fireflyWarm.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      canvas.drawCircle(p, 3, Paint()..color = fireflyCore);
    }
  }

  @override
  bool shouldRepaint(_RoutePainter o) => o.at != at || o.facing != facing || o.route != route;
}
