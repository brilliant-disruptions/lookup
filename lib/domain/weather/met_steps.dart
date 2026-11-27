/// The relay's clouds (`GET /v1/clouds`, relay/src/met.ts: MET Norway's
/// Locationforecast, trimmed) as the hourly samples the rest of the app
/// reads.
///
/// MET steps hourly for about two and a half days, then every 6 hours. Each
/// step's cloud and fog are for its moment; its rain is for the hour or the
/// 6 hours after it. So that a night four days out still has clouds (unknown
/// cloud would pass the alert gate unchecked), every hour from the first
/// step to 3 hours past the last gets:
///
/// - cloud and fog from the nearest step, if one is within 3 hours;
/// - rain from the step whose window covers it, spread evenly over that
///   window, and that window's chance of rain.
library;

import 'cloud_forecast.dart';

/// One step as the relay sends it.
class MetStep {
  const MetStep({required this.time, required this.hours, this.cloud, this.fog, this.precipMm, this.precipProb});
  final DateTime time;
  final int hours;
  final double? cloud;
  final double? fog;
  final double? precipMm;
  final double? precipProb;

  /// Null when the row isn't a step (no time); missing numbers stay null.
  static MetStep? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'];
    final time = t is String ? DateTime.tryParse(t)?.toUtc() : null;
    if (time == null) return null;
    double? n(String k) => j[k] is num ? (j[k] as num).toDouble() : null;
    final h = j['hours'];
    return MetStep(
      time: time,
      hours: h is num && h >= 1 && h <= 12 ? h.round() : 1,
      cloud: n('cloud'),
      fog: n('fog'),
      precipMm: n('precipMm'),
      precipProb: n('precipProb'),
    );
  }
}

const _reach = Duration(hours: 3);

/// Hourly samples from [steps] (any order). Hours with no cloud figure are
/// left out: unknown, never assumed clear.
List<CloudSample> hourlyFromSteps(List<MetStep> steps) {
  if (steps.isEmpty) return const [];
  final s = [...steps]..sort((a, b) => a.time.compareTo(b.time));
  DateTime hourOf(DateTime t) => DateTime.utc(t.year, t.month, t.day, t.hour);
  final first = hourOf(s.first.time);
  final last = hourOf(s.last.time).add(_reach);
  final out = <CloudSample>[];
  for (var h = first; !h.isAfter(last); h = h.add(const Duration(hours: 1))) {
    // Nearest step with a cloud figure; on a tie the later one.
    MetStep? near;
    Duration? best;
    for (final x in s) {
      if (x.cloud == null) continue;
      final d = x.time.difference(h).abs();
      if (d > _reach) continue;
      if (best == null || d <= best) {
        best = d;
        near = x;
      }
    }
    if (near == null) continue;
    // The rain window covering this hour.
    MetStep? wet;
    for (final x in s) {
      if (!x.time.isAfter(h) && h.isBefore(x.time.add(Duration(hours: x.hours)))) wet = x;
    }
    final mm = wet?.precipMm;
    out.add(CloudSample(
      time: h,
      coverPercent: near.cloud!.round().clamp(0, 100),
      fogPercent: near.fog?.round().clamp(0, 100),
      precipMm: mm == null ? null : mm / wet!.hours,
      precipProbability: wet?.precipProb?.round().clamp(0, 100),
    ));
  }
  return out;
}

/// The relay's whole answer as a forecast for [latitude], [longitude].
/// [fetchedAt] is when MET was last asked (the relay's `fetched`), never
/// later than [now], so a stale copy reads as stale.
CloudForecast forecastFromRelay(Map<String, Object?> j,
    {required double latitude, required double longitude, required DateTime now}) {
  final steps = [
    for (final x in (j['steps'] is List ? j['steps'] as List : const []))
      ?MetStep.fromJson(x),
  ];
  final f = j['fetched'];
  final fetched = f is String ? DateTime.tryParse(f)?.toUtc() : null;
  final at = fetched == null || fetched.isAfter(now) ? now.toUtc() : fetched;
  return CloudForecast(latitude: latitude, longitude: longitude, fetchedAt: at, hourly: hourlyFromSteps(steps));
}
