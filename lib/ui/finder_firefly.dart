/// The firefly over the finder: flies to the target on a spring, waits at
/// the edge on the side to turn, blinks (and ticks the phone) faster as you
/// close in, and glows steady when you're on it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../domain/finder/firefly.dart';
import 'theme.dart';

const fireflyWarm = Color(0xFFFFB347);
const _core = Color(0xFFFFF3D6);

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
              left: at.dx - 90,
              width: 180,
              top: at.dy + 24,
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: _core, fontSize: 13, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
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
    canvas.drawCircle(
        p,
        30,
        Paint()
          ..color = fireflyWarm.withValues(alpha: 0.18 + 0.32 * blink)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
    canvas.drawCircle(
        p,
        10,
        Paint()
          ..color = fireflyWarm.withValues(alpha: 0.5 + 0.4 * blink)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(p, 4.5, Paint()..color = _core.withValues(alpha: 0.75 + 0.25 * blink));
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

/// "Lower your phone": once you've held the target, the screen goes dark
/// red to keep your night vision, and the phone buzzes when it appears.
class LookUpNow extends StatelessWidget {
  const LookUpNow({super.key, required this.headline, required this.detail, required this.onBack});
  final String headline;
  final String detail;
  final VoidCallback onBack;

  static const red = Color(0xFFFF5A48);

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF0E0304),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              const Spacer(flex: 2),
              const _Ember(),
              const SizedBox(height: 28),
              Text('Lower your phone.',
                  textAlign: TextAlign.center, style: display(30, weight: FontWeight.w700, color: red)),
              const SizedBox(height: 10),
              Text(headline,
                  textAlign: TextAlign.center, style: TextStyle(color: red.withValues(alpha: 0.8), fontSize: 17, height: 1.4)),
              const SizedBox(height: 18),
              Text(detail,
                  textAlign: TextAlign.center, style: TextStyle(color: red.withValues(alpha: 0.55), fontSize: 14)),
              const Spacer(flex: 3),
              TextButton(
                onPressed: onBack,
                style: TextButton.styleFrom(foregroundColor: red.withValues(alpha: 0.75)),
                child: const Text('Back to the finder'),
              ),
              const SizedBox(height: 12),
            ]),
          ),
        ),
      );
}

/// The firefly, now a dim red ember.
class _Ember extends StatelessWidget {
  const _Ember();
  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [
            const Color(0xFFFF8A70).withValues(alpha: 0.9),
            LookUpNow.red.withValues(alpha: 0.35),
            LookUpNow.red.withValues(alpha: 0),
          ], stops: const [0, 0.35, 1]),
        ),
      );
}
