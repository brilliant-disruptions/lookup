/// The clouds of the last week, kept on the phone.
///
/// MET Norway's forecast starts at the current hour; it has no past. "You
/// missed it" and the recent nights want to know whether last night was
/// clear, so each new forecast carries forward the hours before it from the
/// one it replaces:
///
/// - hours that were already past when that copy was fetched (history the
///   phone has kept before);
/// - hours it forecast at most [pastLead] ahead: a short forecast is close
///   to what happened, a three-day-old guess isn't, so those hours stay
///   unknown. Unknown never counts as clear.
///
/// Only for the same place (within [samePlaceDeg]), and nothing older than
/// [pastKeep].
library;

import 'cloud_forecast.dart';

const pastKeep = Duration(days: 7);
const pastLead = Duration(hours: 12);
const samePlaceDeg = 0.2;

CloudForecast withPast(CloudForecast fresh, CloudForecast? old, {required DateTime now}) {
  if (old == null || old.hourly.isEmpty || fresh.hourly.isEmpty) return fresh;
  if ((old.latitude - fresh.latitude).abs() > samePlaceDeg || (old.longitude - fresh.longitude).abs() > samePlaceDeg) {
    return fresh;
  }
  final firstFresh = fresh.hourly.map((s) => s.time).reduce((a, b) => a.isBefore(b) ? a : b);
  final oldest = now.toUtc().subtract(pastKeep);
  final trustedUntil = old.fetchedAt.add(pastLead);
  final kept = [
    for (final s in old.hourly)
      if (s.time.isBefore(firstFresh) && !s.time.isBefore(oldest) && !s.time.isAfter(trustedUntil)) s,
  ]..sort((a, b) => a.time.compareTo(b.time));
  if (kept.isEmpty) return fresh;
  return CloudForecast(
    latitude: fresh.latitude,
    longitude: fresh.longitude,
    fetchedAt: fresh.fetchedAt,
    hourly: [...kept, ...fresh.hourly],
  );
}
