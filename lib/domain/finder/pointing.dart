/// Sky-finder math: where the phone's back camera points, and how to move
/// it onto a target. Pure Dart; the UI feeds it the fused rotation matrix.
library;

import 'dart:math' as math;

/// Direction in the sky. Azimuth from true north, clockwise.
class SkyDir {
  const SkyDir(this.azimuthDeg, this.elevationDeg);
  final double azimuthDeg;
  final double elevationDeg;
  @override
  String toString() => 'SkyDir(${azimuthDeg.toStringAsFixed(1)}, ${elevationDeg.toStringAsFixed(1)})';
}

/// Camera-axis direction from a device→world rotation matrix [r] (row-major,
/// world = ENU: x east, y magnetic north, z up; device: x right, y up the
/// screen, z out of the screen). The back camera looks along device −z.
/// [declinationDeg] converts magnetic to true azimuth.
SkyDir cameraDirection(List<double> r, {double declinationDeg = 0}) {
  assert(r.length == 9);
  final e = -r[2], n = -r[5], u = -r[8];
  final az = math.atan2(e, n) * 180 / math.pi + declinationDeg;
  final el = math.asin(u.clamp(-1.0, 1.0)) * 180 / math.pi;
  return SkyDir(_norm360(az), el);
}

double _norm360(double a) => ((a % 360) + 360) % 360;

/// Signed smallest difference target − current, in (−180, 180].
double azimuthDelta(double fromDeg, double toDeg) {
  var d = _norm360(toDeg - fromDeg);
  if (d > 180) d -= 360;
  return d;
}

double angularDistanceDeg(SkyDir a, SkyDir b) {
  const k = math.pi / 180;
  final c = math.sin(a.elevationDeg * k) * math.sin(b.elevationDeg * k) +
      math.cos(a.elevationDeg * k) * math.cos(b.elevationDeg * k) * math.cos((a.azimuthDeg - b.azimuthDeg) * k);
  return math.acos(c.clamp(-1.0, 1.0)) / k;
}

class Guidance {
  const Guidance({required this.dAzimuth, required this.dElevation, required this.distanceDeg, required this.onTarget});
  final double dAzimuth; // + = turn right
  final double dElevation; // + = tilt up
  final double distanceDeg;
  final bool onTarget;

  /// "Turn right, tilt up a little", or "You're on it".
  String get words {
    if (onTarget) return 'You\'re looking right at it';
    final parts = <String>[];
    if (dAzimuth.abs() > 8) {
      final side = dAzimuth > 0 ? 'right' : 'left';
      parts.add(dAzimuth.abs() > 60 ? 'Turn $side' : 'Turn $side a little');
    }
    if (dElevation.abs() > 6) {
      final dir = dElevation > 0 ? 'up' : 'down';
      parts.add(dElevation.abs() > 30 ? 'tilt $dir' : 'tilt $dir a little');
    }
    if (parts.isEmpty) return 'Almost there';
    final s = parts.join(', ');
    return s[0].toUpperCase() + s.substring(1);
  }
}

/// [toleranceDeg]: how close counts as "on it" (the phone's compass is good
/// to ~5–10°; we use 7°).
Guidance guide(SkyDir camera, SkyDir target, {double toleranceDeg = 7}) {
  final dist = angularDistanceDeg(camera, target);
  // Near the zenith azimuth is meaningless; only elevation matters.
  final dAz = camera.elevationDeg > 80 && target.elevationDeg > 80 ? 0.0 : azimuthDelta(camera.azimuthDeg, target.azimuthDeg);
  return Guidance(
    dAzimuth: dAz,
    dElevation: target.elevationDeg - camera.elevationDeg,
    distanceDeg: dist,
    onTarget: dist <= toleranceDeg,
  );
}

/// Time between haptic ticks while homing in: silent beyond 35°, then
/// faster as the phone closes in, like a Geiger counter. Null = no tick.
Duration? pulseInterval(double distanceDeg, {double startDeg = 35, double toleranceDeg = 7}) {
  if (distanceDeg > startDeg || distanceDeg <= toleranceDeg) return null;
  final f = (distanceDeg - toleranceDeg) / (startDeg - toleranceDeg); // 0 near … 1 far
  return Duration(milliseconds: (90 + f * 610).round());
}

/// Where [target] lands on a camera preview, in pixels from the preview's
/// centre (x right, y down), for a phone held with rotation matrix [r] (as
/// in [cameraDirection]). [verticalFovDeg] is the preview's field of view
/// along its height. Null when the target is behind the camera.
({double x, double y})? projectToScreen(List<double> r, SkyDir target,
    {required double declinationDeg, required double previewHeightPx, double verticalFovDeg = 66}) {
  assert(r.length == 9);
  const k = math.pi / 180;
  final az = (target.azimuthDeg - declinationDeg) * k; // world frame is magnetic
  final el = target.elevationDeg * k;
  final w = [math.cos(el) * math.sin(az), math.cos(el) * math.cos(az), math.sin(el)];
  // device = Rᵀ · world
  final dx = r[0] * w[0] + r[3] * w[1] + r[6] * w[2];
  final dy = r[1] * w[0] + r[4] * w[1] + r[7] * w[2];
  final dz = r[2] * w[0] + r[5] * w[1] + r[8] * w[2];
  if (dz >= -0.05) return null; // behind, or too far off-axis to draw
  final f = (previewHeightPx / 2) / math.tan(verticalFovDeg / 2 * k);
  return (x: f * dx / -dz, y: -f * dy / -dz);
}
