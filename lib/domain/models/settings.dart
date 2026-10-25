/// User settings. Persisted as JSON by the data layer.
library;

class QuietHours {
  const QuietHours({required this.startMinute, required this.endMinute});

  /// Minutes after local midnight. Default 23:00 → 05:30.
  final int startMinute;
  final int endMinute;

  static const defaults = QuietHours(startMinute: 23 * 60, endMinute: 5 * 60 + 30);

  /// Whether [localMinuteOfDay] falls inside the quiet window (handles
  /// windows that wrap past midnight).
  bool contains(int localMinuteOfDay) {
    if (startMinute == endMinute) return false;
    if (startMinute < endMinute) {
      return localMinuteOfDay >= startMinute && localMinuteOfDay < endMinute;
    }
    return localMinuteOfDay >= startMinute || localMinuteOfDay < endMinute;
  }

  Map<String, Object?> toJson() => {'start': startMinute, 'end': endMinute};
  factory QuietHours.fromJson(Map<String, Object?> j) => QuietHours(
        startMinute: j['start'] as int,
        endMinute: j['end'] as int,
      );
}

enum LocationMode { auto, pinned }

class LookUpSettings {
  const LookUpSettings({
    this.latitude,
    this.longitude,
    this.locationMode = LocationMode.auto,
    this.placeName,
    this.issEnabled = true,
    this.starlinkEnabled = true,
    this.auroraEnabled = true,
    this.tiangongEnabled = false,
    this.meteorsEnabled = true,
    this.eclipsesEnabled = true,
    this.pairingsEnabled = true,
    this.launchesEnabled = true,
    this.transitsEnabled = true,
    this.nightVision = false,
    this.leadMinutes = 10,
    this.goNowNudge = true,
    this.quietHours = QuietHours.defaults,
    this.auroraWakeMe = false,
    this.clearSkyOnly = true,
    this.maxAlertsPerNight = 2,
    this.isPlus = false,
    this.minIssPeakElevationDeg = 25,
    this.minStarlinkPeakElevationDeg = 20,
    this.onboarded = false,
  });

  final double? latitude;
  final double? longitude;
  final LocationMode locationMode;
  final String? placeName;
  final bool issEnabled;
  final bool starlinkEnabled;
  final bool auroraEnabled;
  final bool tiangongEnabled;
  final bool meteorsEnabled;
  final bool eclipsesEnabled;
  final bool pairingsEnabled;
  final bool launchesEnabled;

  /// List ISS transits of the Sun and Moon (never pushed).
  final bool transitsEnabled;

  /// Red-on-black UI that keeps eyes dark-adapted outdoors.
  final bool nightVision;
  final int leadMinutes;
  final bool goNowNudge;
  final QuietHours quietHours;
  final bool auroraWakeMe;
  final bool clearSkyOnly;
  final int maxAlertsPerNight;
  final bool isPlus;
  final double minIssPeakElevationDeg;
  final double minStarlinkPeakElevationDeg;
  final bool onboarded;

  bool get hasLocation => latitude != null && longitude != null;

  /// Cloud cover above which an event is "cloudy" (suppressed when
  /// [clearSkyOnly]).
  static const cloudyThresholdPercent = 60;

  LookUpSettings copyWith({
    double? latitude,
    double? longitude,
    LocationMode? locationMode,
    String? placeName,
    bool? issEnabled,
    bool? starlinkEnabled,
    bool? auroraEnabled,
    bool? tiangongEnabled,
    bool? meteorsEnabled,
    bool? eclipsesEnabled,
    bool? pairingsEnabled,
    bool? launchesEnabled,
    bool? transitsEnabled,
    bool? nightVision,
    int? leadMinutes,
    bool? goNowNudge,
    QuietHours? quietHours,
    bool? auroraWakeMe,
    bool? clearSkyOnly,
    int? maxAlertsPerNight,
    bool? isPlus,
    double? minIssPeakElevationDeg,
    double? minStarlinkPeakElevationDeg,
    bool? onboarded,
  }) =>
      LookUpSettings(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        locationMode: locationMode ?? this.locationMode,
        placeName: placeName ?? this.placeName,
        issEnabled: issEnabled ?? this.issEnabled,
        starlinkEnabled: starlinkEnabled ?? this.starlinkEnabled,
        auroraEnabled: auroraEnabled ?? this.auroraEnabled,
        tiangongEnabled: tiangongEnabled ?? this.tiangongEnabled,
        meteorsEnabled: meteorsEnabled ?? this.meteorsEnabled,
        eclipsesEnabled: eclipsesEnabled ?? this.eclipsesEnabled,
        pairingsEnabled: pairingsEnabled ?? this.pairingsEnabled,
        launchesEnabled: launchesEnabled ?? this.launchesEnabled,
        transitsEnabled: transitsEnabled ?? this.transitsEnabled,
        nightVision: nightVision ?? this.nightVision,
        leadMinutes: leadMinutes ?? this.leadMinutes,
        goNowNudge: goNowNudge ?? this.goNowNudge,
        quietHours: quietHours ?? this.quietHours,
        auroraWakeMe: auroraWakeMe ?? this.auroraWakeMe,
        clearSkyOnly: clearSkyOnly ?? this.clearSkyOnly,
        maxAlertsPerNight: maxAlertsPerNight ?? this.maxAlertsPerNight,
        isPlus: isPlus ?? this.isPlus,
        minIssPeakElevationDeg:
            minIssPeakElevationDeg ?? this.minIssPeakElevationDeg,
        minStarlinkPeakElevationDeg:
            minStarlinkPeakElevationDeg ?? this.minStarlinkPeakElevationDeg,
        onboarded: onboarded ?? this.onboarded,
      );

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'locationMode': locationMode.name,
        'placeName': placeName,
        'issEnabled': issEnabled,
        'starlinkEnabled': starlinkEnabled,
        'auroraEnabled': auroraEnabled,
        'tiangongEnabled': tiangongEnabled,
        'meteorsEnabled': meteorsEnabled,
        'eclipsesEnabled': eclipsesEnabled,
        'pairingsEnabled': pairingsEnabled,
        'launchesEnabled': launchesEnabled,
        'transitsEnabled': transitsEnabled,
        'nightVision': nightVision,
        'leadMinutes': leadMinutes,
        'goNowNudge': goNowNudge,
        'quietHours': quietHours.toJson(),
        'auroraWakeMe': auroraWakeMe,
        'clearSkyOnly': clearSkyOnly,
        'maxAlertsPerNight': maxAlertsPerNight,
        'isPlus': isPlus,
        'minIssPeakElevationDeg': minIssPeakElevationDeg,
        'minStarlinkPeakElevationDeg': minStarlinkPeakElevationDeg,
        'onboarded': onboarded,
      };

  factory LookUpSettings.fromJson(Map<String, Object?> j) {
    const d = LookUpSettings();
    return LookUpSettings(
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      locationMode: LocationMode.values.byName(
          j['locationMode'] as String? ?? LocationMode.auto.name),
      placeName: j['placeName'] as String?,
      issEnabled: j['issEnabled'] as bool? ?? d.issEnabled,
      starlinkEnabled: j['starlinkEnabled'] as bool? ?? d.starlinkEnabled,
      auroraEnabled: j['auroraEnabled'] as bool? ?? d.auroraEnabled,
      tiangongEnabled: j['tiangongEnabled'] as bool? ?? d.tiangongEnabled,
      meteorsEnabled: j['meteorsEnabled'] as bool? ?? d.meteorsEnabled,
      eclipsesEnabled: j['eclipsesEnabled'] as bool? ?? d.eclipsesEnabled,
      pairingsEnabled: j['pairingsEnabled'] as bool? ?? d.pairingsEnabled,
      launchesEnabled: j['launchesEnabled'] as bool? ?? d.launchesEnabled,
      transitsEnabled: j['transitsEnabled'] as bool? ?? d.transitsEnabled,
      nightVision: j['nightVision'] as bool? ?? d.nightVision,
      leadMinutes: j['leadMinutes'] as int? ?? d.leadMinutes,
      goNowNudge: j['goNowNudge'] as bool? ?? d.goNowNudge,
      quietHours: j['quietHours'] is Map
          ? QuietHours.fromJson((j['quietHours'] as Map).cast())
          : QuietHours.defaults,
      auroraWakeMe: j['auroraWakeMe'] as bool? ?? d.auroraWakeMe,
      clearSkyOnly: j['clearSkyOnly'] as bool? ?? d.clearSkyOnly,
      maxAlertsPerNight: j['maxAlertsPerNight'] as int? ?? d.maxAlertsPerNight,
      isPlus: j['isPlus'] as bool? ?? d.isPlus,
      minIssPeakElevationDeg: (j['minIssPeakElevationDeg'] as num?)?.toDouble() ??
          d.minIssPeakElevationDeg,
      minStarlinkPeakElevationDeg:
          (j['minStarlinkPeakElevationDeg'] as num?)?.toDouble() ??
              d.minStarlinkPeakElevationDeg,
      onboarded: j['onboarded'] as bool? ?? d.onboarded,
    );
  }
}
