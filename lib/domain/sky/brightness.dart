/// Visual magnitude of a sunlit satellite from range and phase angle.
///
/// Standard model: a diffusely reflecting sphere. Standard magnitude is the
/// brightness at 1000 km range and 90° phase angle.
///   m = m_std + 5·log10(range/1000) − 2.5·log10(F(φ) / F(90°))
///   F(φ) = (sin φ + (π − φ)·cos φ) / π
/// Spotter-grade (±0.5 mag); good enough to say "brighter than any star".
library;

import 'dart:math' as math;

import 'astro.dart';

/// Typical standard magnitudes. Newly launched Starlinks in train
/// formation are much brighter than the settled constellation.
abstract final class StdMag {
  static const iss = -1.3;
  static const tiangong = -0.6;
  static const starlinkTrain = 3.0;
}

double _phaseFunction(double phaseRad) =>
    (math.sin(phaseRad) + (math.pi - phaseRad) * math.cos(phaseRad)) / math.pi;

/// Magnitude from range (km) and phase angle (degrees; 0 = fully lit).
double satelliteMagnitude({required double stdMag, required double rangeKm, required double phaseDeg}) {
  final phi = (phaseDeg.clamp(0.5, 179.5)) * math.pi / 180;
  final f = _phaseFunction(phi) / _phaseFunction(math.pi / 2);
  return stdMag + 5 * math.log(rangeKm / 1000) / math.ln10 - 2.5 * math.log(f) / math.ln10;
}

/// Phase angle at the satellite between the Sun and the observer.
/// [satEci] and [observerEci] in km, same inertial frame (TEME ≈ of-date).
double phaseAngleDeg({required List<double> satEci, required List<double> observerEci, required DateTime utc}) {
  final sun = sunEquatorial(utc);
  const au = 149597870.7;
  final ra = sun.raDeg * math.pi / 180, dec = sun.decDeg * math.pi / 180;
  final sunEci = [
    sun.distance * au * math.cos(dec) * math.cos(ra),
    sun.distance * au * math.cos(dec) * math.sin(ra),
    sun.distance * au * math.sin(dec),
  ];
  final toSun = [for (var i = 0; i < 3; i++) sunEci[i] - satEci[i]];
  final toObs = [for (var i = 0; i < 3; i++) observerEci[i] - satEci[i]];
  double dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  double len(List<double> a) => math.sqrt(dot(a, a));
  final c = dot(toSun, toObs) / (len(toSun) * len(toObs));
  return math.acos(c.clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// Observer position in the inertial frame (km): WGS-84 → ECEF → rotate by
/// Greenwich sidereal time.
List<double> observerEci(double latDeg, double lonDeg, DateTime utc, {double altitudeKm = 0}) {
  const a = 6378.137, f = 1 / 298.257223563;
  final e2 = f * (2 - f);
  final lat = latDeg * math.pi / 180;
  final n = a / math.sqrt(1 - e2 * math.sin(lat) * math.sin(lat));
  final r = (n + altitudeKm) * math.cos(lat);
  final z = (n * (1 - e2) + altitudeKm) * math.sin(lat);
  final theta = localSiderealDeg(utc, lonDeg) * math.pi / 180;
  return [r * math.cos(theta), r * math.sin(theta), z];
}

/// Human words for a magnitude. Venus ≈ −4, Sirius ≈ −1.5, Vega ≈ 0.
String magnitudeWord(double mag) {
  if (mag <= -3.5) return 'as bright as Venus';
  if (mag <= -2.0) return 'brighter than any star';
  if (mag <= -0.5) return 'as bright as the brightest stars';
  if (mag <= 1.5) return 'a bright, steady star';
  if (mag <= 3.0) return 'easy to see away from city lights';
  return 'faint, needs a dark sky';
}
