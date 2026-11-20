/// Pip off the finder: the same light [paintFirefly] draws in alerts and on
/// the sky, as a widget for every other screen. Mostly Pip is the light, its
/// character in how it moves (pip_motion.dart); in [PipState.wave] it grows
/// a face and hands, waves, and goes back to the dot (pip_figure.dart). Kept out of
/// firefly_mark.dart, which must stay `dart:ui` only for the alert isolate.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import 'firefly_mark.dart';
import 'pip_figure.dart';
import 'pip_motion.dart';

export 'pip_motion.dart' show PipState;

class PipMark extends StatefulWidget {
  const PipMark({
    super.key,
    this.state = PipState.idle,
    this.size = 48,
    this.dim = false,
    this.blinking = false,
    this.flyFrom,
    this.replay = 0,
  });

  /// What Pip is doing. [PipState.hello], [PipState.found] and
  /// [PipState.wave] play once each time Pip changes to them, then Pip rests.
  final PipState state;

  /// The square Pip hovers in; Pip itself is drawn at a scale of size / 48.
  final double size;

  /// Can't see: as when you said no to location, or there's no sensor.
  /// Smaller and dimmer, and it looks one way, then the other.
  final bool dim;

  /// Blinking quickly, as it does before a tap.
  final bool blinking;

  /// When set, Pip flies in from this offset (relative to its own place)
  /// trailing sparks, stretched by the speed, and lands with a squash.
  final Offset? flyFrom;

  /// Change it to play [state] again from the start (another wave).
  final int replay;

  @override
  State<PipMark> createState() => _PipMarkState();
}

class _PipMarkState extends State<PipMark> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(
    (e) => setState(() => _t = e.inMicroseconds / 1e6),
  );
  double _t = 0;
  double _flewAt = 0;
  double _stateAt = 0;
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
  void didUpdateWidget(PipMark old) {
    super.didUpdateWidget(old);
    if (widget.flyFrom != old.flyFrom) _flewAt = _t;
    if (widget.state != old.state || widget.replay != old.replay) _stateAt = _t;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: PipMarkPainter(
          state: widget.state,
          seconds: _t,
          sinceState: _t - _stateAt,
          still: _still,
          dim: widget.dim,
          blinking: widget.blinking,
          flyFrom: widget.flyFrom,
          sinceFlew: _still ? null : _t - _flewAt,
        ),
      ),
    ),
  );
}

/// How long a [PipMark.flyFrom] flight takes.
const pipFlight = 0.9;

class PipMarkPainter extends CustomPainter {
  PipMarkPainter({
    required this.state,
    required this.seconds,
    this.sinceState = 1e9,
    this.still = false,
    this.dim = false,
    this.blinking = false,
    this.flyFrom,
    this.sinceFlew,
  });
  final PipState state;
  final double seconds, sinceState;
  final bool still, dim, blinking;
  final Offset? flyFrom;
  final double? sinceFlew;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    final home = size.center(Offset.zero);
    var pose = pipPose(state, seconds, since: sinceState, dim: dim, blinking: blinking, still: still);
    var at = home + pose.offset * scale;
    final from = flyFrom;
    final f = sinceFlew;
    if (from != null && f != null) {
      pose = pipFlightPose(pose, from, f, pipFlight);
      if (f < pipFlight) {
        final k = Curves.easeInOutCubic.transform(f / pipFlight);
        final start = home + from;
        at = Offset.lerp(start, at, k)!;
        paintSparkTrail(canvas, fireflyCurl(at, start), scale: scale, strength: 1 - k);
      }
    }
    // The lock ring and burst when it's found something.
    if (state == PipState.found && !dim) {
      paintFireflyLanding(canvas, home, still ? 1 : sinceState, scale: scale * 0.9);
    }
    final s = scale * pose.size;
    final figure = state == PipState.wave ? pipFigure(sinceState, still: still) : const PipFigure();
    void draw(Canvas c, double blink) => figure.dot
        ? paintFirefly(c, at, blink: blink, scale: s, stretch: pose.stretch, squash: pose.squash, angle: pose.angle)
        : paintPipFigure(c, at, figure, blink: blink, scale: s);
    if (dim || pose.opacity < 1) {
      final a = (dim ? 0.35 : 1) * pose.opacity;
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
      draw(canvas, pose.blink);
      canvas.restore();
    } else {
      draw(canvas, pose.blink);
    }
  }

  @override
  bool shouldRepaint(PipMarkPainter o) => true;
}
