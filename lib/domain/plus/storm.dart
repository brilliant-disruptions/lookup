/// A geomagnetic storm tonight, for the storm card: the free aurora outlook
/// says it could reach them and the forecast Kp is storm strength (G1, Kp 5,
/// or more). That's when people hear "aurora tonight" on the news, and the
/// one thing they want is a tap when it's visible from where they are:
/// LookUp+'s live aurora alerts. Pure.
library;

import '../models/sky_event.dart';

/// NOAA's G1: Kp 5.
const stormKp = 5.0;

/// The outlook for a storm night that hasn't ended, starting within [ahead].
SkyEvent? stormTonight(Iterable<SkyEvent> events, DateTime now, {Duration ahead = const Duration(hours: 18)}) {
  final u = now.toUtc();
  for (final e in events) {
    if (e.type != SkyEventType.auroraOutlook || e.details['past'] == true) continue;
    final kp = (e.details['kp'] as num?)?.toDouble() ?? 0;
    if (kp < stormKp) continue;
    if (!e.end.isAfter(u) || e.start.isAfter(u.add(ahead))) continue;
    return e;
  }
  return null;
}
