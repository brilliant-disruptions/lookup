/// The full Moon coming up over the horizon: big, orange and the easiest
/// sky event there is. Supermoons are flagged, not a separate event.
library;

import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/moon_times.dart';

/// One event per full Moon whose moonrise falls in [now, now + days]: the
/// rise nearest the instant of full, which is the evening it looks full.
/// None where the Moon doesn't rise that day (near the poles).
List<SkyEvent> fullMoonRiseEvents({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  int days = 14,
}) {
  final from = now.toUtc();
  final to = from.add(Duration(days: days));
  // A day either side: the rise can be up to ~12 h from the full instant.
  final fulls = fullMoonsBetween(from.subtract(const Duration(days: 1)), to.add(const Duration(days: 1)));
  final out = <SkyEvent>[];
  for (final f in fulls) {
    final rises = moonrisesBetween(
        f.at.subtract(const Duration(hours: 13)), f.at.add(const Duration(hours: 13)), latDeg, lonDeg);
    if (rises.isEmpty) continue;
    rises.sort((a, b) => a.at.difference(f.at).abs().compareTo(b.at.difference(f.at).abs()));
    final rise = rises.first;
    if (rise.at.isBefore(from) || rise.at.isAfter(to)) continue;
    // Half an hour of "it's coming up": scored by how high it gets in that
    // time, so it ranks below a good pass under the nightly cap.
    final end = rise.at.add(const Duration(minutes: 30));
    final atEnd = moonHorizontal(end, latDeg, lonDeg);
    final day = f.at.toIso8601String().substring(0, 10);
    out.add(SkyEvent(
      id: 'fullmoon:$day',
      type: SkyEventType.fullMoonRise,
      start: rise.at,
      peak: rise.at,
      end: end,
      peakElevationDeg: atEnd.altitudeDeg,
      riseAzimuthDeg: rise.azimuthDeg,
      peakAzimuthDeg: rise.azimuthDeg,
      setAzimuthDeg: atEnd.azimuthDeg,
      details: {
        'label': f.supermoon ? 'Supermoon' : 'Full Moon',
        'supermoon': f.supermoon,
        'distanceKm': f.distanceKm.round(),
        'fullAt': f.at.toIso8601String(),
      },
    ));
  }
  return out;
}
