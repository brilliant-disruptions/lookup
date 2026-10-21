/// Celestrak OMM (JSON) record → [GpElements].
///
/// We use JSON rather than TLE because Celestrak now issues 6-digit catalog
/// numbers (e.g. new Starlink batches) that do not fit the TLE format.
library;

import 'package:satellite_observer/satellite_observer.dart';

class OmmRecord {
  OmmRecord._(this.json);

  final Map<String, Object?> json;

  factory OmmRecord.fromJson(Map<String, Object?> j) => OmmRecord._(j);

  String get objectName => json['OBJECT_NAME'] as String? ?? '';

  /// International designator, e.g. `2026-232AC`.
  String get objectId => json['OBJECT_ID'] as String? ?? '';

  /// Launch key: the designator without the piece letters, e.g. `2026-232`.
  String get launchKey {
    final id = objectId;
    return id.length >= 8 ? id.substring(0, 8) : id;
  }

  int get noradCatId => (json['NORAD_CAT_ID'] as num?)?.toInt() ?? 0;
  DateTime get epoch => DateTime.parse('${json['EPOCH']}Z').toUtc();
  double get meanMotion => (json['MEAN_MOTION'] as num).toDouble();
  double get eccentricity => (json['ECCENTRICITY'] as num).toDouble();
  double get inclination => (json['INCLINATION'] as num).toDouble();
  double get raan => (json['RA_OF_ASC_NODE'] as num).toDouble();
  double get argOfPericenter => (json['ARG_OF_PERICENTER'] as num).toDouble();
  double get meanAnomaly => (json['MEAN_ANOMALY'] as num).toDouble();
  double get bstar => (json['BSTAR'] as num?)?.toDouble() ?? 0;
  double get meanMotionDot => (json['MEAN_MOTION_DOT'] as num?)?.toDouble() ?? 0;
  double get meanMotionDdot =>
      (json['MEAN_MOTION_DDOT'] as num?)?.toDouble() ?? 0;
  int get revAtEpoch => (json['REV_AT_EPOCH'] as num?)?.toInt() ?? 0;
  String get dataSource => json['DATA_SOURCE'] as String? ?? '';

  /// Approximate orbital period.
  Duration get period =>
      Duration(microseconds: (86400e6 / meanMotion).round());

  bool isStale(DateTime now, {Duration maxAge = const Duration(days: 5)}) =>
      now.toUtc().difference(epoch) > maxAge;

  GpElements toElements() => GpElements.fromMeanElements(
        epoch: epoch,
        inclinationDeg: inclination,
        raanDeg: raan,
        eccentricity: eccentricity,
        argPerigeeDeg: argOfPericenter,
        meanAnomalyDeg: meanAnomaly,
        meanMotionRevPerDay: meanMotion,
        bStar: bstar,
        meanMotionDotRevPerDay2: meanMotionDot,
        meanMotionDdotRevPerDay3: meanMotionDdot,
        name: objectName,
      );

  static List<OmmRecord> listFromJson(Object? decoded) {
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map) OmmRecord.fromJson(e.cast<String, Object?>()),
    ];
  }
}

/// Well-known catalog numbers.
abstract final class Norad {
  static const iss = 25544;
  static const tiangong = 48274;
}
