/// Hourly cloud-cover forecast for one location.
library;

class CloudSample {
  const CloudSample({required this.time, required this.coverPercent, this.visibilityM, this.precipProbability});
  final DateTime time; // UTC, top of hour
  final int coverPercent; // 0–100

  /// Horizontal visibility (fog, haze), metres. Null when not forecast.
  final int? visibilityM;

  /// Chance of rain or snow this hour, 0–100.
  final int? precipProbability;
}

class CloudForecast {
  CloudForecast({
    required this.latitude,
    required this.longitude,
    required this.fetchedAt,
    required List<CloudSample> hourly,
  }) : hourly = List.unmodifiable(hourly);

  final double latitude;
  final double longitude;
  final DateTime fetchedAt;
  final List<CloudSample> hourly;

  static const empty = _EmptyCloudForecast();

  /// Cloud cover at the hour nearest [utc], or null when outside the forecast.
  int? coverAt(DateTime utc) => sampleAt(utc)?.coverPercent;

  /// The whole hourly sample nearest [utc] (within the hour).
  CloudSample? sampleAt(DateTime utc) {
    if (hourly.isEmpty) return null;
    final t = utc.toUtc();
    CloudSample? best;
    var bestDist = const Duration(hours: 1);
    for (final s in hourly) {
      final d = (s.time.difference(t)).abs();
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    return best;
  }

  bool isStale(DateTime now, {Duration maxAge = const Duration(hours: 6)}) =>
      now.toUtc().difference(fetchedAt) > maxAge;

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'fetchedAt': fetchedAt.toIso8601String(),
        'hourly': [
          for (final s in hourly)
            [s.time.millisecondsSinceEpoch ~/ 1000, s.coverPercent, s.visibilityM, s.precipProbability],
        ],
      };

  factory CloudForecast.fromJson(Map<String, Object?> j) => CloudForecast(
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        fetchedAt: DateTime.parse(j['fetchedAt'] as String).toUtc(),
        hourly: [
          for (final e in (j['hourly'] as List))
            CloudSample(
              time: DateTime.fromMillisecondsSinceEpoch(
                  (e[0] as int) * 1000,
                  isUtc: true),
              coverPercent: e[1] as int,
              visibilityM: e.length > 2 ? (e[2] as num?)?.toInt() : null,
              precipProbability: e.length > 3 ? (e[3] as num?)?.toInt() : null,
            ),
        ],
      );
}

class _EmptyCloudForecast implements CloudForecast {
  const _EmptyCloudForecast();
  @override
  double get latitude => 0;
  @override
  double get longitude => 0;
  @override
  DateTime get fetchedAt => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  @override
  List<CloudSample> get hourly => const [];
  @override
  int? coverAt(DateTime utc) => null;
  @override
  CloudSample? sampleAt(DateTime utc) => null;
  @override
  bool isStale(DateTime now, {Duration maxAge = const Duration(hours: 6)}) =>
      true;
  @override
  Map<String, Object?> toJson() => const {};
}
