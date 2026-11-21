/// Asks the store for a rating at the end of a celebrated catch, when
/// [ReviewAsk] says it's time. The store decides whether to show it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';

import '../domain/log/review_ask.dart';
import '../state/providers.dart';

/// The store's own prompt (swapped in tests).
final reviewPromptProvider = Provider<Future<void> Function()>((_) => () async {
      final r = InAppReview.instance;
      if (await r.isAvailable()) await r.requestReview();
    });

Future<void> askForReviewIfDue(ProviderContainer c) async {
  try {
    final s = await c.read(settingsProvider.future);
    final log = await c.read(skyLogProvider.future);
    final now = DateTime.now();
    if (!ReviewAsk.due(catches: log.total, now: now, onboardedAt: s.onboardedAt, lastAskedAt: s.reviewAskedAt, asks: s.reviewAsks)) return;
    await c.read(settingsProvider.notifier).edit((x) => x.copyWith(reviewAskedAt: now.toUtc(), reviewAsks: x.reviewAsks + 1));
    await c.read(reviewPromptProvider)();
  } catch (_) {
    // A rating prompt is never worth an error.
  }
}
