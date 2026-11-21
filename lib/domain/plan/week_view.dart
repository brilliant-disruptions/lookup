/// Every day as one bar, midnight to midnight, in one list you scroll: the
/// week behind above, today, and the days ahead below. Each day holds only
/// its own 24 hours: a 5:40 AM pass is on its own morning's line, not the
/// evening before's. (Hours with nothing on are chopped out in `day_axis`.)
library;

import 'dart:math' as math;

import '../models/sky_event.dart';
import '../weather/cloud_forecast.dart';

/// A day is 24 hourly cloud readings from midnight.
const dayHours = 24;

/// The local date [t] falls on.
DateTime dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

class WeekNight {
  const WeekNight({required this.date, required this.events, required this.clouds, this.past = false});

  /// Local midnight at the start of the day.
  final DateTime date;

  /// What's on that night, by start time: still to come, or for a
  /// [past] night, what went over.
  final List<SkyEvent> events;

  /// Cloud cover each hour from midnight (24 values); null past the forecast.
  final List<int?> clouds;

  /// Already over: a night before tonight.
  final bool past;

  /// The things LookUp would tap you for.
  List<SkyEvent> get alerts => [for (final e in events) if (e.type.pushes) e];

  /// Worth knowing, never pushed: transits, the aurora outlook, satellites.
  List<SkyEvent> get quiet => [for (final e in events) if (!e.type.pushes) e];

  bool get hasForecast => clouds.any((c) => c != null);

  /// Mostly cloudy through the day by the forecast. Never true without
  /// one: no forecast isn't a cloudy night.
  bool get cloudy {
    final known = clouds.nonNulls.toList();
    if (known.length < 6) return false;
    return known.reduce((a, b) => a + b) / known.length >= 60;
  }
}

WeekNight _night(DateTime date, Iterable<SkyEvent> events, DateTime now, CloudForecast? weather, {bool past = false}) =>
    WeekNight(
      date: date,
      past: past,
      events: [
        for (final e in events)
          if (!past && e.end.isAfter(now.toUtc()) && dayOf(e.start) == date) e,
      ]..sort((a, b) => a.start.compareTo(b.start)),
      clouds: [
        for (var h = 0; h < dayHours; h++) weather?.coverAt(DateTime(date.year, date.month, date.day, h).toUtc()),
      ],
    );

/// Today and the next [count] − 1 days.
List<WeekNight> weekNights(Iterable<SkyEvent> events, DateTime now, {CloudForecast? weather, int count = 7}) {
  final first = dayOf(now);
  return [
    for (var i = 0; i < count; i++) _night(DateTime(first.year, first.month, first.day + i), events, now, weather),
  ];
}

/// The days to scroll through: [back] days before today (with what
/// went over, from [recent]), tonight, and the nights after: a week, or on
/// to the last night with something on, up to [ahead] nights in all. Past
/// that, nothing has been worked out yet, and an empty bar would say "no
/// sky". Past nights carry no clouds: the forecast only looks forward.
List<WeekNight> glanceNights(
  Iterable<SkyEvent> events,
  Iterable<SkyEvent> recent,
  DateTime now, {
  CloudForecast? weather,
  int back = 7,
  int ahead = 14,
}) {
  final tonight = dayOf(now);
  return [
    for (var i = back; i > 0; i--)
      () {
        final d = DateTime(tonight.year, tonight.month, tonight.day - i);
        return WeekNight(
          date: d,
          past: true,
          events: [for (final e in recent) if (dayOf(e.start) == d) e]..sort((a, b) => a.start.compareTo(b.start)),
          clouds: List<int?>.filled(dayHours, null),
        );
      }(),
    ...weekNights(events, now, weather: weather, count: math.max(7, math.min(ahead, _lastNight(events, now)))),
  ];
}

/// How many nights from tonight reach the last one with something on.
int _lastNight(Iterable<SkyEvent> events, DateTime now) {
  final tonight = dayOf(now);
  var n = 0;
  for (final e in events) {
    final d = dayOf(e.start).difference(tonight).inHours / 24;
    n = math.max(n, d.round() + 1);
  }
  return n;
}
