/// The finder's guide: a small light that flies to the target. When the
/// target is on screen it sits on it; otherwise it waits at the edge on the
/// side to turn. It moves on a spring, so compass jitter becomes a gentle
/// drift instead of a jumping dot, and it blinks in time with the phone's
/// ticks, faster as you close in.
library;

import 'dart:math' as math;

import 'pointing.dart';

/// Where the firefly heads, in pixels from the centre of a [width]×[height]
/// view (x right, y down). [target] is where the thing is on that view, or
/// null when it's behind you; [toward] is which way to turn then (any
/// length). [waiting] is true when it's parked at the edge.
({double x, double y, bool waiting}) fireflyGoal({
  required double width,
  required double height,
  required ({double x, double y})? target,
  required ({double x, double y}) toward,
  double margin = 30,
}) {
  final rx = width / 2 - margin, ry = height / 2 - margin;
  if (target != null && target.x.abs() <= rx && target.y.abs() <= ry) {
    return (x: target.x, y: target.y, waiting: false);
  }
  var dx = target?.x ?? toward.x, dy = target?.y ?? toward.y;
  if (dx == 0 && dy == 0) dx = 1;
  final s = math.min(rx / math.max(dx.abs(), 1e-9), ry / math.max(dy.abs(), 1e-9));
  return (x: dx * s, y: dy * s, waiting: true);
}

/// Which way to turn on screen for [g]: right for "turn right", up for
/// "tilt up".
({double x, double y}) towardOnScreen(Guidance g) => (x: g.dAzimuth, y: -g.dElevation);

/// A critically damped spring: it gets there quickly and never overshoots.
class FireflyMotion {
  FireflyMotion({this.x = 0, this.y = 0, this.stiffness = 7});
  double x, y;
  double vx = 0, vy = 0;

  /// Higher is snappier; 7 settles in about half a second.
  final double stiffness;

  void step(({double x, double y}) goal, double dtSeconds) {
    final dt = dtSeconds.clamp(0.0, 0.05);
    final w = stiffness;
    // x'' = -w²(x − goal) − 2w·x'
    final ax = -w * w * (x - goal.x) - 2 * w * vx;
    final ay = -w * w * (y - goal.y) - 2 * w * vy;
    vx += ax * dt;
    vy += ay * dt;
    x += vx * dt;
    y += vy * dt;
  }

  void jumpTo(({double x, double y}) p) {
    x = p.x;
    y = p.y;
    vx = vy = 0;
  }
}

/// How often the firefly blinks (and the phone ticks) at [distanceDeg]
/// from the target: slow and lazy far away, quick when close, and a steady
/// glow (null) once you're on it.
Duration? fireflyBlink(double distanceDeg, {double toleranceDeg = 7}) {
  if (distanceDeg <= toleranceDeg) return null;
  return pulseInterval(distanceDeg, toleranceDeg: toleranceDeg) ?? const Duration(milliseconds: 1300);
}
