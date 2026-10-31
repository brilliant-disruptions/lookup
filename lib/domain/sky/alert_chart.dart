/// The little "where to look" picture on a pass alert: the horizon as you'd
/// see it facing the pass, with its path drawn across. Only the geometry
/// lives here (pure, tested); `services/alert_art.dart` paints it.
///
/// Built from the event's rise, peak and set directions and its highest
/// point, so it needs no orbit data and works from any stored event.
library;

import 'dart:math' as math;

import 'direction.dart';

class AlertChart {
  const AlertChart({
    required this.path,
    required this.compass,
    required this.peakIndex,
    required this.centerAz,
    required this.spanAz,
    required this.topAlt,
  });

  /// Points along the pass, rise first, as (x, y) in 0..1: x across the
  /// view left to right, y up from the horizon (0) to the top of the view (1).
  final List<(double, double)> path;

  /// Compass words that fall in view, with their x.
  final List<(String, double)> compass;

  /// Index into [path] of the highest point.
  final int peakIndex;

  /// The view: centre azimuth and width in degrees, and the altitude at its top.
  final double centerAz;
  final double spanAz;
  final double topAlt;

  (double, double) get rise => path.first;
  (double, double) get set => path.last;
  (double, double) get peak => path[peakIndex];

  /// Where a pass that's visible from [riseAz] to [setAz], highest at
  /// [peakAz]/[peakEl], crosses the sky. [startEl] is how high it is when
  /// it becomes visible (passes often appear above the horizon).
  static AlertChart forPass({
    required double riseAz,
    required double peakAz,
    required double setAz,
    required double peakEl,
    double startEl = 10,
    int samples = 48,
  }) {
    // Unwrap the azimuths so the path never jumps across north.
    final d1 = _signed(riseAz, peakAz), d2 = _signed(peakAz, setAz);
    final double a0 = riseAz, a1, a2;
    if (d1.abs() < 1 || d2.abs() < 1 || d1.sign == d2.sign) {
      a1 = a0 + d1;
      a2 = a1 + d2;
    } else {
      // A peak direction that disagrees (near-overhead passes swing fast):
      // trust rise and set, and go the short way between them.
      final d = _signed(riseAz, setAz);
      a1 = a0 + d / 2;
      a2 = a0 + d;
    }
    final start = math.min(startEl, peakEl);
    final pts = <(double az, double alt)>[
      for (var i = 0; i <= samples; i++)
        () {
          final t = i / samples;
          // Smooth curve through rise (t=0), peak (t=½) and set (t=1).
          final az = a0 * 2 * (t - 0.5) * (t - 1) - a1 * 4 * t * (t - 1) + a2 * 2 * t * (t - 0.5);
          final alt = start + (peakEl - start) * math.sin(math.pi * t);
          return (az, alt);
        }(),
    ];
    final lo = pts.map((p) => p.$1).reduce(math.min), hi = pts.map((p) => p.$1).reduce(math.max);
    final center = (lo + hi) / 2;
    final span = math.min(360.0, math.max(120.0, hi - lo + 60));
    final top = (peakEl + 18).clamp(35.0, 95.0);

    double x(double az) => (az - center) / span + 0.5;
    final path = [for (final p in pts) (x(p.$1), p.$2 / top)];

    final compass = <(String, double)>[];
    for (var k = -720.0; k <= 720; k += 45) {
      final cx = x(k);
      if (cx >= 0.04 && cx <= 0.96) compass.add((compassAbbrev(_norm(k)), cx));
    }
    return AlertChart(path: path, compass: compass, peakIndex: samples ~/ 2, centerAz: _norm(center), spanAz: span, topAlt: top);
  }

  static double _norm(double a) => ((a % 360) + 360) % 360;

  /// Shortest signed turn from [a] to [b], in (−180, 180].
  static double _signed(double a, double b) {
    var d = (b - a) % 360;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }
}
