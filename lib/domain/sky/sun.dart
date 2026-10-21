/// Low-precision solar position (Meeus / USNO approximation, ~0.01°).
/// More than enough to decide "is it dark enough".
library;

import 'dart:math' as math;

const _deg2rad = math.pi / 180;
const _rad2deg = 180 / math.pi;

double _norm360(double x) => ((x % 360) + 360) % 360;

/// Sun altitude above the horizon in degrees at [utc] for an observer.
double sunAltitudeDeg(DateTime utc, double latDeg, double lonDeg) {
  final jd = utc.toUtc().millisecondsSinceEpoch / 86400000.0 + 2440587.5;
  final n = jd - 2451545.0;
  final l = _norm360(280.460 + 0.9856474 * n);
  final g = _norm360(357.528 + 0.9856003 * n) * _deg2rad;
  final lambda =
      (l + 1.915 * math.sin(g) + 0.020 * math.sin(2 * g)) * _deg2rad;
  final eps = (23.439 - 0.0000004 * n) * _deg2rad;
  final ra = math.atan2(math.cos(eps) * math.sin(lambda), math.cos(lambda));
  final dec = math.asin(math.sin(eps) * math.sin(lambda));
  final gmstHours = (18.697374558 + 24.06570982441908 * n) % 24;
  final lstDeg = _norm360(gmstHours * 15 + lonDeg);
  final ha = (lstDeg - ra * _rad2deg) * _deg2rad;
  final lat = latDeg * _deg2rad;
  final sinAlt = math.sin(lat) * math.sin(dec) +
      math.cos(lat) * math.cos(dec) * math.cos(ha);
  return math.asin(sinAlt.clamp(-1.0, 1.0)) * _rad2deg;
}

/// Civil darkness: sun at least 6° below the horizon.
bool isDark(DateTime utc, double latDeg, double lonDeg,
        {double thresholdDeg = -6}) =>
    sunAltitudeDeg(utc, latDeg, lonDeg) <= thresholdDeg;

/// The next window of darkness starting at or after [from], searched hourly
/// up to [within]. Returns null if it never gets dark (polar summer).
({DateTime start, DateTime end})? nextDarkWindow(
  DateTime from,
  double latDeg,
  double lonDeg, {
  Duration within = const Duration(hours: 36),
  Duration step = const Duration(minutes: 10),
}) {
  DateTime? start;
  var t = from.toUtc();
  final limit = t.add(within);
  while (!t.isAfter(limit)) {
    final dark = isDark(t, latDeg, lonDeg);
    if (dark && start == null) start = t;
    if (!dark && start != null) return (start: start, end: t);
    t = t.add(step);
  }
  return start == null ? null : (start: start, end: limit);
}
