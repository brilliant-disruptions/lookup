/// Planet highlights (oppositions, greatest elongations) as [SkyEvent]s on
/// the evening (or morning) of the day, once the planet is 15° up.
library;

import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/sun.dart';
import '../sky/tonight.dart';

List<SkyEvent> planetHighlightEvents({
  required DateTime now,
  required DateTime to,
  required double latDeg,
  required double lonDeg,
}) {
  final out = <SkyEvent>[];
  final days = to.difference(now).inDays + 1;
  for (final h in planetHighlights(now.subtract(const Duration(days: 1)), days: days + 1)) {
    if (h.date.isAfter(to.add(const Duration(days: 1)))) continue;
    // Twilight on that day: sun 8° down after sunset, or before sunrise.
    final dayStart = DateTime.utc(h.date.year, h.date.month, h.date.day).subtract(Duration(minutes: (lonDeg / 15 * 60).round()));
    final crossings = horizonCrossings((t) => sunAltitudeDeg(t, latDeg, lonDeg), dayStart, dayStart.add(const Duration(hours: 36)),
        h0: -8, step: const Duration(minutes: 5));
    final twilight = crossings.where((c) => h.evening ? !c.rising : c.rising).firstOrNull?.t;
    if (twilight == null) continue;
    // A planet at opposition rises at sunset, so wait (or, before dawn, look
    // back) until it's clear of the horizon: the first moment ≥ 15° up.
    DateTime? at;
    for (var i = 0; i <= 24; i++) {
      final t = twilight.add(Duration(minutes: (h.evening ? 10 : -10) * i));
      if (planetHorizontal(h.planet, t, latDeg, lonDeg).altitudeDeg >= 15) {
        at = t;
        break;
      }
    }
    if (at == null || !at.isAfter(now) || at.isAfter(to)) continue;
    final pos = planetHorizontal(h.planet, at, latDeg, lonDeg);
    out.add(SkyEvent(
      id: 'planet-${h.planet.name}-${h.kind}:${at.year}${at.month.toString().padLeft(2, '0')}${at.day.toString().padLeft(2, '0')}',
      type: SkyEventType.planetHighlight,
      start: at,
      peak: at.add(const Duration(minutes: 30)),
      end: at.add(const Duration(hours: 2)),
      peakElevationDeg: pos.altitudeDeg,
      riseAzimuthDeg: pos.azimuthDeg,
      peakAzimuthDeg: pos.azimuthDeg,
      setAzimuthDeg: pos.azimuthDeg,
      details: {
        'planet': h.planet.label,
        'kind': h.kind,
        'label': h.title,
        'magnitude': double.parse(planetMagnitude(h.planet, at).toStringAsFixed(1)),
        'brightness': planetBrightnessWord(planetMagnitude(h.planet, at)),
      },
    ));
  }
  return out;
}
