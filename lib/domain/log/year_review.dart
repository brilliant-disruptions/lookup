/// "Your sky year": a shareable summary of what you saw in a calendar year.
library;

import '../models/sky_event.dart';
import 'sighting.dart';

class YearReview {
  const YearReview({
    required this.year,
    required this.seen,
    required this.nights,
    required this.byType,
    required this.brightest,
    required this.highest,
    required this.first,
    required this.bestMonth,
    required this.lateNights,
  });

  final int year;
  final int seen;

  /// Distinct nights out (an evening and the morning after count once).
  final int nights;

  /// Most-seen first.
  final List<(SkyEventType, int)> byType;
  final Sighting? brightest;
  final Sighting? highest;
  final Sighting? first;

  /// 1–12, the month with the most sightings.
  final int? bestMonth;

  /// Sightings between midnight and 4 AM.
  final int lateNights;

  /// Null when nothing was seen that year. [utcOffsetMinutes] places each
  /// sighting on the user's local calendar.
  static YearReview? from(List<Sighting> all, int year, {required int utcOffsetMinutes}) {
    DateTime local(Sighting s) => (s.eventTime ?? s.at).toUtc().add(Duration(minutes: utcOffsetMinutes));
    final seen = [
      for (final s in all)
        if (s.seen && local(s).year == year) s,
    ]..sort((a, b) => local(a).compareTo(local(b)));
    if (seen.isEmpty) return null;

    final counts = <SkyEventType, int>{};
    final months = <int, int>{};
    final nights = <String>{};
    var late = 0;
    Sighting? brightest, highest;
    for (final s in seen) {
      final t = s.inferredType;
      if (t != null) counts[t] = (counts[t] ?? 0) + 1;
      final l = local(s);
      months[l.month] = (months[l.month] ?? 0) + 1;
      final night = l.subtract(const Duration(hours: 12));
      nights.add('${night.year}-${night.month}-${night.day}');
      if (l.hour < 4) late++;
      if (s.magnitude != null && (brightest == null || s.magnitude! < brightest.magnitude!)) brightest = s;
      final passLike = t == SkyEventType.iss || t == SkyEventType.tiangong || t == SkyEventType.starlinkTrain || t == SkyEventType.satellitePass;
      if (passLike && s.peakElevationDeg != null && (highest == null || s.peakElevationDeg! > highest.peakElevationDeg!)) {
        highest = s;
      }
    }
    final byType = [for (final e in counts.entries) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
    final bestMonth = months.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return YearReview(
      year: year,
      seen: seen.length,
      nights: nights.length,
      byType: byType,
      brightest: brightest,
      highest: highest,
      first: seen.first,
      bestMonth: bestMonth,
      lateNights: late,
    );
  }
}
