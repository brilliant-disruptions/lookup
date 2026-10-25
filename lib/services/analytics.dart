/// Anonymous, first-party product metrics (spec §10): alert precision,
/// notification opt-in, finder use, paywall → purchase. Events queue on the
/// device and flush to the backend's `track` function on refresh. No-op when
/// the backend isn't configured or the user turned sharing off.
library;

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/backend.dart';

class Analytics {
  Analytics({this.backend, SharedPreferencesAsync? prefs}) : _injected = prefs;

  final BackendClient? backend;
  final SharedPreferencesAsync? _injected;
  SharedPreferencesAsync? _lazy;
  // Created on first use so a disabled Analytics never touches storage.
  SharedPreferencesAsync get _prefs => _injected ?? (_lazy ??= SharedPreferencesAsync());
  static const _kQueue = 'analytics_queue';
  static const _kInstall = 'install_id';
  static const _kOptOut = 'analytics_opt_out';

  Future<String> installId() async {
    final existing = await _prefs.getString(_kInstall);
    if (existing != null) return existing;
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await _prefs.setString(_kInstall, id);
    return id;
  }

  Future<bool> get optedOut async => await _prefs.getBool(_kOptOut) ?? false;
  Future<void> setOptOut(bool v) async {
    await _prefs.setBool(_kOptOut, v);
    if (v) await _prefs.remove(_kQueue);
  }

  Future<void> log(String name, [Map<String, Object?> props = const {}]) async {
    if (backend == null || await optedOut) return;
    final q = await _queue();
    q.add({'name': name, 'at': DateTime.now().toUtc().toIso8601String(), 'props': props});
    // Bounded: drop the oldest if a device stays offline for a long time.
    final trimmed = q.length > 500 ? q.sublist(q.length - 500) : q;
    await _prefs.setString(_kQueue, jsonEncode(trimmed));
  }

  Future<void> flush() async {
    final b = backend;
    if (b == null || await optedOut) return;
    final q = await _queue();
    if (q.isEmpty) return;
    try {
      await b.track(await installId(), q.take(100).toList());
      final rest = q.length > 100 ? q.sublist(100) : <Map<String, Object?>>[];
      await _prefs.setString(_kQueue, jsonEncode(rest));
    } catch (_) {
      // Keep the queue; try again next refresh.
    }
  }

  Future<List<Map<String, Object?>>> _queue() async {
    final raw = await _prefs.getString(_kQueue);
    if (raw == null) return [];
    try {
      return [for (final e in jsonDecode(raw) as List) (e as Map).cast<String, Object?>()];
    } catch (_) {
      return [];
    }
  }
}
