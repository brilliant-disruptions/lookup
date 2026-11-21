/// "You missed it": the morning after a Plus-only sight went over a free
/// user under a clear sky, one honest line on Home. Only ever said when it's
/// true: the event really happened over them (recent passes are propagated
/// backwards; aurora nights are observed Kp that met the bar here in the
/// dark), and the sky really was clear (Open-Meteo's past hours). Unknown
/// cloud is never "clear". Pure.
library;

import '../models/sky_event.dart';

/// How far back counts as "last night".
const missedItWindow = Duration(hours: 36);

/// At most once a week.
const missedItGap = Duration(days: 7);

/// Cloud cover at or under this is "clear skies" (as pastVerdict says).
const missedItClearPercent = 20;

/// The most recent Plus-only sight they'd have been tapped for, if there is
/// one to tell them about now.
SkyEvent? missedIt({
  required Iterable<SkyEvent> recent,
  required DateTime now,
  String? toldId,
  DateTime? toldAt,
}) {
  final u = now.toUtc();
  if (toldAt != null && u.difference(toldAt.toUtc()) < missedItGap) return null;
  SkyEvent? best;
  for (final e in recent) {
    if (!e.plusOnly || !e.type.pushes) continue;
    if (e.details['past'] != true || e.id == toldId) continue;
    if (!e.end.isBefore(u) || u.difference(e.end) > missedItWindow) continue;
    final c = e.cloudCoverPercent;
    if (c == null || c > missedItClearPercent) continue;
    if (best == null || e.start.isAfter(best.start)) best = e;
  }
  return best;
}
