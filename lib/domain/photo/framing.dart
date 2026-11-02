/// Where to point a propped-up phone, and with which lens, so a pass's
/// streak fits the picture. Pure Dart.
///
/// The phone is assumed level (horizon straight) and still for the whole
/// pass. A pass seen from the ground can cross most of the sky, so this
/// picks the stretch worth having: high and long beats low and short, and
/// a strip of horizon at the bottom gives the picture a sense of place.
library;

import 'dart:math' as math;

import '../finder/pointing.dart';
import 'camera.dart';

typedef PathPoint = ({DateTime t, SkyDir d});

/// A gnomonic (pinhole) projection for a level camera pointing at
/// [center]: x to the right, y up, in tangent units (tan of the angle off
/// the axis). Null when [d] is behind or nearly beside the camera.
({double x, double y})? frameCoords(SkyDir center, SkyDir d) {
  const k = math.pi / 180;
  final az0 = center.azimuthDeg * k, el0 = center.elevationDeg * k;
  final az = d.azimuthDeg * k, el = d.elevationDeg * k;
  final w = (math.cos(el) * math.sin(az), math.cos(el) * math.cos(az), math.sin(el));
  final f = (math.cos(el0) * math.sin(az0), math.cos(el0) * math.cos(az0), math.sin(el0));
  final r = (math.cos(az0), -math.sin(az0), 0.0);
  final u = (-math.sin(el0) * math.sin(az0), -math.sin(el0) * math.cos(az0), math.cos(el0));
  double dot((double, double, double) a, (double, double, double) b) => a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
  final dz = dot(w, f);
  if (dz < 0.1) return null;
  return (x: dot(w, r) / dz, y: dot(w, u) / dz);
}

/// The phone's rotation (row-major device→world, world x east, y north, z
/// up; as pointing.dart reads it) for a level camera aimed at [center],
/// held upright (0) or on its side top-left (1) or top-right (3).
List<double> levelPose(SkyDir center, {int quarterTurns = 0}) {
  const k = math.pi / 180;
  final az0 = center.azimuthDeg * k, el0 = center.elevationDeg * k;
  final f = [math.cos(el0) * math.sin(az0), math.cos(el0) * math.cos(az0), math.sin(el0)];
  final r = [math.cos(az0), -math.sin(az0), 0.0];
  final u = [-math.sin(el0) * math.sin(az0), -math.sin(el0) * math.cos(az0), math.cos(el0)];
  final z = [-f[0], -f[1], -f[2]];
  final (x, y) = switch (quarterTurns % 4) {
    1 => (u, [-r[0], -r[1], -r[2]]),
    3 => ([-u[0], -u[1], -u[2]], r),
    _ => (r, u),
  };
  return [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]];
}

class Framing {
  const Framing({
    required this.lens,
    required this.center,
    required this.landscape,
    required this.coverage,
    required this.enters,
    required this.leaves,
    required this.horizonInFrame,
  });

  final CameraLens lens;

  /// Where the middle of the picture points.
  final SkyDir center;

  /// Phone on its side (the lens's long side across).
  final bool landscape;

  /// Share of the pass (by time, weighted towards the higher parts) that
  /// lands in the picture, 0–1.
  final double coverage;

  /// First and last moments it's in the picture.
  final DateTime enters, leaves;

  /// A strip of ground along the bottom.
  final bool horizonInFrame;

  double get widthFovDeg => landscape ? lens.longFovDeg : lens.shortFovDeg;
  double get heightFovDeg => landscape ? lens.shortFovDeg : lens.longFovDeg;

  /// Whether [d] lands inside the picture, with [margin] (a fraction of the
  /// half-width) kept clear at the edges.
  bool contains(SkyDir d, {double margin = 0}) {
    final p = frameCoords(center, d);
    if (p == null) return false;
    final hx = math.tan(widthFovDeg / 2 * math.pi / 180) * (1 - margin);
    final hy = math.tan(heightFovDeg / 2 * math.pi / 180) * (1 - margin);
    return p.x.abs() <= hx && p.y.abs() <= hy;
  }

  /// [d] in picture coordinates: 0–1 from the left and from the top.
  ({double x, double y})? toPicture(SkyDir d) {
    final p = frameCoords(center, d);
    if (p == null) return null;
    final hx = math.tan(widthFovDeg / 2 * math.pi / 180);
    final hy = math.tan(heightFovDeg / 2 * math.pi / 180);
    return (x: 0.5 + p.x / hx / 2, y: 0.5 - p.y / hy / 2);
  }

  @override
  String toString() => 'Framing(${lens.kind.label}, $center, ${landscape ? 'landscape' : 'portrait'}, '
      '${(coverage * 100).round()}%)';
}

/// The low parts of a pass are dimmer and behind trees and roofs: count
/// them for less.
double _weight(SkyDir d) => d.elevationDeg < 10 ? 0.4 : (d.elevationDeg < 20 ? 0.8 : 1.0);

/// The best way to frame [path] with one of [lenses]. The main camera
/// gathers the most light, so it's kept unless a wider lens catches
/// clearly more of the pass. Null for an empty path.
Framing? frameFor(List<PathPoint> path, List<CameraLens> lenses, {double margin = 0.06}) {
  if (path.length < 2 || lenses.isEmpty) return null;
  Framing? best;
  Framing? bestMain;
  for (final lens in lenses.where((l) => l.kind != LensKind.tele)) {
    final f = _bestFor(path, lens, margin);
    if (f == null) continue;
    if (lens.kind == LensKind.wide && (bestMain == null || f.coverage > bestMain.coverage)) bestMain = f;
    if (best == null || f.coverage > best.coverage + 1e-9) best = f;
  }
  if (bestMain != null && best != null && bestMain.coverage >= math.min(0.75, best.coverage * 0.85)) return bestMain;
  return best ?? bestMain;
}

Framing? _bestFor(List<PathPoint> path, CameraLens lens, double margin) {
  final total = path.fold<double>(0, (s, p) => s + _weight(p.d));
  // Azimuths worth trying: around the pass, every 4°.
  final azs = <double>{};
  for (final p in path) {
    azs.add((p.d.azimuthDeg / 4).round() * 4.0 % 360);
  }
  Framing? best;
  var bestScore = -1.0;
  for (final landscape in const [true, false]) {
    final w = landscape ? lens.longFovDeg : lens.shortFovDeg;
    final h = landscape ? lens.shortFovDeg : lens.longFovDeg;
    final hx = math.tan(w / 2 * math.pi / 180) * (1 - margin);
    final hy = math.tan(h / 2 * math.pi / 180) * (1 - margin);
    // Keep the horizon in view or just below it: higher than that, a
    // propped phone points mostly at empty sky.
    final maxEl = math.min(80.0, h / 2 + 25);
    for (final az in azs) {
      for (var el = 3.0; el <= maxEl; el += 3) {
        final c = SkyDir(az, el);
        var got = 0.0;
        DateTime? enters, leaves;
        for (final p in path) {
          final q = frameCoords(c, p.d);
          if (q == null || q.x.abs() > hx || q.y.abs() > hy) continue;
          got += _weight(p.d);
          enters ??= p.t;
          leaves = p.t;
        }
        if (enters == null) continue;
        final coverage = got / total;
        // Horizon along the bottom, about a sixth of the way up: a sense of
        // place without a picture of the ground.
        final fullHy = math.tan(h / 2 * math.pi / 180);
        final fromBottom = (fullHy - math.tan(el * math.pi / 180)) / (2 * fullHy);
        final horizon = fromBottom >= 0.04;
        final place = horizon ? (1 - (fromBottom - 0.16).abs() / 0.16).clamp(0.0, 1.0) : 0.0;
        final score = coverage + 0.05 * place - (landscape ? 0 : 0.01);
        if (score > bestScore) {
          bestScore = score;
          best = Framing(
            lens: lens,
            center: c,
            landscape: landscape,
            coverage: coverage,
            enters: enters,
            leaves: leaves!,
            horizonInFrame: horizon,
          );
        }
      }
    }
  }
  return best;
}

/// Fastest apparent speed along [path], degrees per second.
double peakAngularSpeed(List<PathPoint> path) {
  var best = 0.0;
  for (var i = 1; i < path.length; i++) {
    final dt = path[i].t.difference(path[i - 1].t).inMilliseconds / 1000;
    if (dt <= 0) continue;
    best = math.max(best, angularDistanceDeg(path[i - 1].d, path[i].d) / dt);
  }
  return best;
}
