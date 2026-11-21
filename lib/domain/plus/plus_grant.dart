/// How long this phone goes on believing it has LookUp+. Pure.
///
/// The store is the only one who knows: it says so at a purchase, on every
/// launch (`PlusService.recheck`) and in the background refresh. What it
/// says is a [PlusNews]; [PlusGrant.apply] turns that into the saved
/// settings, and [PlusGrant.asOf] lets a subscription run out by the clock
/// when the store hasn't been heard from. Nothing is kept on a server.
library;

import 'dart:convert';

import '../models/settings.dart';

/// One answer from the store about LookUp+.
sealed class PlusNews {
  const PlusNews();
}

/// The store vouches for LookUp+ right now. [until] is when the paid period
/// ends: null when the store gave no date.
final class PlusOwned extends PlusNews {
  const PlusOwned({this.until});
  final DateTime? until;
}

/// The store answered, and the account owns no LookUp+: the subscription ran
/// out, or this is a different Apple ID.
final class PlusNotListed extends PlusNews {
  const PlusNotListed();
}

/// The store took it back: a refund, or a family share withdrawn.
final class PlusRevoked extends PlusNews {
  const PlusRevoked();
}

abstract final class PlusGrant {
  /// How long past a subscription's end LookUp+ holds with no word of a
  /// renewal. The renewal is read whenever the app or its background refresh
  /// runs; this covers a phone where neither has, and Apple's own billing
  /// grace (16 days at most).
  static const grace = Duration(days: 16);

  /// How long an empty answer from the store is doubted. While the period
  /// it vouched for is still running (or it gave no date), from the first
  /// empty answer: the store can come back empty for a moment, and someone
  /// who has paid mustn't lose their alerts to one bad answer, however long
  /// ago the store last vouched. Once the period has ended, from its end (or
  /// a later vouch): a phone that has been offline (a dark site, say)
  /// hasn't heard of a renewal yet. After a refund or a real lapse the
  /// answer stays empty.
  static const doubt = Duration(days: 3);

  /// Whether the saved LookUp+ still stands at [t].
  static bool holdsAt(LookUpSettings s, DateTime t) =>
      s.isPlus && (s.plusUntil == null || !t.isAfter(s.plusUntil!.add(grace)));

  /// [s] as it stands at [now]: LookUp+ is off once its period and the
  /// [grace] have run out. The end date stays, so a late renewal is still
  /// looked for.
  static LookUpSettings asOf(LookUpSettings s, DateTime now) =>
      s.isPlus && !holdsAt(s, now) ? s.copyWith(isPlus: false) : s;

  /// [s] after the store said [news] at [now].
  static LookUpSettings apply(LookUpSettings s, PlusNews news, DateTime now) {
    switch (news) {
      case PlusOwned(:final until):
        return s.copyWith(isPlus: true, plusUntil: until, forgetPlusUntil: until == null, plusSeenAt: now, forgetPlusDoubt: true);
      case PlusRevoked():
        return _off(s);
      case PlusNotListed():
        if (!s.isPlus) return s.plusUntil == null ? s : s.copyWith(forgetPlusUntil: true);
        final until = s.plusUntil;
        if (until != null && now.isAfter(until)) {
          // The period it vouched for is over and it lists nothing: a lapse,
          // unless a renewal just hasn't been heard of yet.
          final seen = s.plusSeenAt;
          final from = seen != null && seen.isAfter(until) && !seen.isAfter(now) ? seen : until;
          return now.difference(from) > doubt ? _off(s) : s;
        }
        // Still inside a period it vouched for (or it never gave a date):
        // the doubt starts at the first empty answer, not at the last vouch,
        // which may be long ago on a phone that's rarely opened. A start in
        // the future (the clock was changed) starts again.
        final first = s.plusDoubtAt;
        if (first == null || first.isAfter(now)) return s.copyWith(plusDoubtAt: now);
        return now.difference(first) > doubt ? _off(s) : s;
    }
  }

  static LookUpSettings _off(LookUpSettings s) =>
      s.isPlus || s.plusUntil != null ? s.copyWith(isPlus: false, forgetPlusUntil: true, forgetPlusDoubt: true) : s;
}

/// What one store transaction says about itself. From StoreKit 2's JSON,
/// `expiresDate` and `revocationDate` (milliseconds); from Google Play's
/// purchase JSON, `purchaseState` (0 is paid; 4 is pending: a cash or slow
/// payment that hasn't gone through, which Play still lists). Anything else
/// reads as "no end date, not taken back".
class StoreTransaction {
  const StoreTransaction({this.expires, this.revoked = false, this.upgraded = false, this.unpaid = false});

  factory StoreTransaction.read(String json) {
    try {
      final j = jsonDecode(json);
      if (j is! Map) return const StoreTransaction();
      final expires = j['expiresDate'];
      return StoreTransaction(
        expires: expires is num ? DateTime.fromMillisecondsSinceEpoch(expires.round(), isUtc: true) : null,
        revoked: j['revocationDate'] != null,
        upgraded: j['isUpgraded'] == true,
        unpaid: j['purchaseState'] is num && j['purchaseState'] != 0,
      );
    } catch (_) {
      return const StoreTransaction();
    }
  }

  /// When the paid period ends. Null for a one-off purchase.
  final DateTime? expires;

  /// Refunded, or a family share withdrawn.
  final bool revoked;

  /// Replaced by a higher plan in the same group; the new plan has its own.
  final bool upgraded;

  /// Google Play lists it, but it isn't paid for (pending, or cancelled).
  final bool unpaid;

  /// Still paid for at [now].
  bool activeAt(DateTime now) => !revoked && !upgraded && !unpaid && (expires == null || expires!.isAfter(now));
}
