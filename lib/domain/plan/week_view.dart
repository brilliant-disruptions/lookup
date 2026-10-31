/// The Week tab's two views of the same nights: each night as one bar from
/// 5 PM to 7 AM ("at a glance"), and two weeks as a calendar. A night runs
/// noon to noon, so a 5:40 AM pass belongs to the night before it.
library;

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

  /// What's on that night and still to come, by start time.
  final List<SkyEvent> events;

  /// Cloud cover each hour from 5 PM (14 values); null past the forecast.
  final List<int?> clouds;

  /// Already over (calendar days before tonight).
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

/// [weeks] whole weeks from the Monday of this week, for the calendar.
/// Days before tonight are [WeekNight.past] and carry nothing.
List<WeekNight> calendarNights(Iterable<SkyEvent> events, DateTime now, {CloudForecast? weather, int weeks = 2}) {
  final tonight = nightOf(now);
  final monday = DateTime(tonight.year, tonight.month, tonight.day - (tonight.weekday - DateTime.monday));
  return [
    for (var i = 0; i < weeks * 7; i++)
      () {
        final d = DateTime(monday.year, monday.month, monday.day + i);
        return _night(d, events, now, weather, past: d.isBefore(tonight));
      }(),
  ];
}
