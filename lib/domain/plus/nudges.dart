/// Every soft LookUp+ ask in one budget, so they never stack up into
/// nagging. A soft ask is LookUp offering LookUp+ without being asked: the
/// storm card, "You missed it", "LookUp+ near you", the caught-it offers.
/// Hitting a limit you chose to try (a fourth night, a second place, an old
/// night in Explore) isn't one: that's always answered.
///
/// - Never on LookUp+.
/// - At most one per app session (whichever showed first keeps the slot).
/// - None in the first two days after setting up, apart from the one-time
///   offer at the end of onboarding, and a storm (time-critical: it's what
///   they installed for).
/// - After two "Not now"s (or closing the offer without starting a trial),
///   no more soft asks at all.
///
/// Each ask keeps its own cadence on top (the Pro line weekly, "You missed
/// it" weekly, "near you" snoozed for a week). Pure.
library;

enum SoftAsk {
  /// A geomagnetic storm tonight: aurora alerts (domain/plus/storm.dart).
  storm,

  /// A Plus-only sight went over them, clear, and they weren't told.
  missedIt,

  /// The real Plus-only taps coming over them this month.
  nearYou,

  /// After a catch: a dated Plus-only sight coming.
  caughtSight,

  /// After a catch: what the Pro camera would have done (pro_nudge.dart).
  proTip,
}

abstract final class NudgeBudget {
  /// The quiet start after setting up.
  static const quietStart = Duration(hours: 48);

  /// "Not now"s after which soft asks stop.
  static const maxDeclines = 2;

  static bool allows(
    SoftAsk ask, {
    required bool isPlus,
    required DateTime now,
    DateTime? onboardedAt,
    int declines = 0,
    SoftAsk? shownThisSession,
  }) {
    if (isPlus) return false;
    if (declines >= maxDeclines) return false;
    if (shownThisSession != null && shownThisSession != ask) return false;
    if (ask != SoftAsk.storm && onboardedAt != null && now.toUtc().difference(onboardedAt.toUtc()) < quietStart) return false;
    return true;
  }

  /// Home shows one at most: the most time-critical of those it may show.
  static SoftAsk? pickForHome(Iterable<SoftAsk> eligible) {
    for (final a in const [SoftAsk.storm, SoftAsk.missedIt, SoftAsk.nearYou]) {
      if (eligible.contains(a)) return a;
    }
    return null;
  }
}
