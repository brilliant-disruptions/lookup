/// On-demand extras: the satellites-tonight list and who's aboard the
/// stations. Fetched only when someone looks, cached for a day.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/celestrak_client.dart';
import '../data/launch_library_client.dart';
import '../data/local_store.dart';
import '../domain/models/sky_event.dart';
import '../domain/orbit/omm.dart';
import '../domain/satellites/bright_tonight.dart';
import '../domain/satellites/crew.dart';
import 'providers.dart';

const _maxAge = Duration(hours: 24);

final celestrakProvider = Provider<CelestrakClient>((_) => CelestrakClient());
final launchLibraryProvider = Provider<LaunchLibraryClient>((_) => LaunchLibraryClient());

/// The brightest passes over the next ~20 hours (tonight and the morning).
final brightTonightProvider = FutureProvider<List<SkyEvent>>((ref) async {
  final s = await ref.watch(settingsProvider.future);
  if (!s.hasLocation) return const [];
  final store = ref.read(storeProvider);
  final now = DateTime.now().toUtc();
  var cached = await store.loadElements('visual');
  if (cached == null || cached.isOlderThan(_maxAge, now)) {
    try {
      final recs = await ref.read(celestrakProvider).fetchVisual();
      if (recs.isNotEmpty) {
        await store.saveElements('visual', recs, now);
        cached = CachedElements(fetchedAt: now, records: recs);
      }
    } catch (_) {
      if (cached == null) rethrow;
    }
  }
  final records = [for (final r in cached!.records) r.json];
  final events = await compute(_brightTonight, (
    records: records,
    lat: s.latitude!,
    lon: s.longitude!,
    fromMs: now.millisecondsSinceEpoch,
    toMs: now.add(const Duration(hours: 20)).millisecondsSinceEpoch,
  ));
  return [for (final e in events) SkyEvent.fromJson(e)];
});

/// Runs in an isolate: ~150 objects × a night of SGP4.
List<Map<String, Object?>> _brightTonight(
    ({List<Map<String, Object?>> records, double lat, double lon, int fromMs, int toMs}) a) {
  final events = brightTonight(
    records: [for (final r in a.records) OmmRecord.fromJson(r)],
    latDeg: a.lat,
    lonDeg: a.lon,
    from: DateTime.fromMillisecondsSinceEpoch(a.fromMs, isUtc: true),
    to: DateTime.fromMillisecondsSinceEpoch(a.toMs, isUtc: true),
  );
  return [for (final e in events) e.toJson()];
}

/// Who's aboard each station right now.
final crewProvider = FutureProvider<Map<Station, List<CrewMember>>>((ref) async {
  final store = ref.read(storeProvider);
  final now = DateTime.now().toUtc();
  final cached = await store.loadCrew();
  if (cached != null && now.difference(cached.fetchedAt) < _maxAge) return crewFromExpeditions(cached.json);
  try {
    final trimmed = trimExpeditions(await ref.read(launchLibraryProvider).fetchActiveExpeditions());
    await store.saveCrew(trimmed, now);
    return crewFromExpeditions(trimmed);
  } catch (_) {
    return cached == null ? const {} : crewFromExpeditions(cached.json);
  }
});
