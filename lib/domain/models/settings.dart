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
    this.seenNearby = false,
    this.tiangongEnabled = false,
    this.meteorsEnabled = true,
    this.eclipsesEnabled = true,
    this.pairingsEnabled = true,
    this.occultationsEnabled = true,
    this.rareEventsEnabled = true,
    this.launchesEnabled = true,
    this.moonriseEnabled = true,
    this.moonPhasesEnabled = true,
    this.transitsEnabled = true,
    this.nightVision = true,
    this.nightVisionFollowsLight = true,
    this.nightVisionNudge = 0,
    this.nightVisionLevel = 1,
    this.plusCardSnoozedUntil,
    this.leadMinutes = 10,
    this.goNowNudge = true,
    this.quietHours = QuietHours.defaults,
    this.auroraWakeMe = false,
    this.clearSkyOnly = true,
    this.maxAlertsPerNight = 2,
    this.isPlus = false,
    this.plusUntil,
    this.plusSeenAt,
    this.plusDoubtAt,
    this.minIssPeakElevationDeg = 25,
    this.minStarlinkPeakElevationDeg = 20,
    this.onboarded = false,
    this.places = const [],
    this.skyDarkness = SkyDarkness.suburbs,
    this.favourites = const [],
    this.toured = false,
    this.pipCoached = false,
    this.skyCameraCoached = false,
    this.skyFigures = true,
    this.onboardedAt,
    this.proNudgeAt,
    this.proNudgeNotNow = 0,
    this.reviewAskedAt,
    this.reviewAsks = 0,
    this.weekAhead = true,
    this.alertsPaused = false,
    this.plusDeclines = 0,
    this.trialOfferShown = false,
    this.missedItId,
    this.missedItAt,
    this.photoCaption = true,
    this.firstBadgeShown = false,
    this.nerdMode = false,
    this.miles,
  });

  final double? latitude;
  final double? longitude;
  final LocationMode locationMode;
  final String? placeName;
  final bool issEnabled;
  final bool starlinkEnabled;
  final bool auroraEnabled;

  /// Seen near you: send anonymous "I can see it" reports and hear when
  /// people nearby see the aurora (docs/seen-near-you.md). Off until asked.
  final bool seenNearby;
  final bool tiangongEnabled;
  final bool meteorsEnabled;
  final bool eclipsesEnabled;
  final bool pairingsEnabled;

  /// The Moon covering a bright star or planet (LookUp+).
  final bool occultationsEnabled;

  /// Bright comets (LookUp+) and novae from the curated list.
  final bool rareEventsEnabled;
  final bool launchesEnabled;

  /// Full-Moon moonrises (supermoons included).
  final bool moonriseEnabled;

  /// First and last quarter Moons, on nights they can be seen.
  final bool moonPhasesEnabled;

  /// List ISS transits of the Sun and Moon (never pushed).
  final bool transitsEnabled;

  /// Red-on-black UI from sunset to sunrise, so eyes stay dark-adapted
  /// outdoors.
  final bool nightVision;

  /// Auto: the red follows the light around the phone, like Auto-Brightness
  /// (true colours in a lit room, full red outside in the dark).
  final bool nightVisionFollowsLight;

  /// How far "How red" moved Auto up or down (−1…1); Auto carries on
  /// following the light from there.
  final double nightVisionNudge;

  /// The fixed red (0–1) when Auto is off.
  final double nightVisionLevel;

  /// "Not now" on Tonight's LookUp+ card hides it until then (UTC).
  final DateTime? plusCardSnoozedUntil;
  final int leadMinutes;
  final bool goNowNudge;
  final QuietHours quietHours;
  final bool auroraWakeMe;
  final bool clearSkyOnly;
  final int maxAlertsPerNight;
  final bool isPlus;

  /// When the paid period the store last vouched for ends. Null when the
  /// store gave no date, and for a LookUp+ saved before this was recorded.
  /// The rules are in domain/plus/plus_grant.dart.
  final DateTime? plusUntil;

  /// When the store last vouched for LookUp+ on this phone.
  final DateTime? plusSeenAt;

  /// When the store first answered "nothing owned" while LookUp+ was still
  /// believed here; cleared when it vouches again. The doubt
  /// ([PlusGrant.doubt]) runs from this.
  final DateTime? plusDoubtAt;
  final double minIssPeakElevationDeg;
  final double minStarlinkPeakElevationDeg;
  final bool onboarded;

  /// When onboarding finished: the "Looked up" badge's date.
  final DateTime? onboardedAt;

  /// When the caught-it screen last mentioned the Pro camera, and how many
  /// times they've said "Not now" (`domain/plus/pro_nudge.dart`).
  final DateTime? proNudgeAt;
  final int proNudgeNotNow;

  /// When LookUp last asked for a rating, and how many times ever
  /// (`domain/log/review_ask.dart`).
  final DateTime? reviewAskedAt;
  final int reviewAsks;

  /// The once-a-week "Your week ahead" note (`domain/scheduling/week_ahead.dart`).
  final bool weekAhead;

  /// Every tap off at once (a holiday, exams, a new baby) without touching
  /// what they've chosen to hear about. Nothing is scheduled while it's on.
  final bool alertsPaused;

  /// Soft LookUp+ asks turned down ("Not now", or the offer closed without
  /// a trial). Two and they stop (domain/plus/nudges.dart).
  final int plusDeclines;

  /// The one-time trial offer at the end of onboarding has been shown.
  final bool trialOfferShown;

  /// The last "You missed it" (domain/plus/missed_it.dart): which, and when.
  final String? missedItId;
  final DateTime? missedItAt;

  /// The "LookUp" caption along the foot of photos. Only LookUp+ can turn
  /// it off ([PlusFeature.noCaption]).
  final bool photoCaption;

  /// The first badge has had its moment on screen (once, after onboarding).
  final bool firstBadgeShown;

  /// Nerd mode: the numbers (degrees, magnitudes, coordinates) shown beside
  /// the words. Off by default; the main path always speaks in words.
  final bool nerdMode;

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

  /// Seen the finder's one-time hint: bring Pip into the ring.
  final bool pipCoached;

  /// Seen the sky camera's one-time hint: it draws through cloud, figure-8 if it drifts.
  final bool skyCameraCoached;

  /// Draw each constellation's picture behind its lines on the Sky tab.
  final bool skyFigures;

  /// Distances in miles rather than kilometres. Null until chosen: the app
  /// fills it from the phone's region (miles in the US and UK).
  final bool? miles;

  /// What to write distances in; kilometres when nothing says otherwise.
  bool get usesMiles => miles ?? false;

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
    bool? seenNearby,
    bool? tiangongEnabled,
    bool? meteorsEnabled,
    bool? eclipsesEnabled,
    bool? pairingsEnabled,
    bool? occultationsEnabled,
    bool? rareEventsEnabled,
    bool? launchesEnabled,
    bool? moonriseEnabled,
    bool? moonPhasesEnabled,
    bool? transitsEnabled,
    bool? nightVision,
    bool? nightVisionFollowsLight,
    double? nightVisionNudge,
    double? nightVisionLevel,
    DateTime? plusCardSnoozedUntil,
    int? leadMinutes,
    bool? goNowNudge,
    QuietHours? quietHours,
    bool? auroraWakeMe,
    bool? clearSkyOnly,
    int? maxAlertsPerNight,
    bool? isPlus,
    DateTime? plusUntil,
    bool forgetPlusUntil = false,
    DateTime? plusSeenAt,
    DateTime? plusDoubtAt,
    bool forgetPlusDoubt = false,
    double? minIssPeakElevationDeg,
    double? minStarlinkPeakElevationDeg,
    bool? onboarded,
    List<SavedPlace>? places,
    SkyDarkness? skyDarkness,
    List<String>? favourites,
    bool? toured,
    bool? pipCoached,
    bool? skyCameraCoached,
    bool? skyFigures,
    DateTime? onboardedAt,
    DateTime? proNudgeAt,
    int? proNudgeNotNow,
    DateTime? reviewAskedAt,
    int? reviewAsks,
    bool? weekAhead,
    bool? alertsPaused,
    int? plusDeclines,
    bool? trialOfferShown,
    String? missedItId,
    DateTime? missedItAt,
    bool? photoCaption,
    bool? firstBadgeShown,
    bool? nerdMode,
    bool? miles,
  }) =>
      LookUpSettings(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        locationMode: locationMode ?? this.locationMode,
        placeName: placeName ?? this.placeName,
        issEnabled: issEnabled ?? this.issEnabled,
        starlinkEnabled: starlinkEnabled ?? this.starlinkEnabled,
        auroraEnabled: auroraEnabled ?? this.auroraEnabled,
        seenNearby: seenNearby ?? this.seenNearby,
        tiangongEnabled: tiangongEnabled ?? this.tiangongEnabled,
        meteorsEnabled: meteorsEnabled ?? this.meteorsEnabled,
        eclipsesEnabled: eclipsesEnabled ?? this.eclipsesEnabled,
        pairingsEnabled: pairingsEnabled ?? this.pairingsEnabled,
        occultationsEnabled: occultationsEnabled ?? this.occultationsEnabled,
        rareEventsEnabled: rareEventsEnabled ?? this.rareEventsEnabled,
        launchesEnabled: launchesEnabled ?? this.launchesEnabled,
        moonriseEnabled: moonriseEnabled ?? this.moonriseEnabled,
        moonPhasesEnabled: moonPhasesEnabled ?? this.moonPhasesEnabled,
        transitsEnabled: transitsEnabled ?? this.transitsEnabled,
        nightVision: nightVision ?? this.nightVision,
        nightVisionFollowsLight: nightVisionFollowsLight ?? this.nightVisionFollowsLight,
        nightVisionNudge: nightVisionNudge ?? this.nightVisionNudge,
        nightVisionLevel: nightVisionLevel ?? this.nightVisionLevel,
        plusCardSnoozedUntil: plusCardSnoozedUntil ?? this.plusCardSnoozedUntil,
        leadMinutes: leadMinutes ?? this.leadMinutes,
        goNowNudge: goNowNudge ?? this.goNowNudge,
        quietHours: quietHours ?? this.quietHours,
        auroraWakeMe: auroraWakeMe ?? this.auroraWakeMe,
        clearSkyOnly: clearSkyOnly ?? this.clearSkyOnly,
        maxAlertsPerNight: maxAlertsPerNight ?? this.maxAlertsPerNight,
        isPlus: isPlus ?? this.isPlus,
        plusUntil: forgetPlusUntil ? null : plusUntil ?? this.plusUntil,
        plusSeenAt: plusSeenAt ?? this.plusSeenAt,
        plusDoubtAt: forgetPlusDoubt ? null : plusDoubtAt ?? this.plusDoubtAt,
        minIssPeakElevationDeg:
            minIssPeakElevationDeg ?? this.minIssPeakElevationDeg,
        minStarlinkPeakElevationDeg:
            minStarlinkPeakElevationDeg ?? this.minStarlinkPeakElevationDeg,
        onboarded: onboarded ?? this.onboarded,
        places: places ?? this.places,
        skyDarkness: skyDarkness ?? this.skyDarkness,
        favourites: favourites ?? this.favourites,
        toured: toured ?? this.toured,
        pipCoached: pipCoached ?? this.pipCoached,
        skyCameraCoached: skyCameraCoached ?? this.skyCameraCoached,
        skyFigures: skyFigures ?? this.skyFigures,
        onboardedAt: onboardedAt ?? this.onboardedAt,
        proNudgeAt: proNudgeAt ?? this.proNudgeAt,
        proNudgeNotNow: proNudgeNotNow ?? this.proNudgeNotNow,
        reviewAskedAt: reviewAskedAt ?? this.reviewAskedAt,
        reviewAsks: reviewAsks ?? this.reviewAsks,
        weekAhead: weekAhead ?? this.weekAhead,
        alertsPaused: alertsPaused ?? this.alertsPaused,
        plusDeclines: plusDeclines ?? this.plusDeclines,
        trialOfferShown: trialOfferShown ?? this.trialOfferShown,
        missedItId: missedItId ?? this.missedItId,
        missedItAt: missedItAt ?? this.missedItAt,
        photoCaption: photoCaption ?? this.photoCaption,
        firstBadgeShown: firstBadgeShown ?? this.firstBadgeShown,
        nerdMode: nerdMode ?? this.nerdMode,
        miles: miles ?? this.miles,
      );

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'locationMode': locationMode.name,
        'placeName': placeName,
        'issEnabled': issEnabled,
        'starlinkEnabled': starlinkEnabled,
        'auroraEnabled': auroraEnabled,
        'seenNearby': seenNearby,
        'tiangongEnabled': tiangongEnabled,
        'meteorsEnabled': meteorsEnabled,
        'eclipsesEnabled': eclipsesEnabled,
        'pairingsEnabled': pairingsEnabled,
        'occultationsEnabled': occultationsEnabled,
        'rareEventsEnabled': rareEventsEnabled,
        'launchesEnabled': launchesEnabled,
        'moonriseEnabled': moonriseEnabled,
        'moonPhasesEnabled': moonPhasesEnabled,
        'transitsEnabled': transitsEnabled,
        'nightVisionAfterSunset': nightVision,
        // New keys: the old 'nightVisionAuto' meant "red by itself outside".
        'redFollowsLight': nightVisionFollowsLight,
        'redNudge': nightVisionNudge,
        'redLevel': nightVisionLevel,
        if (plusCardSnoozedUntil != null) 'plusCardSnoozedUntil': plusCardSnoozedUntil!.toIso8601String(),
        'leadMinutes': leadMinutes,
        'goNowNudge': goNowNudge,
        'quietHours': quietHours.toJson(),
        'auroraWakeMe': auroraWakeMe,
        'clearSkyOnly': clearSkyOnly,
        'maxAlertsPerNight': maxAlertsPerNight,
        'isPlus': isPlus,
        if (plusUntil != null) 'plusUntil': plusUntil!.toIso8601String(),
        if (plusSeenAt != null) 'plusSeenAt': plusSeenAt!.toIso8601String(),
        if (plusDoubtAt != null) 'plusDoubtAt': plusDoubtAt!.toIso8601String(),
        'minIssPeakElevationDeg': minIssPeakElevationDeg,
        'minStarlinkPeakElevationDeg': minStarlinkPeakElevationDeg,
        'onboarded': onboarded,
        'places': [for (final p in places) p.toJson()],
        'skyDarkness': skyDarkness.name,
        'favourites': favourites,
        'toured': toured,
        'pipCoached': pipCoached,
        'skyCameraCoached': skyCameraCoached,
        'skyFigures': skyFigures,
        if (onboardedAt != null) 'onboardedAt': onboardedAt!.toIso8601String(),
        if (proNudgeAt != null) 'proNudgeAt': proNudgeAt!.toIso8601String(),
        if (proNudgeNotNow > 0) 'proNudgeNotNow': proNudgeNotNow,
        if (reviewAskedAt != null) 'reviewAskedAt': reviewAskedAt!.toIso8601String(),
        if (reviewAsks > 0) 'reviewAsks': reviewAsks,
        if (!weekAhead) 'weekAhead': false,
        if (alertsPaused) 'alertsPaused': true,
        if (plusDeclines > 0) 'plusDeclines': plusDeclines,
        if (trialOfferShown) 'trialOfferShown': true,
        if (missedItId != null) 'missedItId': missedItId,
        if (missedItAt != null) 'missedItAt': missedItAt!.toIso8601String(),
        if (!photoCaption) 'photoCaption': false,
        'firstBadgeShown': firstBadgeShown,
        'nerdMode': nerdMode,
        if (miles != null) 'miles': miles,
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
      seenNearby: j['seenNearby'] as bool? ?? d.seenNearby,
      tiangongEnabled: j['tiangongEnabled'] as bool? ?? d.tiangongEnabled,
      meteorsEnabled: j['meteorsEnabled'] as bool? ?? d.meteorsEnabled,
      eclipsesEnabled: j['eclipsesEnabled'] as bool? ?? d.eclipsesEnabled,
      pairingsEnabled: j['pairingsEnabled'] as bool? ?? d.pairingsEnabled,
      occultationsEnabled: j['occultationsEnabled'] as bool? ?? d.occultationsEnabled,
      rareEventsEnabled: j['rareEventsEnabled'] as bool? ?? d.rareEventsEnabled,
      launchesEnabled: j['launchesEnabled'] as bool? ?? d.launchesEnabled,
      moonriseEnabled: j['moonriseEnabled'] as bool? ?? d.moonriseEnabled,
      moonPhasesEnabled: j['moonPhasesEnabled'] as bool? ?? d.moonPhasesEnabled,
      transitsEnabled: j['transitsEnabled'] as bool? ?? d.transitsEnabled,
      // A new key: the old one-tap switch was off unless tapped, which says
      // nothing about wanting red after dark, so everyone starts with it on.
      nightVision: j['nightVisionAfterSunset'] as bool? ?? d.nightVision,
      nightVisionFollowsLight: j['redFollowsLight'] as bool? ?? d.nightVisionFollowsLight,
      nightVisionNudge: (j['redNudge'] as num?)?.toDouble().clamp(-1.0, 1.0) ?? d.nightVisionNudge,
      nightVisionLevel: (j['redLevel'] as num?)?.toDouble().clamp(0.0, 1.0) ?? d.nightVisionLevel,
      plusCardSnoozedUntil: DateTime.tryParse(j['plusCardSnoozedUntil'] as String? ?? '')?.toUtc(),
      leadMinutes: j['leadMinutes'] as int? ?? d.leadMinutes,
      goNowNudge: j['goNowNudge'] as bool? ?? d.goNowNudge,
      quietHours: j['quietHours'] is Map
          ? QuietHours.fromJson((j['quietHours'] as Map).cast())
          : QuietHours.defaults,
      auroraWakeMe: j['auroraWakeMe'] as bool? ?? d.auroraWakeMe,
      clearSkyOnly: j['clearSkyOnly'] as bool? ?? d.clearSkyOnly,
      maxAlertsPerNight: j['maxAlertsPerNight'] as int? ?? d.maxAlertsPerNight,
      isPlus: j['isPlus'] as bool? ?? d.isPlus,
      plusUntil: DateTime.tryParse(j['plusUntil'] as String? ?? '')?.toUtc(),
      plusSeenAt: DateTime.tryParse(j['plusSeenAt'] as String? ?? '')?.toUtc(),
      plusDoubtAt: DateTime.tryParse(j['plusDoubtAt'] as String? ?? '')?.toUtc(),
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
      pipCoached: j['pipCoached'] as bool? ?? d.pipCoached,
      skyCameraCoached: j['skyCameraCoached'] as bool? ?? d.skyCameraCoached,
      skyFigures: j['skyFigures'] as bool? ?? d.skyFigures,
      onboardedAt: DateTime.tryParse(j['onboardedAt'] as String? ?? '')?.toUtc(),
      proNudgeAt: DateTime.tryParse(j['proNudgeAt'] as String? ?? '')?.toUtc(),
      proNudgeNotNow: (j['proNudgeNotNow'] as num?)?.toInt() ?? 0,
      reviewAskedAt: DateTime.tryParse(j['reviewAskedAt'] as String? ?? '')?.toUtc(),
      reviewAsks: (j['reviewAsks'] as num?)?.toInt() ?? 0,
      weekAhead: j['weekAhead'] as bool? ?? true,
      alertsPaused: j['alertsPaused'] as bool? ?? false,
      plusDeclines: (j['plusDeclines'] as num?)?.toInt() ?? 0,
      trialOfferShown: j['trialOfferShown'] as bool? ?? false,
      missedItId: j['missedItId'] as String?,
      missedItAt: DateTime.tryParse(j['missedItAt'] as String? ?? '')?.toUtc(),
      photoCaption: j['photoCaption'] as bool? ?? true,
      firstBadgeShown: j['firstBadgeShown'] as bool? ?? d.firstBadgeShown,
      nerdMode: j['nerdMode'] as bool? ?? d.nerdMode,
      miles: j['miles'] as bool?,
    );
  }
}
