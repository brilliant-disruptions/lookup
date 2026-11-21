/// "Your week ahead": one note on Sunday evening about the coming week's
/// sights, so a quiet week for the station doesn't mean a silent app.
///
/// Only what LookUp would tap them for: kinds they have on, on their plan
/// (it never mentions LookUp+), never anything not pushed. A quiet week
/// says when the next thing is; with nothing at all coming it says
/// nothing. Off with `LookUpSettings.weekAhead`. Pure.
library;

import '../models/settings.dart';
import '../models/sky_event.dart';
import 'alert_planner.dart';

class WeekAheadNote {
  const WeekAheadNote({required this.at, required this.title, required this.body});
  final DateTime at;
  final String title, body;
}

abstract final class WeekAhead {
  /// Sunday, 5:40 PM local: before the evening's first passes.
  static const weekday = DateTime.sunday;
  static const minute = 17 * 60 + 40;

  /// The next Sunday at 5:40 PM local after [now] (as UTC).
  static DateTime nextSend(DateTime now) {
    final l = now.toLocal();
    var d = DateTime(l.year, l.month, l.day, minute ~/ 60, minute % 60);
    while (d.weekday != weekday || !d.isAfter(l)) {
      d = DateTime(d.year, d.month, d.day + 1, minute ~/ 60, minute % 60);
    }
    return d.toUtc();
  }

  static WeekAheadNote? of({required Iterable<SkyEvent> events, required LookUpSettings settings, required DateTime now}) {
    if (!settings.weekAhead || !settings.onboarded) return null;
    final at = nextSend(now);
    if (settings.quietHours.contains(minute)) return null;
    bool wanted(SkyEvent e) =>
        e.type.pushes &&
        e.details['past'] != true &&
        AlertPlanner.typeEnabled(e.type, settings) &&
        (settings.isPlus || !e.plusOnly) &&
        // "Pip will tap you" has to be true: not for something quiet hours
        // will keep silent, or worked out from elements too old to tap for.
        AlertPlanner.passesQuietHours(e, settings, e.start.toLocal().timeZoneOffset.inMinutes) &&
        AlertPlanner.elementsFresh(e);
    final ahead = [for (final e in events) if (wanted(e) && e.start.isAfter(at)) e]..sort((a, b) => a.start.compareTo(b.start));
    if (ahead.isEmpty) return null;
    final end = at.add(const Duration(days: 7));
    final week = ahead.where((e) => e.start.isBefore(end)).toList();
    if (week.isEmpty) {
      final next = ahead.first;
      return WeekAheadNote(
        at: at,
        title: 'A quiet week overhead',
        body: '${_capital(_one(next))} is next, on ${_day(next.start, at)}. Pip will tap you.',
      );
    }
    // Count by kind, in the order they first come.
    final kinds = <SkyEventType, List<SkyEvent>>{};
    for (final e in week) {
      (kinds[e.type] ??= []).add(e);
    }
    final parts = [for (final MapEntry(key: t, value: es) in kinds.entries) _many(t, es)].take(3).toList();
    final first = week.first;
    return WeekAheadNote(
      at: at,
      title: 'Your week ahead',
      body: '${_capital(_join(parts))} this week. First up: ${_day(first.start, at)} at ${_time(first.start)}.',
    );
  }

  static String _many(SkyEventType t, List<SkyEvent> es) {
    final n = es.length;
    String count(String one, String many) => n == 1 ? one : '$n $many';
    return switch (t) {
      SkyEventType.iss => count('a space station pass', 'space station passes'),
      SkyEventType.tiangong => count('a Tiangong pass', 'Tiangong passes'),
      SkyEventType.starlinkTrain => count('a Starlink train', 'Starlink trains'),
      SkyEventType.meteorShower => 'the ${es.first.details['shower'] ?? 'meteor shower'} at their best',
      SkyEventType.lunarEclipse => 'an eclipse of the Moon',
      SkyEventType.solarEclipse => 'an eclipse of the Sun',
      SkyEventType.planetPairing || SkyEventType.planetHighlight => count('a planet at its best', 'planet sights'),
      SkyEventType.rocketLaunch => count('a rocket launch you can see', 'rocket launches you can see'),
      SkyEventType.occultation => count('the Moon covering a star', 'Moon covers'),
      SkyEventType.fullMoonRise => 'the full Moon rising',
      SkyEventType.comet || SkyEventType.nova => 'a rare sight',
      _ => count('something to see', 'things to see'),
    };
  }

  static String _one(SkyEvent e) => _many(e.type, [e]);

  static String _join(List<String> p) => switch (p.length) {
        1 => p.first,
        2 => '${p[0]} and ${p[1]}',
        _ => '${p.sublist(0, p.length - 1).join(', ')} and ${p.last}',
      };

  static String _capital(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "Tuesday", or "Monday 1 Dec" when it's more than a week after [from].
  static String _day(DateTime utc, DateTime from) {
    final l = utc.toLocal();
    final far = utc.difference(from) > const Duration(days: 6);
    return far ? '${_days[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}' : _days[l.weekday - 1];
  }

  static String _time(DateTime utc) {
    final l = utc.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  }
}
