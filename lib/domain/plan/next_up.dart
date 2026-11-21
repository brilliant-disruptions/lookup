/// The one thing to count down to on the camera: the soonest sight LookUp
/// would tap you for that isn't over yet (one going over now counts).
library;

import '../models/sky_event.dart';

SkyEvent? nextUp(Iterable<SkyEvent> events, DateTime now) {
  final t = now.toUtc();
  SkyEvent? best;
  for (final e in events) {
    if (!e.type.pushes || !e.end.isAfter(t)) continue;
    if (best == null || e.start.isBefore(best.start)) best = e;
  }
  return best;
}
