/// User settings. Persisted as JSON by the data layer.
library;

import '../sky/visibility.dart';

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

/// A place the user saved: home, the cabin, a trip.
class SavedPlace {
  const SavedPlace({required this.name, required this.latitude, required this.longitude, this.skyDarkness});
  final String name;
  final double latitude;
  final double longitude;

  /// How dark the sky is there, if they've said (a dark-sky park vs home).
  final SkyDarkness? skyDarkness;

  bool sameSpot(double lat, double lon) => (latitude - lat).abs() < 1e-4 && (longitude - lon).abs() < 1e-4;

  SavedPlace withDarkness(SkyDarkness? d) => SavedPlace(name: name, latitude: latitude, longitude: longitude, skyDarkness: d);

  Map<String, Object?> toJson() => {'n': name, 'la': latitude, 'lo': longitude, if (skyDarkness != null) 'sky': skyDarkness!.name};
  factory SavedPlace.fromJson(Map<String, Object?> j) => SavedPlace(
        name: j['n'] as String? ?? '',
        latitude: (j['la'] as num).toDouble(),
        longitude: (j['lo'] as num).toDouble(),
        skyDarkness: SkyDarkness.values.where((d) => d.name == j['sky']).firstOrNull,
      );
}

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
    this.places = const [],
    this.skyDarkness = SkyDarkness.suburbs,
    this.favourites = const [],
    this.toured = false,
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

  /// Saved places to switch between. The active one is the pinned
  /// [latitude]/[longitude] when [locationMode] is pinned.
  final List<SavedPlace> places;

  /// How dark the sky is where they usually look (drives "can I see it").
  final SkyDarkness skyDarkness;

  /// Sky things they follow, by id ("planet:saturn", "moon", "con:Ori",
  /// showpiece ids). Never affects alerts.
  final List<String> favourites;

  /// Seen the spotlight tour (or skipped it).
  final bool toured;

  bool isFavourite(String id) => favourites.contains(id);

  LookUpSettings toggleFavourite(String id) =>
      copyWith(favourites: isFavourite(id) ? [for (final f in favourites) if (f != id) f] : [...favourites, id]);

  bool get hasLocation => latitude != null && longitude != null;

  /// Pin [p] as the active place (adding it to [places] if new).
  LookUpSettings usePlace(SavedPlace p) => copyWith(
        locationMode: LocationMode.pinned,
        latitude: p.latitude,
        longitude: p.longitude,
        placeName: p.name,
        places: places.any((x) => x.sameSpot(p.latitude, p.longitude)) ? places : [...places, p],
      );

  /// The saved place currently in use, if any.
  SavedPlace? get activePlace => locationMode == LocationMode.pinned && hasLocation
      ? places.where((p) => p.sameSpot(latitude!, longitude!)).firstOrNull
      : null;

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
    List<SavedPlace>? places,
    SkyDarkness? skyDarkness,
    List<String>? favourites,
    bool? toured,
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
        places: places ?? this.places,
        skyDarkness: skyDarkness ?? this.skyDarkness,
        favourites: favourites ?? this.favourites,
        toured: toured ?? this.toured,
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
        'places': [for (final p in places) p.toJson()],
        'skyDarkness': skyDarkness.name,
        'favourites': favourites,
        'toured': toured,
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
      places: [
        for (final p in (j['places'] as List? ?? const []))
          if (p is Map) SavedPlace.fromJson(p.cast<String, Object?>()),
      ],
      skyDarkness: SkyDarkness.values.where((d) => d.name == j['skyDarkness']).firstOrNull ?? d.skyDarkness,
      favourites: [for (final f in (j['favourites'] as List? ?? const [])) if (f is String) f],
      toured: j['toured'] as bool? ?? d.toured,
    );
  }
}
