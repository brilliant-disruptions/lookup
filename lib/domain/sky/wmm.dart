/// World Magnetic Model 2025 (NOAA NCEI / BGS), valid 2025.0–2030.0.
///
/// Used to turn the phone's magnetic-north heading into a true-north one for
/// the sky finder. Coefficients copied verbatim from WMM.COF (public domain,
/// https://www.ncei.noaa.gov/products/world-magnetic-model). Verified against
/// the official WMM2025 test values in test/domain/wmm_test.dart.
library;

import 'dart:math' as math;

const _epoch = 2025.0;
const _a = 6371.2; // geomagnetic reference radius, km
const _wgsA = 6378.137;
const _wgsF = 1 / 298.257223563;

/// [n, m, g, h, gdot, hdot], nT and nT/yr.
const _coefficients = <List<num>>[
  [1, 0, -29351.8, 0.0, 12.0, 0.0],
  [1, 1, -1410.8, 4545.4, 9.7, -21.5],
  [2, 0, -2556.6, 0.0, -11.6, 0.0],
  [2, 1, 2951.1, -3133.6, -5.2, -27.7],
  [2, 2, 1649.3, -815.1, -8.0, -12.1],
  [3, 0, 1361.0, 0.0, -1.3, 0.0],
  [3, 1, -2404.1, -56.6, -4.2, 4.0],
  [3, 2, 1243.8, 237.5, 0.4, -0.3],
  [3, 3, 453.6, -549.5, -15.6, -4.1],
  [4, 0, 895.0, 0.0, -1.6, 0.0],
  [4, 1, 799.5, 278.6, -2.4, -1.1],
  [4, 2, 55.7, -133.9, -6.0, 4.1],
  [4, 3, -281.1, 212.0, 5.6, 1.6],
  [4, 4, 12.1, -375.6, -7.0, -4.4],
  [5, 0, -233.2, 0.0, 0.6, 0.0],
  [5, 1, 368.9, 45.4, 1.4, -0.5],
  [5, 2, 187.2, 220.2, 0.0, 2.2],
  [5, 3, -138.7, -122.9, 0.6, 0.4],
  [5, 4, -142.0, 43.0, 2.2, 1.7],
  [5, 5, 20.9, 106.1, 0.9, 1.9],
  [6, 0, 64.4, 0.0, -0.2, 0.0],
  [6, 1, 63.8, -18.4, -0.4, 0.3],
  [6, 2, 76.9, 16.8, 0.9, -1.6],
  [6, 3, -115.7, 48.8, 1.2, -0.4],
  [6, 4, -40.9, -59.8, -0.9, 0.9],
  [6, 5, 14.9, 10.9, 0.3, 0.7],
  [6, 6, -60.7, 72.7, 0.9, 0.9],
  [7, 0, 79.5, 0.0, -0.0, 0.0],
  [7, 1, -77.0, -48.9, -0.1, 0.6],
  [7, 2, -8.8, -14.4, -0.1, 0.5],
  [7, 3, 59.3, -1.0, 0.5, -0.8],
  [7, 4, 15.8, 23.4, -0.1, 0.0],
  [7, 5, 2.5, -7.4, -0.8, -1.0],
  [7, 6, -11.1, -25.1, -0.8, 0.6],
  [7, 7, 14.2, -2.3, 0.8, -0.2],
  [8, 0, 23.2, 0.0, -0.1, 0.0],
  [8, 1, 10.8, 7.1, 0.2, -0.2],
  [8, 2, -17.5, -12.6, 0.0, 0.5],
  [8, 3, 2.0, 11.4, 0.5, -0.4],
  [8, 4, -21.7, -9.7, -0.1, 0.4],
  [8, 5, 16.9, 12.7, 0.3, -0.5],
  [8, 6, 15.0, 0.7, 0.2, -0.6],
  [8, 7, -16.8, -5.2, -0.0, 0.3],
  [8, 8, 0.9, 3.9, 0.2, 0.2],
  [9, 0, 4.6, 0.0, -0.0, 0.0],
  [9, 1, 7.8, -24.8, -0.1, -0.3],
  [9, 2, 3.0, 12.2, 0.1, 0.3],
  [9, 3, -0.2, 8.3, 0.3, -0.3],
  [9, 4, -2.5, -3.3, -0.3, 0.3],
  [9, 5, -13.1, -5.2, 0.0, 0.2],
  [9, 6, 2.4, 7.2, 0.3, -0.1],
  [9, 7, 8.6, -0.6, -0.1, -0.2],
  [9, 8, -8.7, 0.8, 0.1, 0.4],
  [9, 9, -12.9, 10.0, -0.1, 0.1],
  [10, 0, -1.3, 0.0, 0.1, 0.0],
  [10, 1, -6.4, 3.3, 0.0, 0.0],
  [10, 2, 0.2, 0.0, 0.1, -0.0],
  [10, 3, 2.0, 2.4, 0.1, -0.2],
  [10, 4, -1.0, 5.3, -0.0, 0.1],
  [10, 5, -0.6, -9.1, -0.3, -0.1],
  [10, 6, -0.9, 0.4, 0.0, 0.1],
  [10, 7, 1.5, -4.2, -0.1, 0.0],
  [10, 8, 0.9, -3.8, -0.1, -0.1],
  [10, 9, -2.7, 0.9, -0.0, 0.2],
  [10, 10, -3.9, -9.1, -0.0, -0.0],
  [11, 0, 2.9, 0.0, 0.0, 0.0],
  [11, 1, -1.5, 0.0, -0.0, -0.0],
  [11, 2, -2.5, 2.9, 0.0, 0.1],
  [11, 3, 2.4, -0.6, 0.0, -0.0],
  [11, 4, -0.6, 0.2, 0.0, 0.1],
  [11, 5, -0.1, 0.5, -0.1, -0.0],
  [11, 6, -0.6, -0.3, 0.0, -0.0],
  [11, 7, -0.1, -1.2, -0.0, 0.1],
  [11, 8, 1.1, -1.7, -0.1, -0.0],
  [11, 9, -1.0, -2.9, -0.1, 0.0],
  [11, 10, -0.2, -1.8, -0.1, 0.0],
  [11, 11, 2.6, -2.3, -0.1, 0.0],
  [12, 0, -2.0, 0.0, 0.0, 0.0],
  [12, 1, -0.2, -1.3, 0.0, -0.0],
  [12, 2, 0.3, 0.7, -0.0, 0.0],
  [12, 3, 1.2, 1.0, -0.0, -0.1],
  [12, 4, -1.3, -1.4, -0.0, 0.1],
  [12, 5, 0.6, -0.0, -0.0, -0.0],
  [12, 6, 0.6, 0.6, 0.1, -0.0],
  [12, 7, 0.5, -0.1, -0.0, -0.0],
  [12, 8, -0.1, 0.8, 0.0, 0.0],
  [12, 9, -0.4, 0.1, 0.0, -0.0],
  [12, 10, -0.2, -1.0, -0.1, -0.0],
  [12, 11, -1.3, 0.1, -0.0, 0.0],
  [12, 12, -0.7, 0.2, -0.1, -0.1],
];

const _maxN = 12;

class MagneticField {
  const MagneticField({required this.declinationDeg, required this.inclinationDeg, required this.x, required this.y, required this.z});
  final double declinationDeg;
  final double inclinationDeg;
  final double x, y, z; // north, east, down; nT
}

/// Magnetic field at a geodetic position. [altitudeKm] above the WGS-84
/// ellipsoid; [decimalYear] e.g. 2026.8.
MagneticField magneticField(double latDeg, double lonDeg, {double altitudeKm = 0, required double decimalYear}) {
  const d2r = math.pi / 180;
  final t = decimalYear - _epoch;
  final lat = latDeg * d2r;
  final lon = lonDeg * d2r;

  // Geodetic -> geocentric spherical.
  final e2 = _wgsF * (2 - _wgsF);
  final sinLat = math.sin(lat);
  final rc = _wgsA / math.sqrt(1 - e2 * sinLat * sinLat);
  final p = (rc + altitudeKm) * math.cos(lat);
  final z = (rc * (1 - e2) + altitudeKm) * sinLat;
  final r = math.sqrt(p * p + z * z);
  final latC = math.asin(z / r);

  // Schmidt semi-normalised associated Legendre functions in colatitude.
  final ct = math.sin(latC); // cos(colatitude)
  final st = math.cos(latC); // sin(colatitude)
  final pnm = List.generate(_maxN + 1, (_) => List.filled(_maxN + 1, 0.0));
  final dp = List.generate(_maxN + 1, (_) => List.filled(_maxN + 1, 0.0));
  final s = List.generate(_maxN + 1, (_) => List.filled(_maxN + 1, 0.0));
  pnm[0][0] = 1;
  s[0][0] = 1;
  for (var n = 1; n <= _maxN; n++) {
    for (var m = 0; m <= n; m++) {
      if (n == m) {
        pnm[n][m] = st * pnm[n - 1][m - 1];
        dp[n][m] = st * dp[n - 1][m - 1] + ct * pnm[n - 1][m - 1];
      } else if (n == 1 && m == 0) {
        pnm[n][m] = ct * pnm[n - 1][m];
        dp[n][m] = ct * dp[n - 1][m] - st * pnm[n - 1][m];
      } else {
        final k = n > 1 && m <= n - 2
            ? ((n - 1) * (n - 1) - m * m) / ((2 * n - 1) * (2 * n - 3))
            : 0.0;
        final p2 = n > 1 && m <= n - 2 ? pnm[n - 2][m] : 0.0;
        final dp2 = n > 1 && m <= n - 2 ? dp[n - 2][m] : 0.0;
        pnm[n][m] = ct * pnm[n - 1][m] - k * p2;
        dp[n][m] = ct * dp[n - 1][m] - st * pnm[n - 1][m] - k * dp2;
      }
      if (m == 0) {
        s[n][0] = s[n - 1][0] * (2 * n - 1) / n;
      } else {
        s[n][m] = s[n][m - 1] * math.sqrt((n - m + 1) * (m == 1 ? 2 : 1) / (n + m));
      }
    }
  }

  var br = 0.0, bt = 0.0, bp = 0.0;
  for (final c in _coefficients) {
    final n = c[0].toInt(), m = c[1].toInt();
    final g = (c[2] + t * c[4]) * s[n][m];
    final h = (c[3] + t * c[5]) * s[n][m];
    final ar = math.pow(_a / r, n + 2).toDouble();
    final cm = math.cos(m * lon), sm = math.sin(m * lon);
    final t1 = g * cm + h * sm;
    final t2 = g * sm - h * cm;
    br += (n + 1) * ar * t1 * pnm[n][m];
    bt -= ar * t1 * dp[n][m];
    bp += m * ar * t2 * pnm[n][m];
  }
  bp = st.abs() < 1e-10 ? 0 : bp / st;

  // Spherical (north = -bt, east = bp, down = -br) -> geodetic frame.
  final xs = -bt, ys = bp, zs = -br;
  final psi = latC - lat;
  final x = xs * math.cos(psi) - zs * math.sin(psi);
  final zz = xs * math.sin(psi) + zs * math.cos(psi);
  final y = ys;
  final hH = math.sqrt(x * x + y * y);
  return MagneticField(
    declinationDeg: math.atan2(y, x) / d2r,
    inclinationDeg: math.atan2(zz, hH) / d2r,
    x: x, y: y, z: zz,
  );
}

/// Declination (true = magnetic + declination) at a place and time.
double declinationDeg(double latDeg, double lonDeg, DateTime utc) =>
    magneticField(latDeg, lonDeg, decimalYear: decimalYear(utc)).declinationDeg;

double decimalYear(DateTime utc) {
  final u = utc.toUtc();
  final start = DateTime.utc(u.year);
  final end = DateTime.utc(u.year + 1);
  return u.year + u.difference(start).inSeconds / end.difference(start).inSeconds;
}
