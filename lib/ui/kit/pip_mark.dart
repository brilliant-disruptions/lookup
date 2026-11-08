/// Pip off the finder: the same firefly [paintFirefly] draws in alerts and on
/// the sky, as a widget for every other screen. Kept out of
/// firefly_mark.dart, which must stay `dart:ui` only for the alert isolate.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'firefly_mark.dart';

/// What Pip is doing.
/// - [idle]: hovering, blinking slowly.
/// - [searching]: circling, waiting on something.
/// - [resting]: landed on something, a gentle hover and a steady glow.
enum PipState { idle, searching, resting }

class PipMark extends StatefulWidget {
  const PipMark({
    super.key,
    this.state = PipState.idle,
    this.size = 48,
    this.dim = false,
    this.blinking = false,
    this.flyFrom,
  });

  final PipState state;

  /// The square Pip hovers in; Pip itself is drawn at a scale of size / 48.
  final double size;

  /// Dimmed, as when you said no to location.
  final bool dim;

  /// Blinking quickly, as it does before a tap.
  final bool blinking;

  /// When set, Pip flies in from this offset (relative to its own place)
  /// trailing sparks, then settles.
  final Offset? flyFrom;

  @override
  State<PipMark> createState() => _PipMarkState();
}

class _PipMarkState extends State<PipMark> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(
    (e) => setState(() => _t = e.inMicroseconds / 1e6),
  );
  double _t = 0;
  double _flewAt = 0;
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
    this.still = false,
    this.dim = false,
    this.blinking = false,
    this.flyFrom,
    this.sinceFlew,
  });
  final PipState state;
  final double seconds;
  final bool still, dim, blinking;
  final Offset? flyFrom;
  final double? sinceFlew;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    final home = size.center(Offset.zero);
    var at = home;
    if (!still) {
      switch (state) {
        case PipState.idle:
          at += fireflyHover(seconds) * scale;
        case PipState.resting:
          at += fireflyHover(seconds, landed: true) * scale;
        case PipState.searching:
          final a = seconds * 2.4;
          at += Offset(math.cos(a), math.sin(a)) * size.shortestSide * 0.3;
      }
    }
    final from = flyFrom;
    final f = sinceFlew;
    if (from != null && f != null && f < pipFlight) {
      final k = Curves.easeInOutCubic.transform(f / pipFlight);
      final start = home + from;
      at = Offset.lerp(start, at, k)!;
      paintSparkTrail(
        canvas,
        fireflyCurl(at, start),
        scale: scale,
        strength: 1 - k,
      );
    }
    double blink;
    if (still) {
      blink = 1;
    } else if (blinking) {
      blink = 0.55 + 0.45 * math.cos(seconds * 2 * math.pi * 2.5);
    } else if (state == PipState.resting) {
      blink = 0.85;
    } else {
      blink = 0.55 + 0.45 * math.cos(seconds * 2 * math.pi / 1.6);
    }
    if (dim) {
      canvas.saveLayer(null, Paint()..color = const Color(0x59000000));
      paintFirefly(canvas, at, blink: blink * 0.6, scale: scale);
      canvas.restore();
    } else {
      paintFirefly(canvas, at, blink: blink, scale: scale);
    }
  }

  @override
  bool shouldRepaint(PipMarkPainter o) => true;
}
