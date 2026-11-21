/// When LookUp asks for a rating: only straight after a real catch has
/// been celebrated, once someone has caught a few things and used the app
/// for a few days, and rarely. iOS and Android also cap how often their
/// prompt shows; this keeps LookUp well under that. Pure.
library;

abstract final class ReviewAsk {
  /// Catches before the first ask.
  static const minCatches = 3;

  /// Days after setting up before the first ask.
  static const settleIn = Duration(days: 3);

  /// Between asks.
  static const gap = Duration(days: 120);

  /// Asks, ever.
  static const maxAsks = 3;

  static bool due({
    required int catches,
    required DateTime now,
    required DateTime? onboardedAt,
    required DateTime? lastAskedAt,
    required int asks,
    bool practice = false,
  }) {
    if (practice || catches < minCatches || asks >= maxAsks) return false;
    final u = now.toUtc();
    if (onboardedAt == null || u.difference(onboardedAt.toUtc()) < settleIn) return false;
    if (lastAskedAt != null && u.difference(lastAskedAt.toUtc()) < gap) return false;
    return true;
  }
}
