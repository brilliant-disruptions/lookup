/// Aurora rules: Kp needed for a latitude, tonight's outlook, and the
/// "it's happening now" gate.
library;

import '../sky/geomagnetic.dart';
import '../sky/sun.dart';

/// (Kp, minimum |geomagnetic latitude| at which aurora is typically visible
/// on the northern horizon). Linear between rows.
const _kpTable = <(double, double)>[
  (0, 67),
  (1, 65),
  (2, 63),
  (3, 61),
  (4, 58),
  (5, 55),
  (6, 52),
  (7, 48),
  (8, 45),
  (9, 40),
];

/// Kp index needed for aurora to be plausible at [geomagneticLatDeg].
/// Returns > 9 when it is effectively never visible there.
double kpNeededForGeomagneticLatitude(double geomagneticLatDeg) {
  final lat = geomagneticLatDeg.abs();
  if (lat >= _kpTable.first.$2) return 0;
  for (var i = 1; i < _kpTable.length; i++) {
    final (kpHi, latLo) = _kpTable[i];
    final (kpLo, latHi) = _kpTable[i - 1];
    if (lat >= latLo) {
      final f = (latHi - lat) / (latHi - latLo);
      return kpLo + f * (kpHi - kpLo);
    }
  }
  // Below 40° geomagnetic: extrapolate past 9 so callers can show "unlikely".
  return 9 + (40 - lat) / 5;
}

double kpNeededAt(double latDeg, double lonDeg) =>
    kpNeededForGeomagneticLatitude(geomagneticLatitudeDeg(latDeg, lonDeg));

class KpForecastPoint {
  const KpForecastPoint({required this.time, required this.kp, required this.kind});
  final DateTime time; // UTC, start of 3-hour bin
  final double kp;
  final String kind; // observed | estimated | predicted
}

enum AuroraOutlookLevel { none, slim, possible, likely }

class AuroraOutlook {
  const AuroraOutlook({
    required this.level,
    required this.maxKpTonight,
    required this.kpNeeded,
    this.window,
  });
  final AuroraOutlookLevel level;
  final double maxKpTonight;
  final double kpNeeded;
  final ({DateTime start, DateTime end})? window;

  String get headline => switch (level) {
        AuroraOutlookLevel.likely => 'Aurora likely tonight',
        AuroraOutlookLevel.possible => 'Aurora possible tonight',
        AuroraOutlookLevel.slim => 'Slim aurora chance tonight',
        AuroraOutlookLevel.none => 'No aurora expected tonight',
      };
}

/// Tonight's outlook from the 3-day Kp forecast.
AuroraOutlook auroraOutlook({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  required List<KpForecastPoint> forecast,
}) {
  final needed = kpNeededAt(latDeg, lonDeg);
  final window = nextDarkWindow(now, latDeg, lonDeg);
  if (window == null) {
    return AuroraOutlook(
        level: AuroraOutlookLevel.none, maxKpTonight: 0, kpNeeded: needed);
  }
  var maxKp = 0.0;
  for (final p in forecast) {
    final binEnd = p.time.add(const Duration(hours: 3));
    final overlaps = p.time.isBefore(window.end) && binEnd.isAfter(window.start);
    if (overlaps && p.kp > maxKp) maxKp = p.kp;
  }
  final margin = maxKp - needed;
  final level = margin >= 1
      ? AuroraOutlookLevel.likely
      : margin >= 0
          ? AuroraOutlookLevel.possible
          : margin >= -1
              ? AuroraOutlookLevel.slim
              : AuroraOutlookLevel.none;
  return AuroraOutlook(
      level: level, maxKpTonight: maxKp, kpNeeded: needed, window: window);
}

/// Probability (0–100) from NOAA's Ovation grid at the cell containing
/// [latDeg], [lonDeg]. The grid is `[lon 0..359, lat -90..90, p]`, lon-major.
int ovationProbabilityAt(List<dynamic> coordinates, double latDeg, double lonDeg) {
  final lon = ((lonDeg.round() % 360) + 360) % 360;
  final lat = latDeg.round().clamp(-90, 90);
  final idx = lon * 181 + (lat + 90);
  if (idx < coordinates.length) {
    final c = coordinates[idx];
    if (c is List && c.length >= 3 && c[0] == lon && c[1] == lat) {
      return (c[2] as num).round();
    }
  }
  // Layout differs from expectation: fall back to a linear scan.
  for (final c in coordinates) {
    if (c is List && c.length >= 3 && c[0] == lon && c[1] == lat) {
      return (c[2] as num).round();
    }
  }
  return 0;
}

class AuroraNowDecision {
  const AuroraNowDecision({required this.alert, required this.reason});
  final bool alert;
  final String reason;
}

/// Should we tap the user *right now*?
AuroraNowDecision auroraNow({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  required double estimatedKp,
  required int ovationProbability,
  int? cloudCoverPercent,
  int minProbability = 20,
  int cloudyThreshold = 60,
}) {
  if (!isDark(now, latDeg, lonDeg)) {
    return const AuroraNowDecision(alert: false, reason: 'not dark');
  }
  final needed = kpNeededAt(latDeg, lonDeg);
  if (estimatedKp < needed - 1) {
    return AuroraNowDecision(
        alert: false,
        reason: 'Kp ${estimatedKp.toStringAsFixed(1)} < needed '
            '${needed.toStringAsFixed(1)}');
  }
  if (ovationProbability < minProbability) {
    return AuroraNowDecision(
        alert: false, reason: 'ovation $ovationProbability% < $minProbability%');
  }
  if (cloudCoverPercent != null && cloudCoverPercent > cloudyThreshold) {
    return AuroraNowDecision(alert: false, reason: 'cloudy $cloudCoverPercent%');
  }
  return const AuroraNowDecision(alert: true, reason: 'go');
}
