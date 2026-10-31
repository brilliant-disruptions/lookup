/// What to say the moment someone answers "Yes, I saw it": which sighting
/// this is for them, the badges it just earned, and what's next over them.
///
/// Pure: the "You caught it" screen draws this and nothing else, so the
/// words it uses (and the one place it mentions LookUp+) are tested here.
library;

import '../models/sky_event.dart';
import '../scheduling/alert_planner.dart';
import 'sky_log.dart';

class CatchMoment {
  const CatchMoment({required this.nth, required this.nthOfType, required this.newBadges, this.next, this.nextPlus});

  /// This sighting's place among everything they've seen (1 = their first).
  final int nth;

  /// Its place among sightings of the same kind (their 3rd ISS pass).
  final int nthOfType;

  /// Badges this very sighting earned, in the log's order.
  final List<Badge> newBadges;

  /// The next thing LookUp would tap them for on their plan, if any.
  final SkyEvent? next;

  /// For someone on free: the next thing only LookUp+ would tap them for.
  /// Always null for Plus. Never a not-pushed event (transits, outlooks).
  final SkyEvent? nextPlus;

  bool get isFirst => nth == 1;

  /// "Your first sighting", "Your 3rd sighting".
  String get countLine => isFirst ? 'Your first sighting' : 'Your ${ordinal(nth)} sighting';

  /// Build the moment for [eventId] from the log as it stands *after* the
  /// answer was stored. Returns null if the log has no "seen" for it (a
  /// "no" answer, or the store write failed).
  static CatchMoment? of({
    required SkyLog log,
    required String eventId,
    required Iterable<SkyEvent> upcoming,
    required DateTime now,
    required bool isPlus,
  }) {
    final chrono = log.seen.reversed.toList(); // oldest first
    final i = chrono.indexWhere((s) => s.eventId == eventId);
    if (i < 0) return null;
    final s = chrono[i];
    final type = s.inferredType;
    final nthOfType = type == null ? 1 : chrono.take(i + 1).where((x) => x.inferredType == type).length;
    final newBadges = [
      for (final b in log.badges)
        if (b.earnedAt == s.at) b,
    ];

    final u = now.toUtc();
    final ahead = upcoming.where((e) => e.id != eventId && e.type.pushes && e.start.isAfter(u)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final next = ahead.where((e) => isPlus || !e.plusOnly).firstOrNull;
    final nextPlus = isPlus ? null : AlertPlanner.plusOnlyAhead(ahead, u, max: 1).where((e) => e.id != eventId).firstOrNull;

    return CatchMoment(nth: i + 1, nthOfType: nthOfType, newBadges: newBadges, next: next, nextPlus: nextPlus);
  }
}

/// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st, 22nd.
String ordinal(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}
