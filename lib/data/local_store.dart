/// Everything persisted on-device. No PII leaves the phone in the MVP.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/aurora/aurora_rules.dart';
import '../domain/log/sighting.dart';
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/orbit/omm.dart';
import '../domain/weather/cloud_forecast.dart';

class CachedElements {
  const CachedElements({required this.fetchedAt, required this.records});
  final DateTime fetchedAt;
  final List<OmmRecord> records;
  bool isOlderThan(Duration d, DateTime now) =>
      now.toUtc().difference(fetchedAt) > d;
}

class AuroraSnapshot {
  const AuroraSnapshot({
    required this.fetchedAt,
    required this.kpNow,
    required this.forecast,
    required this.ovationProbability,
  });
  final DateTime fetchedAt;
  final double? kpNow;
  final List<KpForecastPoint> forecast;
  final int ovationProbability;

  Map<String, Object?> toJson() => {
        'fetchedAt': fetchedAt.toIso8601String(),
        'kpNow': kpNow,
        'ovation': ovationProbability,
        'forecast': [
          for (final p in forecast)
            {'t': p.time.toIso8601String(), 'kp': p.kp, 'k': p.kind},
        ],
      };

  factory AuroraSnapshot.fromJson(Map<String, Object?> j) => AuroraSnapshot(
        fetchedAt: DateTime.parse(j['fetchedAt'] as String).toUtc(),
        kpNow: (j['kpNow'] as num?)?.toDouble(),
        ovationProbability: (j['ovation'] as num?)?.toInt() ?? 0,
        forecast: [
          for (final e in (j['forecast'] as List? ?? const []))
            KpForecastPoint(
              time: DateTime.parse(e['t'] as String).toUtc(),
              kp: (e['kp'] as num).toDouble(),
              kind: e['k'] as String,
            ),
        ],
      );
}

class LocalStore {
  LocalStore([SharedPreferencesAsync? prefs])
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _kSettings = 'settings';
  static const _kEvents = 'events';
  static const _kRecent = 'recent_events';
  static const _kLaunches = 'launches';
  static const _kPlan = 'plan_ids';
  static const _kAurora = 'aurora';
  static const _kClouds = 'clouds';
  static const _kLastRefresh = 'last_refresh';
  static const _kFeedback = 'feedback';
  static const _kCrew = 'crew';
  static String _kElements(String key) => 'elements_$key';

  Future<LookUpSettings> loadSettings() async {
    final raw = await _prefs.getString(_kSettings);
    if (raw == null) return const LookUpSettings();
    try {
      return LookUpSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return const LookUpSettings();
    }
  }

  Future<void> saveSettings(LookUpSettings s) =>
      _prefs.setString(_kSettings, jsonEncode(s.toJson()));

  Future<CachedElements?> loadElements(String key) async {
    final raw = await _prefs.getString(_kElements(key));
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      return CachedElements(
        fetchedAt: DateTime.parse(j['fetchedAt'] as String).toUtc(),
        records: OmmRecord.listFromJson(j['records']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveElements(
          String key, List<OmmRecord> records, DateTime fetchedAt) =>
      _prefs.setString(
          _kElements(key),
          jsonEncode({
            'fetchedAt': fetchedAt.toUtc().toIso8601String(),
            'records': [for (final r in records) r.json],
          }));

  Future<CloudForecast?> loadClouds() async {
    final raw = await _prefs.getString(_kClouds);
    if (raw == null) return null;
    try {
      return CloudForecast.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveClouds(CloudForecast f) =>
      _prefs.setString(_kClouds, jsonEncode(f.toJson()));

  /// Forecasts for other places (saved places, "where to go"), one per
  /// ~10 km square so nearby spots share a copy.
  static String placeCloudsKey(double lat, double lon) =>
      'clouds_at_${lat.toStringAsFixed(1)}_${lon.toStringAsFixed(1)}';

  Future<CloudForecast?> loadPlaceClouds(double lat, double lon) async {
    final raw = await _prefs.getString(placeCloudsKey(lat, lon));
    if (raw == null) return null;
    try {
      return CloudForecast.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  Future<void> savePlaceClouds(CloudForecast f) =>
      _prefs.setString(placeCloudsKey(f.latitude, f.longitude), jsonEncode(f.toJson()));

  Future<AuroraSnapshot?> loadAurora() async {
    final raw = await _prefs.getString(_kAurora);
    if (raw == null) return null;
    try {
      return AuroraSnapshot.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAurora(AuroraSnapshot a) =>
      _prefs.setString(_kAurora, jsonEncode(a.toJson()));

  Future<List<SkyEvent>> loadEvents() async {
    final raw = await _prefs.getString(_kEvents);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          SkyEvent.fromJson((e as Map).cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveEvents(List<SkyEvent> events) => _prefs.setString(
      _kEvents, jsonEncode([for (final e in events) e.toJson()]));

  Future<List<SkyEvent>> loadRecent() async {
    final raw = await _prefs.getString(_kRecent);
    if (raw == null) return const [];
    try {
      return [for (final e in jsonDecode(raw) as List) SkyEvent.fromJson((e as Map).cast<String, Object?>())];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveRecent(List<SkyEvent> events) =>
      _prefs.setString(_kRecent, jsonEncode([for (final e in events) e.toJson()]));

  Future<({DateTime fetchedAt, List<Map<String, Object?>> raw})?> loadLaunches() async {
    final raw = await _prefs.getString(_kLaunches);
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      return (
        fetchedAt: DateTime.parse(j['t'] as String).toUtc(),
        raw: [for (final r in j['r'] as List) (r as Map).cast<String, Object?>()],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLaunches(List<Map<String, Object?>> raw, DateTime at) =>
      _prefs.setString(_kLaunches, jsonEncode({'t': at.toUtc().toIso8601String(), 'r': raw}));

  /// Station crews (trimmed Launch Library JSON) and when we fetched them.
  Future<({DateTime fetchedAt, Object? json})?> loadCrew() async {
    final raw = await _prefs.getString(_kCrew);
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      return (fetchedAt: DateTime.parse(j['t'] as String).toUtc(), json: j['d']);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCrew(Object? json, DateTime at) =>
      _prefs.setString(_kCrew, jsonEncode({'t': at.toUtc().toIso8601String(), 'd': json}));

  /// Notification ids currently scheduled, so a re-plan can cancel strays.
  Future<Set<int>> loadPlannedIds() async {
    final raw = await _prefs.getStringList(_kPlan);
    return {for (final s in raw ?? const <String>[]) int.parse(s)};
  }

  Future<void> savePlannedIds(Iterable<int> ids) =>
      _prefs.setStringList(_kPlan, [for (final i in ids) '$i']);

  Future<DateTime?> loadLastRefresh() async {
    final raw = await _prefs.getString(_kLastRefresh);
    return raw == null ? null : DateTime.parse(raw).toUtc();
  }

  Future<void> saveLastRefresh(DateTime t) =>
      _prefs.setString(_kLastRefresh, t.toUtc().toIso8601String());
}

/// "Did you see it?" answers, kept on-device (spec §6). Phase 1 uploads an
/// anonymised aggregate to tune thresholds.
class SeenFeedback {
  const SeenFeedback({
    required this.eventId,
    required this.seen,
    required this.at,
    this.reason,
    this.type,
    this.eventTime,
    this.peakElevationDeg,
    this.magnitude,
    this.place,
    this.photo,
  });
  final String eventId;
  final bool seen;
  final DateTime at;
  final String? reason; // clouds | too-low | missed
  final SkyEventType? type;
  final DateTime? eventTime;
  final double? peakElevationDeg;
  final double? magnitude;
  final String? place;

  /// File name under the app's sightings folder (never a full path: the
  /// container moves between app updates).
  final String? photo;

  SeenFeedback withPhoto(String? name) => SeenFeedback(
        eventId: eventId,
        seen: seen,
        at: at,
        reason: reason,
        type: type,
        eventTime: eventTime,
        peakElevationDeg: peakElevationDeg,
        magnitude: magnitude,
        place: place,
        photo: name,
      );

  factory SeenFeedback.forEvent(SkyEvent e, {required bool seen, String? reason, String? place, DateTime? at}) => SeenFeedback(
        eventId: e.id,
        seen: seen,
        at: (at ?? DateTime.now()).toUtc(),
        reason: reason,
        type: e.type,
        eventTime: e.peak,
        peakElevationDeg: e.peakElevationDeg,
        magnitude: (e.details['magnitude'] as num?)?.toDouble(),
        place: place,
      );

  Sighting toSighting() => Sighting(
        eventId: eventId,
        seen: seen,
        at: at,
        reason: reason,
        type: type,
        eventTime: eventTime,
        peakElevationDeg: peakElevationDeg,
        magnitude: magnitude,
        place: place,
        photo: photo,
      );

  Map<String, Object?> toJson() => {
        'e': eventId,
        's': seen,
        't': at.toIso8601String(),
        'r': reason,
        if (type != null) 'ty': type!.name,
        if (eventTime != null) 'et': eventTime!.toIso8601String(),
        if (peakElevationDeg != null) 'el': peakElevationDeg,
        if (magnitude != null) 'mg': magnitude,
        if (place != null) 'pl': place,
        if (photo != null) 'ph': photo,
      };
  factory SeenFeedback.fromJson(Map<String, Object?> j) => SeenFeedback(
        eventId: j['e'] as String,
        seen: j['s'] as bool,
        at: DateTime.parse(j['t'] as String).toUtc(),
        reason: j['r'] as String?,
        type: SkyEventType.values.where((t) => t.name == j['ty']).firstOrNull,
        eventTime: j['et'] == null ? null : DateTime.parse(j['et'] as String).toUtc(),
        peakElevationDeg: (j['el'] as num?)?.toDouble(),
        magnitude: (j['mg'] as num?)?.toDouble(),
        place: j['pl'] as String?,
        photo: j['ph'] as String?,
      );
}

extension FeedbackStore on LocalStore {
  Future<List<SeenFeedback>> loadFeedback() async {
    final raw = await _prefs.getString(LocalStore._kFeedback);
    if (raw == null) return const [];
    try {
      return [for (final e in jsonDecode(raw) as List) SeenFeedback.fromJson((e as Map).cast())];
    } catch (_) {
      return const [];
    }
  }

  Future<void> addFeedback(SeenFeedback f) async {
    final previous = (await loadFeedback()).where((x) => x.eventId == f.eventId).firstOrNull;
    // Answering again keeps a photo already attached.
    if (f.photo == null && previous?.photo != null) f = f.withPhoto(previous!.photo);
    final all = (await loadFeedback()).where((x) => x.eventId != f.eventId).toList()..add(f);
    // Keep the last 200.
    final trimmed = all.length > 200 ? all.sublist(all.length - 200) : all;
    await _prefs.setString(LocalStore._kFeedback, jsonEncode([for (final x in trimmed) x.toJson()]));
  }

  /// Attach (or with null, detach) a photo to the sighting for [eventId].
  Future<void> setPhoto(String eventId, String? name) async {
    final all = await loadFeedback();
    final i = all.indexWhere((x) => x.eventId == eventId);
    if (i < 0) return;
    final next = [...all]..[i] = all[i].withPhoto(name);
    await _prefs.setString(LocalStore._kFeedback, jsonEncode([for (final x in next) x.toJson()]));
  }
}
