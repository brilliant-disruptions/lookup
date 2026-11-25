/// "This year": the big dates of the next twelve months where you are, all
/// worked out on the phone: full Moons (supermoons named), eclipses you can
/// see from here, meteor shower peaks, planets at their best, and the
/// equinoxes and solstices. Pure Dart.
library;

import '../models/sky_event.dart';
import '../sky/seasons.dart';
import 'eclipses.dart';
import 'meteors.dart';
import 'moonrise.dart';
import 'planet_highlights.dart';
import 'solar_eclipses.dart';

/// One line of the year: a sky event, or a season's start (not something to
/// look up at, so not a [SkyEvent]).
class YearEntry {
  const YearEntry.event(SkyEvent this.event) : season = null;
  const YearEntry.season(SeasonStart this.season) : event = null;

  final SkyEvent? event;
  final SeasonStart? season;

  DateTime get at => event?.start ?? season!.at;
}

/// How far ahead "This year" looks.
const yearAheadDays = 365;

List<YearEntry> yearAhead({
  required DateTime now,
  required double latDeg,
  required double lonDeg,
  int days = yearAheadDays,
}) {
  final u = now.toUtc();
  final to = u.add(Duration(days: days));
  final window = Duration(days: days);
  final out = <YearEntry>[
    for (final e in fullMoonRiseEvents(now: u, latDeg: latDeg, lonDeg: lonDeg, days: days)) YearEntry.event(e),
    for (final e in lunarEclipseEvents(now: u, latDeg: latDeg, lonDeg: lonDeg, window: window)) YearEntry.event(e),
    for (final e in solarEclipseEvents(now: u, latDeg: latDeg, lonDeg: lonDeg, window: window)) YearEntry.event(e),
    for (final e in meteorShowerEvents(now: u, latDeg: latDeg, lonDeg: lonDeg, window: window)) YearEntry.event(e),
    for (final e in planetHighlightEvents(now: u, to: to, latDeg: latDeg, lonDeg: lonDeg)) YearEntry.event(e),
    for (final s in seasonsBetween(u, to)) YearEntry.season(s),
  ];
  out.removeWhere((x) => x.at.isAfter(to) || (x.event != null && !x.event!.end.isAfter(u)));
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}
