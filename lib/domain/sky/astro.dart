/// Low-precision positions of the Sun, Moon and bright planets.
///
/// Paul Schlyter's method ("How to compute planetary positions"), good to
/// ~1–2 arcminutes for the Sun and planets and a few arcminutes for the Moon
/// (with the main perturbations and topocentric parallax). Plenty for
/// "Venus and Jupiter are 1° apart low in the west after sunset", moon phase,
/// and meteor-shower dates. Verified against NASA eclipse times and a known
/// conjunction in test/domain/astro_test.dart.
library;

import 'dart:math' as math;

const _d2r = math.pi / 180;
const _r2d = 180 / math.pi;

double _rev(double x) => x - (x / 360).floorToDouble() * 360;
double _sind(double x) => math.sin(x * _d2r);
double _cosd(double x) => math.cos(x * _d2r);
double _atan2d(double y, double x) => math.atan2(y, x) * _r2d;

/// Schlyter's day number: days since 2000 Jan 0.0 UT.
double dayNumber(DateTime utc) =>
    utc.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5 - 2451543.5;

double _obliquity(double d) => 23.4393 - 3.563e-7 * d;

/// Right ascension / declination (degrees) plus distance (AU, or Earth radii
/// for the Moon).
class Equatorial {
  const Equatorial(this.raDeg, this.decDeg, this.distance);
  final double raDeg;
  final double decDeg;
  final double distance;
}

class Horizontal {
  const Horizontal(this.azimuthDeg, this.altitudeDeg);
  final double azimuthDeg;
  final double altitudeDeg;
}

class _Ecl {
  const _Ecl(this.x, this.y, this.z);
  final double x, y, z;
  double get lonDeg => _rev(_atan2d(y, x));
  double get latDeg => _atan2d(z, math.sqrt(x * x + y * y));
  double get r => math.sqrt(x * x + y * y + z * z);
}

double _kepler(double mDeg, double e) {
  var eA = mDeg + e * _r2d * _sind(mDeg) * (1 + e * _cosd(mDeg));
  for (var i = 0; i < 8; i++) {
    final next = eA - (eA - e * _r2d * _sind(eA) - mDeg) / (1 - e * _cosd(eA));
    if ((next - eA).abs() < 1e-6) return next;
    eA = next;
  }
  return eA;
}

_Ecl _orbit(double n, double i, double w, double a, double e, double m) {
  final eA = _kepler(_rev(m), e);
  final xv = a * (_cosd(eA) - e);
  final yv = a * math.sqrt(1 - e * e) * _sind(eA);
  final v = _atan2d(yv, xv);
  final r = math.sqrt(xv * xv + yv * yv);
  final vw = v + w;
  return _Ecl(
    r * (_cosd(n) * _cosd(vw) - _sind(n) * _sind(vw) * _cosd(i)),
    r * (_sind(n) * _cosd(vw) + _cosd(n) * _sind(vw) * _cosd(i)),
    r * _sind(vw) * _sind(i),
  );
}

class _SunState {
  const _SunState(this.lonDeg, this.r, this.m, this.w);
  final double lonDeg, r, m, w;
  double get x => r * _cosd(lonDeg);
  double get y => r * _sind(lonDeg);
}

_SunState _sun(double d) {
  final w = 282.9404 + 4.70935e-5 * d;
  final e = 0.016709 - 1.151e-9 * d;
  final m = _rev(356.0470 + 0.9856002585 * d);
  final eA = _kepler(m, e);
  final xv = _cosd(eA) - e;
  final yv = math.sqrt(1 - e * e) * _sind(eA);
  return _SunState(_rev(_atan2d(yv, xv) + w), math.sqrt(xv * xv + yv * yv), m, w);
}

/// The Sun's geocentric ecliptic longitude (degrees). Meteor showers peak at
/// fixed values of this.
double solarLongitudeDeg(DateTime utc) => _sun(dayNumber(utc)).lonDeg;

Equatorial _eclToEq(double lonDeg, double latDeg, double dist, double d) {
  final x = dist * _cosd(lonDeg) * _cosd(latDeg);
  final y = dist * _sind(lonDeg) * _cosd(latDeg);
  final z = dist * _sind(latDeg);
  final ob = _obliquity(d);
  final ye = y * _cosd(ob) - z * _sind(ob);
  final ze = y * _sind(ob) + z * _cosd(ob);
  return Equatorial(_rev(_atan2d(ye, x)), _atan2d(ze, math.sqrt(x * x + ye * ye)), dist);
}

Equatorial sunEquatorial(DateTime utc) {
  final d = dayNumber(utc);
  final s = _sun(d);
  return _eclToEq(s.lonDeg, 0, s.r, d);
}

/// Geocentric Moon (distance in Earth radii).
Equatorial moonEquatorial(DateTime utc) {
  final d = dayNumber(utc);
  final s = _sun(d);
  final n = 125.1228 - 0.0529538083 * d;
  final w = 318.0634 + 0.1643573223 * d;
  final m = _rev(115.3654 + 13.0649929509 * d);
  final ecl = _orbit(n, 5.1454, w, 60.2666, 0.054900, m);
  final ls = s.m + s.w;
  final lm = m + w + n;
  final dd = lm - ls;
  final f = lm - n;
  final ms = s.m;
  final lon = ecl.lonDeg -
      1.274 * _sind(m - 2 * dd) +
      0.658 * _sind(2 * dd) -
      0.186 * _sind(ms) -
      0.059 * _sind(2 * m - 2 * dd) -
      0.057 * _sind(m - 2 * dd + ms) +
      0.053 * _sind(m + 2 * dd) +
      0.046 * _sind(2 * dd - ms) +
      0.041 * _sind(m - ms) -
      0.035 * _sind(dd) -
      0.031 * _sind(m + ms) -
      0.015 * _sind(2 * f - 2 * dd) +
      0.011 * _sind(m - 4 * dd);
  final lat = ecl.latDeg -
      0.173 * _sind(f - 2 * dd) -
      0.055 * _sind(m - f - 2 * dd) -
      0.046 * _sind(m + f - 2 * dd) +
      0.033 * _sind(f + 2 * dd) +
      0.017 * _sind(2 * m + f);
  final r = ecl.r - 0.58 * _cosd(m - 2 * dd) - 0.46 * _cosd(2 * dd);
  return _eclToEq(lon, lat, r, d);
}

enum Planet { venus, mars, jupiter, saturn }

extension PlanetInfo on Planet {
  String get label => switch (this) {
        Planet.venus => 'Venus',
        Planet.mars => 'Mars',
        Planet.jupiter => 'Jupiter',
        Planet.saturn => 'Saturn',
      };
}

_Ecl _heliocentric(Planet p, double d) {
  switch (p) {
    case Planet.venus:
      return _orbit(76.6799 + 2.46590e-5 * d, 3.3946 + 2.75e-8 * d, 54.8910 + 1.38374e-5 * d,
          0.723330, 0.006773 - 1.302e-9 * d, 48.0052 + 1.6021302244 * d);
    case Planet.mars:
      return _orbit(49.5574 + 2.11081e-5 * d, 1.8497 - 1.78e-8 * d, 286.5016 + 2.92961e-5 * d,
          1.523688, 0.093405 + 2.516e-9 * d, 18.6021 + 0.5240207766 * d);
    case Planet.jupiter:
    case Planet.saturn:
      final mj = _rev(19.8950 + 0.0830853001 * d);
      final ms = _rev(316.9670 + 0.0334442282 * d);
      final base = p == Planet.jupiter
          ? _orbit(100.4542 + 2.76854e-5 * d, 1.3030 - 1.557e-7 * d, 273.8777 + 1.64505e-5 * d,
              5.20256, 0.048498 + 4.469e-9 * d, mj)
          : _orbit(113.6634 + 2.38980e-5 * d, 2.4886 - 1.081e-7 * d, 339.3939 + 2.97661e-5 * d,
              9.55475, 0.055546 - 9.499e-9 * d, ms);
      double dLon, dLat = 0;
      if (p == Planet.jupiter) {
        dLon = -0.332 * _sind(2 * mj - 5 * ms - 67.6) -
            0.056 * _sind(2 * mj - 2 * ms + 21) +
            0.042 * _sind(3 * mj - 5 * ms + 21) -
            0.036 * _sind(mj - 2 * ms) +
            0.022 * _cosd(mj - ms) +
            0.023 * _sind(2 * mj - 3 * ms + 52) -
            0.016 * _sind(mj - 5 * ms - 69);
      } else {
        dLon = 0.812 * _sind(2 * mj - 5 * ms - 67.6) -
            0.229 * _cosd(2 * mj - 4 * ms - 2) +
            0.119 * _sind(mj - 2 * ms - 3) +
            0.046 * _sind(2 * mj - 6 * ms - 69) +
            0.014 * _sind(mj - 3 * ms + 32);
        dLat = -0.020 * _cosd(2 * mj - 4 * ms - 2) + 0.018 * _sind(2 * mj - 6 * ms - 49);
      }
      final lon = base.lonDeg + dLon, lat = base.latDeg + dLat, r = base.r;
      return _Ecl(r * _cosd(lon) * _cosd(lat), r * _sind(lon) * _cosd(lat), r * _sind(lat));
  }
}

Equatorial planetEquatorial(Planet p, DateTime utc) {
  final d = dayNumber(utc);
  final h = _heliocentric(p, d);
  final s = _sun(d);
  final x = h.x + s.x, y = h.y + s.y, z = h.z;
  final g = _Ecl(x, y, z);
  return _eclToEq(g.lonDeg, g.latDeg, g.r, d);
}

/// Local sidereal time in degrees.
double localSiderealDeg(DateTime utc, double lonDeg) {
  final ut = utc.toUtc();
  final hours = ut.hour + ut.minute / 60 + ut.second / 3600 + ut.millisecond / 3.6e6;
  // Schlyter's GMST0 is defined at 0h UT of the date.
  final s0 = _sun(dayNumber(ut) - hours / 24);
  final gmst0 = _rev(s0.m + s0.w + 180);
  return _rev(gmst0 + hours * 15.04107 + lonDeg);
}

Horizontal toHorizontal(Equatorial eq, DateTime utc, double latDeg, double lonDeg) {
  final ha = localSiderealDeg(utc, lonDeg) - eq.raDeg;
  final x = _cosd(ha) * _cosd(eq.decDeg);
  final y = _sind(ha) * _cosd(eq.decDeg);
  final z = _sind(eq.decDeg);
  final xh = x * _sind(latDeg) - z * _cosd(latDeg);
  final zh = x * _cosd(latDeg) + z * _sind(latDeg);
  return Horizontal(_rev(_atan2d(y, xh) + 180), _atan2d(zh, math.sqrt(xh * xh + y * y)));
}

/// Moon alt/az with topocentric parallax (up to ~1°, matters for pairings).
Horizontal moonHorizontal(DateTime utc, double latDeg, double lonDeg) {
  final geo = toHorizontal(moonEquatorial(utc), utc, latDeg, lonDeg);
  final mpar = math.asin(1 / moonEquatorial(utc).distance) * _r2d;
  final alt = geo.altitudeDeg - mpar * _cosd(geo.altitudeDeg);
  return Horizontal(geo.azimuthDeg, alt);
}

Horizontal planetHorizontal(Planet p, DateTime utc, double latDeg, double lonDeg) =>
    toHorizontal(planetEquatorial(p, utc), utc, latDeg, lonDeg);

/// Great-circle separation of two sky positions (degrees).
double separationDeg(Horizontal a, Horizontal b) {
  final c = _sind(a.altitudeDeg) * _sind(b.altitudeDeg) +
      _cosd(a.altitudeDeg) * _cosd(b.altitudeDeg) * _cosd(a.azimuthDeg - b.azimuthDeg);
  return math.acos(c.clamp(-1.0, 1.0)) * _r2d;
}

double equatorialSeparationDeg(Equatorial a, Equatorial b) {
  final c = _sind(a.decDeg) * _sind(b.decDeg) + _cosd(a.decDeg) * _cosd(b.decDeg) * _cosd(a.raDeg - b.raDeg);
  return math.acos(c.clamp(-1.0, 1.0)) * _r2d;
}

/// Sun–Moon elongation (0 = new, 180 = full).
double moonElongationDeg(DateTime utc) => equatorialSeparationDeg(sunEquatorial(utc), moonEquatorial(utc));

/// Illuminated fraction of the Moon, 0–1.
double moonIllumination(DateTime utc) => (1 - _cosd(moonElongationDeg(utc))) / 2;
