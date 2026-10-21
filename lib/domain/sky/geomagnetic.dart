/// Centred-dipole approximation of geomagnetic latitude.
///
/// Good to a couple of degrees, which is all the Kp-vs-latitude aurora rule
/// needs. Pole position is the IGRF-14 geomagnetic north pole for 2025.
library;

import 'dart:math' as math;

const geomagneticPoleLatDeg = 80.9;
const geomagneticPoleLonDeg = -72.6;

double geomagneticLatitudeDeg(double latDeg, double lonDeg) {
  const d2r = math.pi / 180;
  final lat = latDeg * d2r;
  final lon = lonDeg * d2r;
  final pLat = geomagneticPoleLatDeg * d2r;
  final pLon = geomagneticPoleLonDeg * d2r;
  final s = math.sin(lat) * math.sin(pLat) +
      math.cos(lat) * math.cos(pLat) * math.cos(lon - pLon);
  return math.asin(s.clamp(-1.0, 1.0)) / d2r;
}
