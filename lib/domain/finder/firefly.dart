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

/// How long the ghost run takes to fly the whole route.
const ghostRunLength = Duration(milliseconds: 3600);

/// How far along the route the ghost is [since] its run began (0 at rise,
/// 1 at set), eased in and out; null before it starts and once it's done.
double? ghostProgress(Duration since, {Duration length = ghostRunLength}) {
  if (since.isNegative || since >= length) return null;
  final x = since.inMicroseconds / length.inMicroseconds;
  return x < 0.5 ? 2 * x * x : 1 - math.pow(-2 * x + 2, 2).toDouble() / 2;
}

/// The point [f] of the way along [route] (0 at the first point, 1 at the
/// last), interpolated the short way round in azimuth.
SkyDir alongRoute(List<SkyDir> route, double f) {
  assert(route.isNotEmpty);
  if (route.length == 1) return route.first;
  final x = f.clamp(0.0, 1.0) * (route.length - 1);
  final i = math.min(x.floor(), route.length - 2);
  final u = x - i;
  final a = route[i], b = route[i + 1];
  final az = a.azimuthDeg + azimuthDelta(a.azimuthDeg, b.azimuthDeg) * u;
  return SkyDir(((az % 360) + 360) % 360, a.elevationDeg + (b.elevationDeg - a.elevationDeg) * u);
}

/// What the firefly is showing you.
enum FireflyStep {
  /// Flying the route once before the pass.
  ghostRun,

  /// A bright planet or star the pass goes near: find that first.
  findLandmark,

  /// Then the spot by it where the pass will go.
  meetingPoint,

  /// The thing itself: where it will rise, or where it is now.
  target,
}

/// Before the pass: the ghost run, then the landmark and the spot by it,
/// then where it rises. Once it's up, always the thing itself.
FireflyStep fireflyStep({
  required bool beforePass,
  required bool ghostRunning,
  required bool hasLandmark,
  required bool landmarkFound,
  bool skipped = false,
}) {
  if (!beforePass) return FireflyStep.target;
  if (ghostRunning) return FireflyStep.ghostRun;
  if (hasLandmark && !skipped) return landmarkFound ? FireflyStep.meetingPoint : FireflyStep.findLandmark;
  return FireflyStep.target;
}
