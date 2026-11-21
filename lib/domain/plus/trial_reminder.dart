/// The "your trial ends in 2 days" notice the paywall's timeline promises.
/// Builds trust and cuts refunds. A trial is a first LookUp+ whose period
/// ends within a week or so (the yearly plan's 7 free days); a monthly or a
/// renewal is longer, and someone who had LookUp+ before gets no trial.
/// Pure.
library;

import '../models/settings.dart';
import 'plus_grant.dart';

/// How long before the end it comes.
const trialReminderBefore = Duration(days: 2);

/// When to remind, for [news] arriving on [before]; null if it isn't a trial
/// starting, or it's too late to say "2 days".
DateTime? trialReminderAt(LookUpSettings before, PlusNews news, DateTime now) {
  if (news is! PlusOwned) return null;
  final until = news.until;
  if (until == null || before.isPlus || before.plusUntil != null) return null;
  final u = now.toUtc();
  final left = until.toUtc().difference(u);
  if (left > const Duration(days: 8) || left <= trialReminderBefore) return null;
  return until.toUtc().subtract(trialReminderBefore);
}
