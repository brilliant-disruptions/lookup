/// "What LookUp+ would add near you": the real, dated taps a free user
/// won't get over the next few weeks. Feeds the soft card on Tonight, so
/// LookUp+ can be seen even when nothing Plus-only is in the next fortnight
/// the paywall looks at. Pure.
library;

import '../models/sky_event.dart';

class PlusPreview {
  const PlusPreview({required this.soonest, required this.count});

  /// The next few Plus-only alerts, soonest first (at most three).
  final List<SkyEvent> soonest;

  /// How many there are in the window.
  final int count;

  static const window = Duration(days: 30);

  /// How long "Not now" hides the card.
  static const snooze = Duration(days: 7);

  static PlusPreview of(Iterable<SkyEvent> events, DateTime now) {
    final u = now.toUtc();
    final ahead = [
      for (final e in events)
        if (e.plusOnly && e.type.pushes && e.details['past'] != true && e.start.isAfter(u) && e.start.isBefore(u.add(window))) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
    return PlusPreview(soonest: ahead.take(3).toList(), count: ahead.length);
  }

  /// Whether to show the card: free, not snoozed.
  static bool show({required bool isPlus, required DateTime? snoozedUntil, required DateTime now}) =>
      !isPlus && (snoozedUntil == null || !now.toUtc().isBefore(snoozedUntil));
}
