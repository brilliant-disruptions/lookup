/// Everything persisted on-device. No PII leaves the phone in the MVP.
library;

import 'dart:convert';
import 'dart:math' show Random;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scheduling/alert_ledger.dart';
import '../domain/aurora/aurora_rules.dart';
import '../domain/aurora/push_plan.dart' show PushRecord;
import '../domain/finder/finder_stats.dart';
import '../domain/log/sighting.dart';
import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/orbit/omm.dart';
import '../domain/plus/plus_grant.dart';
import '../domain/scheduling/refresh_slot.dart';
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
    this.latitude,
    this.longitude,
  });

  /// "Aurora now" is only said from a reading this fresh. Older (the feed
  /// is down, the phone's offline) is yesterday's storm.
  static const nowMaxAge = Duration(minutes: 60);

  /// Where the oval was read for; null in a snapshot saved before this was kept.
  final double? latitude, longitude;

  /// Whether [kpNow] and [ovationProbability] still say what's overhead at
  /// [lat], [lon] at [now]: read within [nowMaxAge], and for this place.
  bool currentFor(DateTime now, double lat, double lon) {
    final age = now.toUtc().difference(fetchedAt);
    if (age > nowMaxAge || age < const Duration(minutes: -5)) return false;
    final la = latitude, lo = longitude;
    if (la == null || lo == null) return true;
    return (la - lat).abs() <= 0.5 && (lo - lon).abs() <= 0.5;
  }

  final DateTime fetchedAt;
  final double? kpNow;
  final List<KpForecastPoint> forecast;
  final int ovationProbability;

  Map<String, Object?> toJson() => {
        'fetchedAt': fetchedAt.toIso8601String(),
        'kpNow': kpNow,
        'ovation': ovationProbability,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lon': longitude,
        'forecast': [
          for (final p in forecast)
            {'t': p.time.toIso8601String(), 'kp': p.kp, 'k': p.kind},
        ],
      };

  factory AuroraSnapshot.fromJson(Map<String, Object?> j) => AuroraSnapshot(
        fetchedAt: DateTime.parse(j['fetchedAt'] as String).toUtc(),
        kpNow: (j['kpNow'] as num?)?.toDouble(),
        ovationProbability: (j['ovation'] as num?)?.toInt() ?? 0,
        latitude: (j['lat'] as num?)?.toDouble(),
        longitude: (j['lon'] as num?)?.toDouble(),
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
  static const _kRareEvents = 'rareEvents';
  static const _kPlan = 'plan_ids';
  static const _kLedger = 'alert_ledger_v1';
  static const _kAurora = 'aurora';
  static const _kClouds = 'clouds';
  static const _kLastRefresh = 'last_refresh';
  static const _kFeedback = 'feedback';
  static const _kCrew = 'crew';
  static const _kReporter = 'aurora_reporter';
  static const _kPush = 'aurora_push';
  static String _kElements(String key) => 'elements_$key';
  static String _kCelestrakFailed(String key) => 'celestrak_failed_$key';
  static const _kRefreshSlot = 'refresh_slot_min';
  static const _kFinderStats = 'finder_stats';

  Future<LookUpSettings> loadSettings() async {
    final raw = await _prefs.getString(_kSettings);
    if (raw == null) return const LookUpSettings();
    try {
      // Every reader (the app, the background refresh, the alert planner)
      // sees a subscription that has run out as free.
      return PlusGrant.asOf(
          LookUpSettings.fromJson((jsonDecode(raw) as Map).cast<String, Object?>()), DateTime.now().toUtc());
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

  /// Celestrak's etiquette: each feed at most once a day, and phones spread
  /// out over the day ([feedDue] in `domain/scheduling/refresh_slot.dart`):
  /// [background] runs download in this install's own slot; with the app
  /// open, only a cache that's overdue (or missing) is fetched. Never while
  /// the feed is resting after a failure. Nothing forces it sooner.
  /// [utcOffset] is the phone's (tests pass one).
  Future<bool> celestrakDue(String key, CachedElements? cached, DateTime now,
      {bool background = false, Duration? utcOffset}) async {
    final failed = await _celestrakFailures(key);
    if (failed != null && now.toUtc().isBefore(failed.until)) return false;
    final local = now.toUtc().add(utcOffset ?? now.toLocal().timeZoneOffset);
    return feedDue(
      fetchedAt: cached?.fetchedAt,
      now: now,
      localMinute: local.hour * 60 + local.minute,
      slotMinute: await refreshSlot(),
      background: background,
    );
  }

  /// How long a feed rests after each failure in a row; a refusal rests the longest.
  static const celestrakBackoff = [Duration(hours: 1), Duration(hours: 4), Duration(hours: 24)];

  /// Records a failed download of [key]; [refused] when Celestrak said no.
  Future<void> celestrakFailed(String key, DateTime now, {bool refused = false}) async {
    final n = ((await _celestrakFailures(key))?.count ?? 0) + 1;
    final rest = refused ? celestrakBackoff.last : celestrakBackoff[(n - 1).clamp(0, celestrakBackoff.length - 1)];
    await _prefs.setString(_kCelestrakFailed(key),
        jsonEncode({'count': n, 'until': now.toUtc().add(rest).toIso8601String()}));
  }

  Future<void> celestrakSucceeded(String key) => _prefs.remove(_kCelestrakFailed(key));

  Future<({int count, DateTime until})?> _celestrakFailures(String key) async {
    final raw = await _prefs.getString(_kCelestrakFailed(key));
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      return (count: j['count'] as int, until: DateTime.parse(j['until'] as String).toUtc());
    } catch (_) {
      return null;
    }
  }

  /// This install's daily download slot, a local minute of the day picked
  /// once ([pickRefreshSlot]).
  Future<int> refreshSlot() async {
    final have = await _prefs.getInt(_kRefreshSlot);
    if (have != null) return have;
    final pick = pickRefreshSlot(Random.secure());
    await _prefs.setInt(_kRefreshSlot, pick);
    return pick;
  }

  Future<FinderStats> loadFinderStats() async {
    final raw = await _prefs.getString(_kFinderStats);
    if (raw == null) return const FinderStats();
    try {
      return FinderStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const FinderStats();
    }
  }

  /// Adds one finder session to the on-phone lock-rate tally.
  Future<void> recordFinderSession(Duration? toLock) async =>
      _prefs.setString(_kFinderStats, jsonEncode((await loadFinderStats()).record(toLock).toJson()));

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

  /// Seen near you: a random token that counts this install once among
  /// aurora reports. A new one every day (UTC), so reports can't be tied
  /// together across nights; the relay salts and hashes it as well.
  Future<String> auroraReporter(DateTime now) async {
    final day = now.toUtc().toIso8601String().substring(0, 10);
    final raw = await _prefs.getString(_kReporter);
    if (raw != null && raw.startsWith('$day:')) return raw.substring(day.length + 1);
    final rnd = Random.secure();
    final token = [for (var i = 0; i < 24; i++) rnd.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    await _prefs.setString(_kReporter, '$day:$token');
    return token;
  }

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

  /// The relay's rare-events list (decoded JSON) and when we fetched it.
  Future<({DateTime fetchedAt, Object? json})?> loadRareEvents() async {
    final raw = await _prefs.getString(_kRareEvents);
    if (raw == null) return null;
    try {
      final j = (jsonDecode(raw) as Map).cast<String, Object?>();
      return (fetchedAt: DateTime.parse(j['t'] as String).toUtc(), json: j['r']);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRareEvents(Object? json, DateTime at) =>
      _prefs.setString(_kRareEvents, jsonEncode({'t': at.toUtc().toIso8601String(), 'r': json}));

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
  /// What the phone last told the relay about wake-ups; null if nothing.
  Future<PushRecord?> loadPushRecord() async {
    final raw = await _prefs.getString(_kPush);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      return (token: j['token']! as String, area: j['area']! as String, at: DateTime.parse(j['at']! as String).toUtc());
    } catch (_) {
      return null;
    }
  }

  Future<void> savePushRecord(PushRecord? r) => r == null
      ? _prefs.remove(_kPush)
      : _prefs.setString(_kPush, jsonEncode({'token': r.token, 'area': r.area, 'at': r.at.toUtc().toIso8601String()}));

  Future<Set<int>> loadPlannedIds() async {
    final raw = await _prefs.getStringList(_kPlan);
    return {for (final s in raw ?? const <String>[]) int.parse(s)};
  }

  Future<void> savePlannedIds(Iterable<int> ids) =>
      _prefs.setStringList(_kPlan, [for (final i in ids) '$i']);

  /// Alerts scheduled and delivered (domain/scheduling/alert_ledger.dart).
  Future<List<AlertRecord>> loadAlertLedger() async {
    try {
      final raw = await _prefs.getString(_kLedger);
      if (raw == null) return const [];
      return [for (final j in jsonDecode(raw) as List) ?AlertRecord.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAlertLedger(Iterable<AlertRecord> records) =>
      _prefs.setString(_kLedger, jsonEncode([for (final r in records) r.toJson()]));

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
    this.photoAsset,
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

  /// The picture's id in Photos, when the Log shows it from there (then
  /// [photo] is only a small thumbnail).
  final String? photoAsset;

  /// The same answer, dated [when].
  SeenFeedback caughtAt(DateTime when) => SeenFeedback(
        eventId: eventId,
        seen: seen,
        at: when,
        reason: reason,
        type: type,
        eventTime: eventTime,
        peakElevationDeg: peakElevationDeg,
        magnitude: magnitude,
        place: place,
        photo: photo,
        photoAsset: photoAsset,
      );

  SeenFeedback withPhoto(String? name, {String? asset}) => SeenFeedback(
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
        photoAsset: asset,
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
        photoAsset: photoAsset,
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
        if (photoAsset != null) 'pa': photoAsset,
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
        photoAsset: j['pa'] as String?,
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
    if (f.photo == null && previous?.photo != null) f = f.withPhoto(previous!.photo, asset: previous.photoAsset);
    // Catching something again (Jupiter has one entry, whatever the night)
    // keeps the day it was first caught: the Log's order and the patches
    // earned along the way don't move, and nothing is announced twice.
    if (f.seen && (previous?.seen ?? false)) f = f.caughtAt(previous!.at);
    final all = (await loadFeedback()).where((x) => x.eventId != f.eventId).toList()..add(f);
    await _prefs.setString(LocalStore._kFeedback, jsonEncode([for (final x in trimLog(all)) x.toJson()]));
  }

  /// "No, I missed it" answers are only for tuning: the newest 200 are
  /// enough. A catch is somebody's eclipse and the patch it earned, so
  /// catches are kept (5,000 is years of looking up every clear night).
  static const maxMissed = 200, maxCatches = 5000;

  /// [all] (oldest first) within those limits, dropping the oldest of each kind.
  static List<SeenFeedback> trimLog(List<SeenFeedback> all) {
    var missed = all.where((x) => !x.seen).length - maxMissed;
    var caught = all.where((x) => x.seen).length - maxCatches;
    if (missed <= 0 && caught <= 0) return all;
    return [
      for (final x in all)
        if (x.seen ? caught-- <= 0 : missed-- <= 0) x,
    ];
  }

  /// Attach (or with null, detach) a photo to the sighting for [eventId].
  Future<void> setPhoto(String eventId, String? name, {String? asset}) async {
    final all = await loadFeedback();
    final i = all.indexWhere((x) => x.eventId == eventId);
    if (i < 0) return;
    final next = [...all]..[i] = all[i].withPhoto(name, asset: asset);
    await _prefs.setString(LocalStore._kFeedback, jsonEncode([for (final x in next) x.toJson()]));
  }
}
