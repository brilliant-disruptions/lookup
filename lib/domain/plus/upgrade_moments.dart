/// When to offer LookUp+ beyond the moments that are about a specific thing
/// (a Plus event coming, a second saved place): only to people who are
/// really using the app, and rarely.
library;

import '../models/settings.dart';

/// "Really using it": this many things seen, or this long since they started.
const plusAskMinSeen = 2;
const plusAskMinAge = Duration(days: 7);

/// No more than one general ask in this long.
const plusAskSpacing = Duration(days: 7);

/// Whether to offer LookUp+ right after they've logged a sighting: they
/// have real use behind them, it's been a week since the last ask, and
/// they're not outside under red light.
bool offerPlusAfterSighting(LookUpSettings s, {required int seenCount, required DateTime now}) {
  if (s.isPlus || s.nightVision) return false;
  final started = s.firstOpenedAt;
  final using = seenCount >= plusAskMinSeen || (started != null && now.difference(started) >= plusAskMinAge);
  if (!using) return false;
  final last = s.lastPlusAskAt;
  return last == null || now.difference(last) >= plusAskSpacing;
}
