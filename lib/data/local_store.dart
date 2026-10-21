/// Everything persisted on-device. No PII leaves the phone in the MVP.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/aurora/aurora_rules.dart';
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
  static const _kPlan = 'plan_ids';
  static const _kAurora = 'aurora';
  static const _kClouds = 'clouds';
  static const _kLastRefresh = 'last_refresh';
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
