/// The sky behind the app: what's really above you, as you'd see it lying
/// back and looking up toward the equator. Stereographic, so constellation
/// shapes stay true.
library;

import 'dart:math' as math;

import 'astro.dart';

/// Which way the backdrop faces: south from the northern hemisphere, north
/// from the southern, where most of the turning sky is.
double backdropFacingAz(double latDeg) => latDeg >= 0 ? 180 : 0;

/// How high the middle of the backdrop is.
const backdropCenterAlt = 55.0;

/// Stereographic projection of [h] about the point ([centerAz],
/// [centerAlt]), in units where the centre is (0, 0) and a point 90° away
/// lands at radius 2. x grows to the right of the view, y upward. Null for
/// anything below the horizon.
({double x, double y})? backdropProject(Horizontal h, {required double centerAz, double centerAlt = backdropCenterAlt}) {
  if (h.altitudeDeg < 0) return null;
  const k = math.pi / 180;
  final alt = h.altitudeDeg * k, alt0 = centerAlt * k;
  final dAz = (h.azimuthDeg - centerAz) * k;
  final cosC = math.sin(alt0) * math.sin(alt) + math.cos(alt0) * math.cos(alt) * math.cos(dAz);
  if (cosC <= -0.98) return null; // the far side, which blows up
  final s = 2 / (1 + cosC);
  // Facing south, east (a smaller azimuth) comes out on the left.
  return (
    x: s * math.cos(alt) * math.sin(dAz),
    y: s * (math.cos(alt0) * math.sin(alt) - math.sin(alt0) * math.cos(alt) * math.cos(dAz)),
  );
}
