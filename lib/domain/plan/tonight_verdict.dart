/// The one answer Tonight opens with: should I go out, and when? Pure; the
/// words with times in them are the UI's (`ui/verdict_card.dart`).
///
/// It must never say "go" through cloud: a thing tonight under heavy cloud
/// is "stay in" with the reason, middling cloud is "worth a look", and only
/// a clear (or not yet forecast) sky gets "go".
library;

import '../models/sky_event.dart';
import '../sky/visibility.dart';

enum VerdictKind {
  /// Something worth seeing tonight, and the sky should be clear for it.
  go,

  /// It's up right now.
  live,

  /// Something tonight, through some cloud.
  maybe,

  /// Not tonight: cloud over the thing, or over the whole night.
  stayIn,

  /// Nothing passes over, but the sky is clear and a planet is up.
  clearNight,

  /// Nothing to step out for tonight.
  quiet,
}

class TonightVerdict {
  const TonightVerdict(this.kind, {this.event, this.nextGood, this.cloudedOut = false});
  final VerdictKind kind;

  /// The thing tonight the verdict is about (also for stayIn when it's
  /// clouded out, so the card can say what's being missed).
  final SkyEvent? event;

  /// The next thing after tonight that isn't forecast cloudy, for the
  /// "not tonight" verdicts.
  final SkyEvent? nextGood;

  /// Stay in because of the cloud forecast (rather than nothing to see).
  final bool cloudedOut;

  /// Cloud at the event (percent) at or under which it's a "go".
  static const goCloud = 40;

  /// Over this it's "stay in"; between, "worth a look".
  static const maybeCloud = 70;

  static bool _clearEnough(SkyEvent e) => (e.cloudCoverPercent ?? 0) <= goCloud;

  /// [events] are the pushed things ahead, soonest first (as Home has them);
  /// [tonightEnds] is when this night's dark ends (or a stand-in ~18 h out);
  /// [outlook] tonight's clouds if known; [planetUp] whether a bright
  /// planet is well placed tonight.
  static TonightVerdict decide({
    required List<SkyEvent> events,
    required DateTime now,
    required DateTime tonightEnds,
    NightOutlook? outlook,
    bool planetUp = false,
  }) {
    final u = now.toUtc();
    final ahead = [
      for (final e in events)
        if (e.type.pushes && e.details['past'] != true && e.end.isAfter(u)) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final tonight = ahead.where((e) => e.start.isBefore(tonightEnds)).firstOrNull;
    SkyEvent? nextGoodAfter(DateTime t) => ahead.where((e) => !e.start.isBefore(t) && _clearEnough(e)).firstOrNull;

    if (tonight != null) {
      final cloud = tonight.cloudCoverPercent;
      if (cloud != null && cloud > maybeCloud) {
        return TonightVerdict(VerdictKind.stayIn, event: tonight, nextGood: nextGoodAfter(tonightEnds), cloudedOut: true);
      }
      if (!tonight.start.isAfter(u)) return TonightVerdict(VerdictKind.live, event: tonight);
      if (cloud != null && cloud > goCloud) return TonightVerdict(VerdictKind.maybe, event: tonight);
      return TonightVerdict(VerdictKind.go, event: tonight);
    }

    final next = nextGoodAfter(tonightEnds);
    final shape = outlook?.shape;
    if (shape == 'cloudy') return TonightVerdict(VerdictKind.stayIn, nextGood: next, cloudedOut: true);
    final clearish =
        shape == 'clear' || shape == 'clouds-later' || shape == 'clearing' || (shape == 'patchy' && outlook?.bestStart != null);
    if (clearish && planetUp) return TonightVerdict(VerdictKind.clearNight, nextGood: next);
    return TonightVerdict(VerdictKind.quiet, nextGood: next);
  }
}
