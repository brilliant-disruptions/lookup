/// What Pip leads you to in the sky camera. Unless you pick, Pip goes to
/// the thing most worth finding: something going over right now first, then
/// the brightest planet, then the Moon, then the rest, brightest first.
/// Anything barely above the horizon is skipped. "Find something else"
/// steps through the same order.
library;

class GuideCandidate {
  const GuideCandidate({required this.id, required this.kind, required this.mag, required this.altitudeDeg, this.live = false});
  final String id;

  /// 'pass', 'planet', 'moon' or anything else.
  final String kind;
  final double mag, altitudeDeg;

  /// A pass going over now.
  final bool live;
}

/// High enough to find: clear of trees and rooftops.
const guideMinAltitudeDeg = 5.0;

/// The candidates in the order Pip offers them.
List<GuideCandidate> guideOrder(Iterable<GuideCandidate> all) {
  int rank(GuideCandidate c) => c.live
      ? 0
      : switch (c.kind) {
          'planet' => 1,
          'moon' => 2,
          _ => 3,
        };
  return [
    for (final c in all)
      if (c.altitudeDeg >= guideMinAltitudeDeg || c.live) c,
  ]..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.mag.compareTo(b.mag);
    });
}

/// Who Pip leads to: [chosen] while it's still up, otherwise the first in
/// [guideOrder]. Null when nothing is up.
GuideCandidate? guideTarget(Iterable<GuideCandidate> all, {String? chosen}) {
  final order = guideOrder(all);
  return order.where((c) => c.id == chosen).firstOrNull ?? order.firstOrNull;
}

/// "Find something else": the one after [current], wrapping round.
GuideCandidate? nextGuideTarget(Iterable<GuideCandidate> all, String? current) {
  final order = guideOrder(all);
  if (order.isEmpty) return null;
  final i = order.indexWhere((c) => c.id == current);
  return order[(i + 1) % order.length];
}
