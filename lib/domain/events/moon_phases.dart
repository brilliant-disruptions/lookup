/// First and last quarter Moons, only on the nights you can actually see
/// them: the Moon well up while the sky is properly dark. (Full Moons are
/// `moonrise.dart`; a new Moon can't be seen, so it isn't an event.)
library;

import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/moon_times.dart';
import '../sky/sun.dart';

/// The Moon must be at least this high (°) to count as visible.
const moonPhaseMinAltDeg = 10.0;

/// The Sun must be at least this far down (°): the end of civil twilight.
const moonPhaseSunMaxAltDeg = -6.0;

/// One event per quarter Moon in [now, now + days] whose night has the
/// Moon up in a dark sky: first quarter in the evening, last quarter before
/// dawn. The night nearest the instant of the quarter is the one used. None
/// where the Moon is never up in the dark that day (near the poles).
List<SkyEvent> moonPhaseEvents({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  int days = 14,
}) {
  final from = now.toUtc();
  final to = from.add(Duration(days: days));
  final out = <SkyEvent>[];
  for (final quarter in MoonQuarter.values) {
    for (final q in moonQuartersBetween(quarter, from.subtract(const Duration(days: 1)), to.add(const Duration(days: 1)))) {
      final run = _visibleRun(q, latDeg, lonDeg);
      if (run == null || run.start.isBefore(from) || run.start.isAfter(to)) continue;
      final peak = run.peak;
      final at = moonHorizontal(peak, latDeg, lonDeg);
      final rise = moonHorizontal(run.start, latDeg, lonDeg);
      final set = moonHorizontal(run.end, latDeg, lonDeg);
      out.add(SkyEvent(
        id: 'moonphase:${quarter.name}:${q.toIso8601String().substring(0, 10)}',
        type: SkyEventType.moonPhase,
        start: run.start,
        peak: peak,
        end: run.end,
        peakElevationDeg: at.altitudeDeg,
        riseAzimuthDeg: rise.azimuthDeg,
        peakAzimuthDeg: at.azimuthDeg,
        setAzimuthDeg: set.azimuthDeg,
        details: {
          'label': quarter.label,
          'quarter': quarter.name,
          'exactAt': q.toIso8601String(),
          'evening': quarter == MoonQuarter.first,
        },
      ));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// The stretch of dark sky with the Moon up that sits closest to [q].
({DateTime start, DateTime peak, DateTime end})? _visibleRun(DateTime q, double lat, double lon) {
  const step = Duration(minutes: 5);
  final lo = q.subtract(const Duration(hours: 24));
  final hi = q.add(const Duration(hours: 24));
  final runs = <({DateTime start, DateTime peak, DateTime end})>[];
  DateTime? start;
  DateTime? peak;
  var peakAlt = -90.0;
  var last = lo;
  for (var t = lo; t.isBefore(hi); t = t.add(step)) {
    final alt = moonHorizontal(t, lat, lon).altitudeDeg;
    final ok = alt >= moonPhaseMinAltDeg && sunAltitudeDeg(t, lat, lon) <= moonPhaseSunMaxAltDeg;
    if (ok) {
      if (start == null) {
        start = t;
        peakAlt = -90;
      }
      if (alt > peakAlt) {
        peakAlt = alt;
        peak = t;
      }
    } else if (start != null) {
      runs.add((start: start, peak: peak!, end: last));
      start = null;
    }
    last = t;
  }
  if (start != null) runs.add((start: start, peak: peak!, end: last));
  if (runs.isEmpty) return null;
  Duration away(({DateTime start, DateTime peak, DateTime end}) r) => r.peak.difference(q).abs();
  runs.sort((a, b) => away(a).compareTo(away(b)));
  return runs.first;
}
