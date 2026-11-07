/// Low-precision positions of the Sun, Moon and bright planets.
///
/// Paul Schlyter's method ("How to compute planetary positions"), good to
/// ~1–2 arcminutes for the Sun and planets. The Moon is Meeus ch. 47 with
/// exact topocentric parallax, good to ~10 arcseconds (docs/moon-accuracy.md)
/// because occultations need it. Plenty for
/// "Venus and Jupiter are 1° apart low in the west after sunset", moon phase,
/// and meteor-shower dates. Verified against NASA eclipse times and a known
/// conjunction in test/domain/astro_test.dart.
///
/// For other centuries it adds what Schlyter's linear elements leave out:
/// ΔT (the Sun, Moon and planets run on TT), the quadratic term of
/// precession, the IAU obliquity polynomial and IAU sidereal time (Meeus
/// ch. 12 & 22). Checked against JPL Horizons from
/// 3000 BC to 2400 AD in test/domain/history_test.dart.
library;

import 'dart:math' as math;

import 'delta_t.dart';

const _d2r = math.pi / 180;
const _r2d = 180 / math.pi;

double _rev(double x) => x - (x / 360).floorToDouble() * 360;
double _sind(double x) => math.sin(x * _d2r);
double _cosd(double x) => math.cos(x * _d2r);
double _atan2d(double y, double x) => math.atan2(y, x) * _r2d;

/// Schlyter's day number: days since 2000 Jan 0.0 UT.
double dayNumber(DateTime utc) =>
    utc.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5 - 2451543.5;

/// Julian centuries from J2000.0 for a day number.
double _centuries(double d) => (d - 1.5) / 36525;

/// Day number on TT, the steady time the Sun, Moon and planets keep.
double _ttDay(DateTime utc) {
  final d = dayNumber(utc);
  return d + deltaTSeconds(2000 + (d - 1.5) / 365.25) / 86400;
}

double _obliquity(double d) {
  final t = _centuries(d);
  return 23.439291 - 0.0130042 * t - 1.64e-7 * t * t + 5.04e-7 * t * t * t;
}

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
  // Schlyter's elements precess linearly; this is the 1.11″·T² that's
  // missing (0.7° by 3000 BC).
  final t = _centuries(d);
  return _eclOfDateToEq(lonDeg + 3.0865e-4 * t * t, latDeg, dist, d);
}

Equatorial _eclOfDateToEq(double lonDeg, double latDeg, double dist, double d) {
  final x = dist * _cosd(lonDeg) * _cosd(latDeg);
  final y = dist * _sind(lonDeg) * _cosd(latDeg);
  final z = dist * _sind(latDeg);
  final ob = _obliquity(d);
  final ye = y * _cosd(ob) - z * _sind(ob);
  final ze = y * _sind(ob) + z * _cosd(ob);
  return Equatorial(_rev(_atan2d(ye, x)), _atan2d(ze, math.sqrt(x * x + ye * ye)), dist);
}

Equatorial sunEquatorial(DateTime utc) {
  final d = _ttDay(utc);
  final s = _sun(d);
  return _eclToEq(s.lonDeg, 0, s.r, d);
}

// Meeus, Astronomical Algorithms (2nd ed.), table 47.A: multiples of D, M,
// M′, F, then the sine coefficient for longitude and the cosine for
// distance (10⁻⁶ degree, 10⁻³ km).
const _moonLonDist = <int>[
  0, 0, 1, 0, 6288774, -20905355, 2, 0, -1, 0, 1274027, -3699111, //
  2, 0, 0, 0, 658314, -2955968, 0, 0, 2, 0, 213618, -569925, //
  0, 1, 0, 0, -185116, 48888, 0, 0, 0, 2, -114332, -3149, //
  2, 0, -2, 0, 58793, 246158, 2, -1, -1, 0, 57066, -152138, //
  2, 0, 1, 0, 53322, -170733, 2, -1, 0, 0, 45758, -204586, //
  0, 1, -1, 0, -40923, -129620, 1, 0, 0, 0, -34720, 108743, //
  0, 1, 1, 0, -30383, 104755, 2, 0, 0, -2, 15327, 10321, //
  0, 0, 1, 2, -12528, 0, 0, 0, 1, -2, 10980, 79661, //
  4, 0, -1, 0, 10675, -34782, 0, 0, 3, 0, 10034, -23210, //
  4, 0, -2, 0, 8548, -21636, 2, 1, -1, 0, -7888, 24208, //
  2, 1, 0, 0, -6766, 30824, 1, 0, -1, 0, -5163, -8379, //
  1, 1, 0, 0, 4987, -16675, 2, -1, 1, 0, 4036, -12831, //
  2, 0, 2, 0, 3994, -10445, 4, 0, 0, 0, 3861, -11650, //
  2, 0, -3, 0, 3665, 14403, 0, 1, -2, 0, -2689, -7003, //
  2, 0, -1, 2, -2602, 0, 2, -1, -2, 0, 2390, 10056, //
  1, 0, 1, 0, -2348, 6322, 2, -2, 0, 0, 2236, -9884, //
  0, 1, 2, 0, -2120, 5751, 0, 2, 0, 0, -2069, 0, //
  2, -2, -1, 0, 2048, -4950, 2, 0, 1, -2, -1773, 4130, //
  2, 0, 0, 2, -1595, 0, 4, -1, -1, 0, 1215, -3958, //
  0, 0, 2, 2, -1110, 0, 3, 0, -1, 0, -892, 3258, //
  2, 1, 1, 0, -810, 2616, 4, -1, -2, 0, 759, -1897, //
  0, 2, -1, 0, -713, -2117, 2, 2, -1, 0, -700, 2354, //
  2, 1, -2, 0, 691, 0, 2, -1, 0, -2, 596, 0, //
  4, 0, 1, 0, 549, -1423, 0, 0, 4, 0, 537, -1117, //
  4, -1, 0, 0, 520, -1571, 1, 0, -2, 0, -487, -1739, //
  2, 1, 0, -2, -399, 0, 0, 0, 2, -2, -381, -4421, //
  1, 1, 1, 0, 351, 0, 3, 0, -2, 0, -340, 0, //
  4, 0, -3, 0, 330, 0, 2, -1, 2, 0, 327, 0, //
  0, 2, 1, 0, -323, 1165, 1, 1, -1, 0, 299, 0, //
  2, 0, 3, 0, 294, 0, 2, 0, -1, -2, 0, 8752, //
];

// Table 47.B: multiples of D, M, M′, F, then the sine coefficient for
// latitude (10⁻⁶ degree).
const _moonLat = <int>[
  0, 0, 0, 1, 5128122, 0, 0, 1, 1, 280602, 0, 0, 1, -1, 277693, //
  2, 0, 0, -1, 173237, 2, 0, -1, 1, 55413, 2, 0, -1, -1, 46271, //
  2, 0, 0, 1, 32573, 0, 0, 2, 1, 17198, 2, 0, 1, -1, 9266, //
  0, 0, 2, -1, 8822, 2, -1, 0, -1, 8216, 2, 0, -2, -1, 4324, //
  2, 0, 1, 1, 4200, 2, 1, 0, -1, -3359, 2, -1, -1, 1, 2463, //
  2, -1, 0, 1, 2211, 2, -1, -1, -1, 2065, 0, 1, -1, -1, -1870, //
  4, 0, -1, -1, 1828, 0, 1, 0, 1, -1794, 0, 0, 0, 3, -1749, //
  0, 1, -1, 1, -1565, 1, 0, 0, 1, -1491, 0, 1, 1, 1, -1475, //
  0, 1, 1, -1, -1410, 0, 1, 0, -1, -1344, 1, 0, 0, -1, -1335, //
  0, 0, 3, 1, 1107, 4, 0, 0, -1, 1021, 4, 0, -1, 1, 833, //
  0, 0, 1, -3, 777, 4, 0, -2, 1, 671, 2, 0, 0, -3, 607, //
  2, 0, 2, -1, 596, 2, -1, 1, -1, 491, 2, 0, -2, 1, -451, //
  0, 0, 3, -1, 439, 2, 0, 2, 1, 422, 2, 0, -3, -1, 421, //
  2, 1, -1, 1, -366, 2, 1, 0, 1, -351, 4, 0, 0, 1, 331, //
  2, -1, 1, 1, 315, 2, -2, 0, -1, 302, 0, 0, 1, 3, -283, //
  2, 1, 1, -1, -229, 1, 1, 0, -1, 223, 1, 1, 0, 1, 223, //
  0, 1, -2, -1, -220, 2, 1, -1, -1, -220, 1, 0, 1, 1, -185, //
  2, -1, -2, -1, 181, 0, 1, 2, 1, -177, 4, 0, -2, -1, 176, //
  4, -1, -1, -1, 166, 1, 0, 1, -1, -164, 4, 0, 1, -1, 132, //
  1, 0, -1, -1, -119, 4, -1, 0, -1, 115, 2, -2, 0, 1, 107, //
];

/// Geocentric Moon (distance in Earth radii), referred to the mean equator
/// and equinox of date like the precessed stars. Meeus ch. 47, the
/// truncated ELP-2000/82: he gives ~10″ in longitude and 4″ in latitude,
/// good enough to time an occultation (docs/moon-accuracy.md). Its T²
/// terms carry the Moon's secular acceleration and already include
/// precession, so it skips [_eclToEq]'s correction for Schlyter.
Equatorial moonEquatorial(DateTime utc) {
  final d = _ttDay(utc);
  final t = _centuries(d), t2 = t * t, t3 = t2 * t, t4 = t3 * t;
  final lp = 218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538841 - t4 / 65194000;
  final dd = 297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545868 - t4 / 113065000;
  final m = 357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000;
  final mp = 134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69699 - t4 / 14712000;
  final f = 93.2720950 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3526000 + t4 / 863310000;
  final a1 = 119.75 + 131.849 * t, a2 = 53.09 + 479264.290 * t, a3 = 313.45 + 481266.484 * t;
  // The Earth's orbit is getting rounder: terms in M shrink with it.
  final e = 1 - 0.002516 * t - 0.0000074 * t2;
  double ecc(int k) => k == 0 ? 1 : (k.abs() == 1 ? e : e * e);
  var sl = 3958 * _sind(a1) + 1962 * _sind(lp - f) + 318 * _sind(a2);
  var sr = 0.0;
  for (var i = 0; i < _moonLonDist.length; i += 6) {
    final arg = _moonLonDist[i] * dd + _moonLonDist[i + 1] * m + _moonLonDist[i + 2] * mp + _moonLonDist[i + 3] * f;
    final k = ecc(_moonLonDist[i + 1]);
    sl += _moonLonDist[i + 4] * k * _sind(arg);
    sr += _moonLonDist[i + 5] * k * _cosd(arg);
  }
  var sb = -2235 * _sind(lp) + 382 * _sind(a3) + 175 * _sind(a1 - f) + 175 * _sind(a1 + f) +
      127 * _sind(lp - mp) - 115 * _sind(lp + mp);
  for (var i = 0; i < _moonLat.length; i += 5) {
    final arg = _moonLat[i] * dd + _moonLat[i + 1] * m + _moonLat[i + 2] * mp + _moonLat[i + 3] * f;
    sb += _moonLat[i + 4] * ecc(_moonLat[i + 1]) * _sind(arg);
  }
  final km = 385000.56 + sr / 1000;
  return _eclOfDateToEq(_rev(lp + sl / 1e6), sb / 1e6, km / 6378.14, d);
}

enum Planet { mercury, venus, mars, jupiter, saturn }

extension PlanetInfo on Planet {
  String get label => switch (this) {
        Planet.mercury => 'Mercury',
        Planet.venus => 'Venus',
        Planet.mars => 'Mars',
        Planet.jupiter => 'Jupiter',
        Planet.saturn => 'Saturn',
      };
}

_Ecl _heliocentric(Planet p, double d) {
  switch (p) {
    case Planet.mercury:
      return _orbit(48.3313 + 3.24587e-5 * d, 7.0047 + 5.00e-8 * d, 29.1241 + 1.01444e-5 * d,
          0.387098, 0.205635 + 5.59e-10 * d, 168.6562 + 4.0923344368 * d);
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
  final d = _ttDay(utc);
  final h = _heliocentric(p, d);
  final s = _sun(d);
  final x = h.x + s.x, y = h.y + s.y, z = h.z;
  final g = _Ecl(x, y, z);
  return _eclToEq(g.lonDeg, g.latDeg, g.r, d);
}

/// Local mean sidereal time in degrees (IAU 1982 GMST, Meeus 12.4).
double localSiderealDeg(DateTime utc, double lonDeg) {
  final d = dayNumber(utc) - 1.5, t = d / 36525;
  return _rev(280.46061837 + 360.98564736629 * d + 0.000387933 * t * t - t * t * t / 38710000 + lonDeg);
}

/// J2000 catalogue coordinates moved to the equator and equinox of [utc]
/// (IAU 1976 precession, Meeus ch. 21): about 1.4° a century, so it's what
/// lets the stars sit right on a date centuries away.
Equatorial precessFromJ2000(double raDeg, double decDeg, DateTime utc) {
  final t = _centuries(dayNumber(utc));
  final zeta = (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) / 3600;
  final z = (2306.2181 * t + 1.09468 * t * t + 0.018203 * t * t * t) / 3600;
  final theta = (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) / 3600;
  final a = _cosd(decDeg) * _sind(raDeg + zeta);
  final b = _cosd(theta) * _cosd(decDeg) * _cosd(raDeg + zeta) - _sind(theta) * _sind(decDeg);
  final c = _sind(theta) * _cosd(decDeg) * _cosd(raDeg + zeta) + _cosd(theta) * _sind(decDeg);
  return Equatorial(_rev(_atan2d(a, b) + z), math.asin(c.clamp(-1.0, 1.0)) * _r2d, 1);
}

/// Where a J2000 catalogue position (a star, a constellation, a showpiece)
/// is in your sky at [utc]. [pm] is the star's own drift across the sky in
/// milliarcseconds a year (RA·cos Dec, Dec): Arcturus moves ~2° in 3,000
/// years, Alpha Centauri ~3°.
Horizontal catalogHorizontal(double raDeg, double decDeg, DateTime utc, double latDeg, double lonDeg,
    {(double, double)? pm}) {
  if (pm != null) {
    final years = (dayNumber(utc) - 1.5) / 365.25;
    decDeg += pm.$2 * years / 3.6e6;
    raDeg += pm.$1 * years / 3.6e6 / math.max(_cosd(decDeg), 1e-3);
  }
  return toHorizontal(precessFromJ2000(raDeg, decDeg, utc), utc, latDeg, lonDeg);
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

/// The Moon as seen from where you stand (distance in Earth radii): up to
/// ~1° from the geocentric place, which is the whole of an occultation.
/// Subtracts your position on the WGS 84 ellipsoid (Meeus ch. 11) from the
/// Moon's, so it's exact rather than a first-order shift in altitude.
Equatorial moonTopocentric(DateTime utc, double latDeg, double lonDeg) {
  final m = moonEquatorial(utc);
  const ba = 1 - 1 / 298.257223563;
  final u = math.atan(ba * math.tan(latDeg * _d2r));
  final lst = localSiderealDeg(utc, lonDeg);
  final x = m.distance * _cosd(m.decDeg) * _cosd(m.raDeg) - math.cos(u) * _cosd(lst);
  final y = m.distance * _cosd(m.decDeg) * _sind(m.raDeg) - math.cos(u) * _sind(lst);
  final z = m.distance * _sind(m.decDeg) - ba * math.sin(u);
  final r = math.sqrt(x * x + y * y + z * z);
  return Equatorial(_rev(_atan2d(y, x)), math.asin(z / r) * _r2d, r);
}

/// Moon alt/az from the ground (see [moonTopocentric]).
Horizontal moonHorizontal(DateTime utc, double latDeg, double lonDeg) =>
    toHorizontal(moonTopocentric(utc, latDeg, lonDeg), utc, latDeg, lonDeg);

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

/// The Moon's ecliptic longitude minus the Sun's (degrees, 0–360): 0 at new
/// Moon, 180 at full. The phases are defined by this; the elongation only
/// reaches 180° in an eclipse.
double moonLongitudeFromSunDeg(DateTime utc) {
  final ob = _obliquity(_ttDay(utc));
  double lon(Equatorial e) =>
      _atan2d(_sind(e.raDeg) * _cosd(ob) + math.tan(e.decDeg * _d2r) * _sind(ob), _cosd(e.raDeg));
  return _rev(lon(moonEquatorial(utc)) - lon(sunEquatorial(utc)));
}

/// The Moon's distance from the centre of the Earth (km).
double moonDistanceKm(DateTime utc) => moonEquatorial(utc).distance * 6378.14;

Horizontal sunHorizontal(DateTime utc, double latDeg, double lonDeg) =>
    toHorizontal(sunEquatorial(utc), utc, latDeg, lonDeg);

/// Apparent radius of the Sun's disk (degrees), ~0.26–0.27.
double sunRadiusDeg(DateTime utc) => 0.26656 / sunEquatorial(utc).distance;

/// Apparent radius of the Moon's disk from the ground (degrees), ~0.24–0.28.
/// The observer is up to one Earth radius closer than the centre when the
/// Moon is high, which makes it ~1.5% bigger.
double moonRadiusDeg(DateTime utc, double altitudeDeg) {
  const earthKm = 6378.14, moonKm = 1737.4;
  final distKm = moonEquatorial(utc).distance * earthKm - earthKm * _sind(altitudeDeg);
  return math.asin(moonKm / distKm) * _r2d;
}


/// Elongation: the planet's angle from the Sun as seen from Earth. Small
/// means lost in the glare.
double planetElongationDeg(Planet p, DateTime utc) =>
    equatorialSeparationDeg(planetEquatorial(p, utc), sunEquatorial(utc));

/// True when the planet is east of the Sun (an evening object).
bool planetIsEvening(Planet p, DateTime utc) {
  final d = dayNumber(utc);
  final h = _heliocentric(p, d);
  final s = _sun(d);
  final geo = _Ecl(h.x + s.x, h.y + s.y, h.z);
  final diff = _rev(geo.lonDeg - s.lonDeg);
  return diff < 180;
}

/// Apparent visual magnitude (Schlyter's formulas; Saturn includes its
/// rings). Good to a few tenths: enough to say "brightest thing up".
double planetMagnitude(Planet p, DateTime utc) {
  final d = dayNumber(utc);
  final h = _heliocentric(p, d);
  final s = _sun(d);
  final geo = _Ecl(h.x + s.x, h.y + s.y, h.z);
  final r = h.r, big = geo.r, sun = s.r;
  final cosFv = ((r * r + big * big - sun * sun) / (2 * r * big)).clamp(-1.0, 1.0);
  final fv = math.acos(cosFv) * _r2d;
  final dist = 5 * math.log(r * big) / math.ln10;
  switch (p) {
    case Planet.mercury:
      return -0.36 + dist + 0.027 * fv + 2.2e-13 * math.pow(fv, 6);
    case Planet.venus:
      return -4.34 + dist + 0.013 * fv + 4.2e-7 * fv * fv * fv;
    case Planet.mars:
      return -1.51 + dist + 0.016 * fv;
    case Planet.jupiter:
      return -9.25 + dist + 0.014 * fv;
    case Planet.saturn:
      // Ring tilt as seen from Earth.
      final ir = 28.06, nr = 169.51 + 3.82e-5 * d;
      final los = geo.latDeg, lon = geo.lonDeg;
      final sinB = _sind(ir) * _cosd(los) * _sind(lon - nr) - _cosd(ir) * _sind(los);
      final ring = -2.6 * sinB.abs() + 1.2 * sinB * sinB;
      return -9.0 + dist + 0.044 * fv + ring;
  }
}
