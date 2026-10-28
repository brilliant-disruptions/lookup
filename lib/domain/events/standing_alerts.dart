/// LookUp+ taps for things that are up for weeks rather than minutes: a
/// favourite at its best on a clear night, and Milky Way nights at a dark
/// place. Both need a real clear forecast (no forecast, no tap) and both are
/// spaced out so a planet that's well placed all autumn doesn't tap nightly.
library;

import '../plan/night_plan.dart';
import '../models/sky_event.dart';
import '../sky/astro.dart';
import '../sky/sun.dart';
import '../sky/tonight.dart';
import '../sky/visibility.dart';
import '../weather/cloud_forecast.dart';

/// When each standing alert last fired (or is planned to), by [standingKey].
typedef StandingLog = Map<String, DateTime>;

/// At most one favourite tap per thing in this long.
const favouriteSpacing = Duration(days: 6);

/// At most one Milky Way tap per place in this long.
const milkyWaySpacing = Duration(days: 3);

/// How far ahead of a Milky Way night somewhere else we tap, to leave time
/// to get there.
const milkyWayTripLead = Duration(hours: 3);

/// The log key for a standing alert: one per favourite, one per place.
String? standingKey(SkyEvent e) => switch (e.type) {
      SkyEventType.favourite => 'fav:${e.details['favourite']}',
      SkyEventType.milkyWayNight => 'mw:${e.details['placeKey']}',
      _ => null,
    };

bool _spacedOut(StandingLog log, String key, DateTime at, Duration spacing) {
  final last = log[key];
  if (last == null) return true;
  final gap = at.difference(last).abs();
  // The same night's tap (re-planned on a later refresh) still counts as
  // this one; any other within the spacing is too soon.
  return gap < const Duration(hours: 12) || gap >= spacing;
}

/// Clear enough for a tap: forecast says so, not just "no forecast".
bool _clearAt(CloudForecast? weather, DateTime t, {int maxCover = 30}) {
  final s = weather?.sampleAt(t);
  return s != null && s.coverPercent <= maxCover && (s.precipProbability ?? 0) < 40;
}

String _dayKey(DateTime utc) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}';
}

/// One tap per favourite, on the first of [nights] (tonight first) when it's
/// easy or good to see, high enough, and the forecast is clear at its best.
List<SkyEvent> favouriteEvents({
  required List<String> favourites,
  required List<NightPlan> nights,
  required CloudForecast? weather,
  required Map<String, String> names,
  required StandingLog log,
  required DateTime now,
}) {
  final out = <SkyEvent>[];
  for (final id in favourites) {
    for (final n in nights) {
      final w = n.window;
      final s = n.sightings[id];
      if (w == null || s == null) continue;
      if (s.verdict != Seeability.great && s.verdict != Seeability.good) continue;
      if (s.altDeg < 15 || !s.best.isAfter(now)) continue;
      if (!_clearAt(weather, s.best)) continue;
      if (!_spacedOut(log, 'fav:$id', s.best, favouriteSpacing)) break;
      out.add(SkyEvent(
        id: 'fav:$id:${_dayKey(w.start)}',
        type: SkyEventType.favourite,
        start: s.best,
        peak: s.best,
        end: s.best.add(const Duration(minutes: 30)),
        peakElevationDeg: s.altDeg,
        riseAzimuthDeg: s.azDeg,
        peakAzimuthDeg: s.azDeg,
        setAzimuthDeg: s.azDeg,
        cloudCoverPercent: weather?.coverAt(s.best),
        details: {'favourite': id, 'name': names[id] ?? id},
      ));
      break;
    }
  }
  return out;
}

/// The next [count] dark windows from [now], back to back: the rest of
/// tonight (or tonight), then the following nights.
List<({DateTime start, DateTime end})> darkWindows(DateTime now, double lat, double lon, {int count = 2}) {
  final out = <({DateTime start, DateTime end})>[];
  var at = now;
  for (var i = 0; i < count; i++) {
    final w = tonightWindow(at, lat, lon);
    if (w == null) break;
    out.add(w);
    at = w.end.add(const Duration(hours: 1));
  }
  return out;
}

/// Somewhere dark to check for Milky Way nights.
typedef DarkPlace = ({String name, double lat, double lon, bool here, CloudForecast? weather});

// The two brightest stretches of the Milky Way (J2000).
const _galacticCentre = Equatorial(266.4, -28.9, 1);
const _cygnus = Equatorial(305.0, 40.0, 1);

/// Where the bright Milky Way is at [t], or null when it's too low to be
/// worth it: the core 10° up, or the Cygnus clouds 30° up.
Horizontal? milkyWayUp(DateTime t, double lat, double lon) {
  final core = toHorizontal(_galacticCentre, t, lat, lon);
  if (core.altitudeDeg >= 10) return core;
  final cyg = toHorizontal(_cygnus, t, lat, lon);
  return cyg.altitudeDeg >= 30 ? cyg : null;
}

/// Astronomically dark, the Moon down (or a thin crescent), the Milky Way
/// up and the forecast clear, all at once.
bool milkyWayGood(DateTime t, double lat, double lon, CloudForecast? weather) =>
    sunAltitudeDeg(t, lat, lon) <= -18 &&
    (moonHorizontal(t, lat, lon).altitudeDeg < -1 || moonIllumination(t) < 0.12) &&
    milkyWayUp(t, lat, lon) != null &&
    _clearAt(weather, t, maxCover: 25);

/// A tap for each dark place's first Milky Way night in the next [days]: a
/// run of at least two hours that is [milkyWayGood] throughout.
List<SkyEvent> milkyWayEvents({
  required List<DarkPlace> places,
  required DateTime now,
  required StandingLog log,
  int days = 2,
}) {
  const step = Duration(minutes: 30);
  final out = <SkyEvent>[];
  for (final p in places) {
    final placeKey = '${p.lat.toStringAsFixed(1)},${p.lon.toStringAsFixed(1)}';
    for (final w in darkWindows(now, p.lat, p.lon, count: days)) {
      // Longest good run, sampled every half hour.
      DateTime? runStart, bestStart, bestEnd;
      for (var t = w.start; !t.isAfter(w.end); t = t.add(step)) {
        final good = t.isAfter(now) && milkyWayGood(t, p.lat, p.lon, p.weather);
        if (good) {
          runStart ??= t;
          if (bestStart == null || t.difference(runStart) > bestEnd!.difference(bestStart)) {
            bestStart = runStart;
            bestEnd = t;
          }
        } else {
          runStart = null;
        }
      }
      if (bestStart == null || bestEnd!.difference(bestStart) < const Duration(hours: 2)) continue;
      if (!_spacedOut(log, 'mw:$placeKey', bestStart, milkyWaySpacing)) break;
      final mid = bestStart.add(bestEnd.difference(bestStart) ~/ 2);
      final where = milkyWayUp(mid, p.lat, p.lon)!;
      var cover = 0;
      for (var t = bestStart; !t.isAfter(bestEnd); t = t.add(step)) {
        final c = p.weather?.coverAt(t) ?? 0;
        if (c > cover) cover = c;
      }
      out.add(SkyEvent(
        id: 'milkyway:$placeKey:${_dayKey(w.start)}',
        type: SkyEventType.milkyWayNight,
        start: bestStart,
        peak: mid,
        end: bestEnd,
        peakElevationDeg: where.altitudeDeg,
        riseAzimuthDeg: where.azimuthDeg,
        peakAzimuthDeg: where.azimuthDeg,
        setAzimuthDeg: where.azimuthDeg,
        cloudCoverPercent: cover,
        details: {'place': p.name, 'here': p.here, 'placeKey': placeKey, 'lat': p.lat, 'lon': p.lon},
      ));
      break;
    }
  }
  return out;
}

/// The log after planning: what's planned now is recorded at its fire time;
/// a tap that was planned for later but has dropped out (the forecast turned)
/// is forgotten so another night can have it; taps that already fired stay
/// until they're two weeks old.
StandingLog updateStandingLog(
  StandingLog log,
  Iterable<({SkyEvent event, DateTime fireAt})> planned,
  DateTime now,
) {
  final next = <String, DateTime>{};
  final plannedKeys = <String>{};
  for (final p in planned) {
    final key = standingKey(p.event);
    if (key == null) continue;
    plannedKeys.add(key);
    next[key] = p.fireAt;
  }
  for (final MapEntry(:key, value: at) in log.entries) {
    if (plannedKeys.contains(key)) continue;
    if (at.isAfter(now)) continue; // planned, then dropped: never fired
    if (now.difference(at) > const Duration(days: 14)) continue;
    next[key] = at;
  }
  return next;
}
