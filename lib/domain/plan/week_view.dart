/// Every night as one bar from 5 PM to 7 AM ("at a glance"), in one list you
/// scroll: the week behind above, tonight, and the nights ahead below. A
/// night runs noon to noon, so a 5:40 AM pass belongs to the night before it.
library;

import 'dart:math' as math;

import '../models/sky_event.dart';
import '../weather/cloud_forecast.dart';

/// The bar starts at 5 PM local and runs 14 hours, to 7 AM.
const nightBarStartHour = 17;
const nightBarHours = 14;

/// The local date of the night [t] falls in (noon to noon).
DateTime nightOf(DateTime t) {
  final l = t.toLocal().subtract(const Duration(hours: 12));
  return DateTime(l.year, l.month, l.day);
}

/// Where [t] falls along its night's bar: 0 at 5 PM, 1 at 7 AM, clamped.
double barPosition(DateTime t) {
  final n = nightOf(t);
  final start = DateTime(n.year, n.month, n.day, nightBarStartHour);
  return (t.toLocal().difference(start).inMinutes / (nightBarHours * 60)).clamp(0.0, 1.0);
}

class WeekNight {
  const WeekNight({required this.date, required this.events, required this.clouds, this.past = false});

  /// Local midnight of the evening the night starts on.
  final DateTime date;

  /// What's on that night, by start time: still to come, or for a
  /// [past] night, what went over.
  final List<SkyEvent> events;

  /// Cloud cover each hour from 5 PM (14 values); null past the forecast.
  final List<int?> clouds;

  /// Already over: a night before tonight.
  final bool past;

  /// The things LookUp would tap you for.
  List<SkyEvent> get alerts => [for (final e in events) if (e.type.pushes) e];

  /// Worth knowing, never pushed: transits, the aurora outlook, satellites.
  List<SkyEvent> get quiet => [for (final e in events) if (!e.type.pushes) e];

  bool get hasForecast => clouds.any((c) => c != null);

  /// Mostly cloudy through the night by the forecast. Never true without
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
          if (!past && e.end.isAfter(now.toUtc()) && nightOf(e.start) == date) e,
      ]..sort((a, b) => a.start.compareTo(b.start)),
      clouds: [
        for (var h = 0; h < nightBarHours; h++)
          weather?.coverAt(DateTime(date.year, date.month, date.day, nightBarStartHour + h).toUtc()),
      ],
    );

/// Tonight and the next [count] − 1 nights.
List<WeekNight> weekNights(Iterable<SkyEvent> events, DateTime now, {CloudForecast? weather, int count = 7}) {
  final first = nightOf(now);
  return [
    for (var i = 0; i < count; i++) _night(DateTime(first.year, first.month, first.day + i), events, now, weather),
  ];
}

/// The nights to scroll through: [back] nights before tonight (with what
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
  final tonight = nightOf(now);
  return [
    for (var i = back; i > 0; i--)
      () {
        final d = DateTime(tonight.year, tonight.month, tonight.day - i);
        return WeekNight(
          date: d,
          past: true,
          events: [for (final e in recent) if (nightOf(e.start) == d) e]..sort((a, b) => a.start.compareTo(b.start)),
          clouds: List<int?>.filled(nightBarHours, null),
        );
      }(),
    ...weekNights(events, now, weather: weather, count: math.max(7, math.min(ahead, _lastNight(events, now)))),
  ];
}

/// How many nights from tonight reach the last one with something on.
int _lastNight(Iterable<SkyEvent> events, DateTime now) {
  final tonight = nightOf(now);
  var n = 0;
  for (final e in events) {
    final d = nightOf(e.start).difference(tonight).inHours / 24;
    n = math.max(n, d.round() + 1);
  }
  return n;
}
