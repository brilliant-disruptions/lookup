/// Core domain model: one thing worth stepping outside for.
///
/// Pure Dart. No Flutter imports anywhere under `lib/domain/`.
library;

enum SkyEventType {
  iss('ISS flyover', plusOnly: false),
  tiangong('Tiangong flyover', plusOnly: true),
  starlinkTrain('Starlink train', plusOnly: true),
  auroraNow('Aurora now', plusOnly: true),
  auroraOutlook('Aurora possible tonight', plusOnly: false, pushes: false),
  meteorShower('Meteor shower', plusOnly: false),
  lunarEclipse('Lunar eclipse', plusOnly: false),
  planetPairing('Planet pairing', plusOnly: false),
  rocketLaunch('Rocket launch', plusOnly: true),
  issTransit('ISS transit', plusOnly: false, pushes: false),
  planetHighlight('Planet highlight', plusOnly: false),

  /// A planet, star, constellation or showpiece opened from the Sky tab:
  /// not an event, but the finder and sheets speak [SkyEvent].
  skyObject('Sky object', plusOnly: false, pushes: false),
  satellitePass('Satellite pass', plusOnly: false, pushes: false),

  /// Something they follow (a planet, the Moon, a constellation, a
  /// showpiece) at its best on a clear night.
  favourite('Favourite at its best', plusOnly: true),

  /// Clear and moonless at a dark place with the Milky Way up.
  milkyWayNight('Milky Way night', plusOnly: true);

  const SkyEventType(this.label, {required this.plusOnly, this.pushes = true});

  /// Human label used in notifications and lists.
  final String label;

  /// Whether alerts for this type require LookUp+. The event itself is always
  /// visible on the Upcoming screen; only the *tap* is gated.
  final bool plusOnly;

  /// False for things we list but never alert on: the aurora outlook,
  /// sub-second transits (photographers plan those) and the "satellites
  /// tonight" list.
  final bool pushes;
}

/// A sky event at the user's location. All instants are UTC.
class SkyEvent {
  SkyEvent({
    required this.id,
    required this.type,
    required this.start,
    required this.peak,
    required this.end,
    required this.peakElevationDeg,
    required this.riseAzimuthDeg,
    required this.peakAzimuthDeg,
    required this.setAzimuthDeg,
    this.cloudCoverPercent,
    this.isEstimate = false,
    this.details = const {},
  })  : assert(!start.isAfter(peak) && !peak.isAfter(end)),
        assert(start.isUtc && peak.isUtc && end.isUtc);

  /// Stable key, e.g. `iss:2026-10-21T01:23Z`. Used to derive notification ids
  /// so a re-plan never double-fires.
  final String id;
  final SkyEventType type;
  final DateTime start;
  final DateTime peak;
  final DateTime end;
  final double peakElevationDeg;
  final double riseAzimuthDeg;
  final double peakAzimuthDeg;
  final double setAzimuthDeg;

  /// Forecast cloud cover at [peak], 0–100, or null when unknown.
  final int? cloudCoverPercent;

  /// True when the underlying elements are stale (> 5 days). Suppresses the
  /// go-now nudge and adds a hedge to the copy.
  final bool isEstimate;

  /// Type-specific extras (satellite count, Kp, brightness word, ...).
  final Map<String, Object?> details;

  Duration get duration => end.difference(start);
  bool get plusOnly => type.plusOnly;

  /// Higher is better. Peak elevation × visible seconds × clear-sky factor.
  double get score {
    final clear = 1 - (cloudCoverPercent ?? 0) / 100;
    return peakElevationDeg * duration.inSeconds * clear;
  }

  SkyEvent copyWith({
    int? cloudCoverPercent,
    bool? isEstimate,
    Map<String, Object?>? details,
  }) =>
      SkyEvent(
        id: id,
        type: type,
        start: start,
        peak: peak,
        end: end,
        peakElevationDeg: peakElevationDeg,
        riseAzimuthDeg: riseAzimuthDeg,
        peakAzimuthDeg: peakAzimuthDeg,
        setAzimuthDeg: setAzimuthDeg,
        cloudCoverPercent: cloudCoverPercent ?? this.cloudCoverPercent,
        isEstimate: isEstimate ?? this.isEstimate,
        details: details ?? this.details,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'start': start.toIso8601String(),
        'peak': peak.toIso8601String(),
        'end': end.toIso8601String(),
        'peakElevationDeg': peakElevationDeg,
        'riseAzimuthDeg': riseAzimuthDeg,
        'peakAzimuthDeg': peakAzimuthDeg,
        'setAzimuthDeg': setAzimuthDeg,
        'cloudCoverPercent': cloudCoverPercent,
        'isEstimate': isEstimate,
        'details': details,
      };

  factory SkyEvent.fromJson(Map<String, Object?> j) => SkyEvent(
        id: j['id'] as String,
        type: SkyEventType.values.byName(j['type'] as String),
        start: DateTime.parse(j['start'] as String).toUtc(),
        peak: DateTime.parse(j['peak'] as String).toUtc(),
        end: DateTime.parse(j['end'] as String).toUtc(),
        peakElevationDeg: (j['peakElevationDeg'] as num).toDouble(),
        riseAzimuthDeg: (j['riseAzimuthDeg'] as num).toDouble(),
        peakAzimuthDeg: (j['peakAzimuthDeg'] as num).toDouble(),
        setAzimuthDeg: (j['setAzimuthDeg'] as num).toDouble(),
        cloudCoverPercent: (j['cloudCoverPercent'] as num?)?.toInt(),
        isEstimate: j['isEstimate'] as bool? ?? false,
        details: (j['details'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  @override
  String toString() => 'SkyEvent($id peak=${peak.toIso8601String()} '
      'el=${peakElevationDeg.toStringAsFixed(0)} clouds=$cloudCoverPercent)';
}
