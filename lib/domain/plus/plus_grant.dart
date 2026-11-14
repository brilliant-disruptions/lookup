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
/// ends: null for the lifetime purchase, or when the store gave no date.
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

  /// How long an empty answer from the store is doubted, counted from when
  /// it last vouched (or from the period's end, once that has passed). The
  /// store can come back empty for a moment, and a phone that has been
  /// offline (a dark site, say) hasn't heard of a renewal yet; after a
  /// refund or a real lapse the answer stays empty.
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
        return s.copyWith(isPlus: true, plusUntil: until, forgetPlusUntil: until == null, plusSeenAt: now);
      case PlusRevoked():
        return _off(s);
      case PlusNotListed():
        if (!s.isPlus) return s.plusUntil == null ? s : s.copyWith(forgetPlusUntil: true);
        final until = s.plusUntil;
        final seen = s.plusSeenAt;
        final over = until != null && now.isAfter(until);
        final from = over && (seen == null || until.isAfter(seen)) ? until : seen;
        // An older build's LookUp+ has no dates: the doubt starts now.
        if (from == null) return s.copyWith(plusSeenAt: now);
        return now.difference(from) > doubt ? _off(s) : s;
    }
  }

  static LookUpSettings _off(LookUpSettings s) =>
      s.isPlus || s.plusUntil != null ? s.copyWith(isPlus: false, forgetPlusUntil: true) : s;
}

/// What one App Store transaction says about itself, read from StoreKit 2's
/// JSON for it (`expiresDate` and `revocationDate` are milliseconds).
/// Anything else, Google Play's purchase JSON included, reads as "no end
/// date, not taken back".
class StoreTransaction {
  const StoreTransaction({this.expires, this.revoked = false, this.upgraded = false});

  factory StoreTransaction.read(String json) {
    try {
      final j = jsonDecode(json);
      if (j is! Map) return const StoreTransaction();
      final expires = j['expiresDate'];
      return StoreTransaction(
        expires: expires is num ? DateTime.fromMillisecondsSinceEpoch(expires.round(), isUtc: true) : null,
        revoked: j['revocationDate'] != null,
        upgraded: j['isUpgraded'] == true,
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

  /// Still paid for at [now].
  bool activeAt(DateTime now) => !revoked && !upgraded && (expires == null || expires!.isAfter(now));
}
