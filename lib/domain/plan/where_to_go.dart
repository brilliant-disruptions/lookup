/// "Where to go tonight": their saved places side by side on the coming
/// night's clouds and how dark each sky is, and one plain recommendation.
library;

import 'dart:math' as math;

import '../sky/visibility.dart';

/// One place on one night.
class PlaceNight {
  const PlaceNight({
    required this.name,
    required this.here,
    required this.darkness,
    required this.outlook,
    this.distanceKm,
    this.bearingDeg,
  });

  final String name;

  /// Where they are now (no trip needed).
  final bool here;
  final SkyDarkness darkness;

  /// Clouds through the dark hours; null when it never gets dark there.
  final NightOutlook? outlook;

  /// From where they are; null for here, or when we don't know where they are.
  final double? distanceKm;
  final double? bearingDeg;

  bool get hasForecast => outlook?.hasForecast ?? false;

  /// The longest clear spell (see [NightOutlook]), in hours. Zero without a
  /// forecast: we never guess clear.
  double get clearHours {
    final o = outlook;
    if (o == null || !o.hasForecast || o.bestStart == null || o.bestEnd == null) return 0;
    return o.bestEnd!.difference(o.bestStart!).inMinutes / 60;
  }

  /// Clear hours, discounted for a brighter sky: an hour under a city sky
  /// shows far less than an hour somewhere dark.
  double get score => clearHours * _weight[darkness]!;

  static const _weight = {SkyDarkness.city: 0.6, SkyDarkness.suburbs: 0.8, SkyDarkness.dark: 1.0};
}

enum WhereToGoKind {
  /// Here is best, or close enough that the drive isn't worth it.
  stayPut,

  /// Somewhere else is clearly better: [WhereToGo.best].
  go,

  /// The forecast reaches tonight but nowhere they've saved is clear.
  cloudyEverywhere,

  /// No forecast for anywhere (offline, or not fetched yet).
  noForecast,
}

class WhereToGo {
  const WhereToGo(this.kind, this.ranked, {this.best});
  final WhereToGoKind kind;

  /// Every place, best first.
  final List<PlaceNight> ranked;

  /// The place to be; null for [WhereToGoKind.cloudyEverywhere] and
  /// [WhereToGoKind.noForecast].
  final PlaceNight? best;
}

/// How much better (in clear, dark-weighted hours) somewhere else must be
/// before it's worth suggesting a trip.
const tripWorthHours = 1.0;

/// Best first: highest [PlaceNight.score], then here, then nearest.
List<PlaceNight> rankPlaces(Iterable<PlaceNight> places) => places.toList()
  ..sort((a, b) {
    final s = b.score.compareTo(a.score);
    if (s != 0) return s;
    if (a.here != b.here) return a.here ? -1 : 1;
    return (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0);
  });

WhereToGo whereToGo(Iterable<PlaceNight> places) {
  final ranked = rankPlaces(places);
  if (!ranked.any((p) => p.hasForecast)) return WhereToGo(WhereToGoKind.noForecast, ranked);
  final top = ranked.first;
  if (top.clearHours <= 0) return WhereToGo(WhereToGoKind.cloudyEverywhere, ranked);
  final here = ranked.where((p) => p.here).firstOrNull;
  // Never "stay put" under cloud when somewhere saved has a clear spell.
  if (here != null && here.clearHours > 0 && top.score - here.score < tripWorthHours) {
    return WhereToGo(WhereToGoKind.stayPut, ranked, best: here);
  }
  return WhereToGo(WhereToGoKind.go, ranked, best: top);
}

const _earthKm = 6371.0;
double _rad(double d) => d * math.pi / 180;

/// Great-circle distance in km.
double distanceKm(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1), dLon = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthKm * math.asin(math.min(1, math.sqrt(a)));
}

/// Initial compass bearing from the first point to the second, 0–360°.
double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final p1 = _rad(lat1), p2 = _rad(lat2), dLon = _rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
