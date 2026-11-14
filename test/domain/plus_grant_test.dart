import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/plus/plus_grant.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 21);
  const free = LookUpSettings();

  group('what the store says', () {
    test('a subscription is LookUp+ until its period ends', () {
      final until = now.add(const Duration(days: 30));
      final s = PlusGrant.apply(free, PlusOwned(until: until), now);
      expect(s.isPlus, isTrue);
      expect(s.plusUntil, until);
      expect(s.plusSeenAt, now);
    });

    test('the lifetime purchase has no end, and clears an older end date', () {
      final sub = PlusGrant.apply(free, PlusOwned(until: now.add(const Duration(days: 3))), now);
      final s = PlusGrant.apply(sub, const PlusOwned(), now);
      expect(s.isPlus, isTrue);
      expect(s.plusUntil, isNull);
    });

    test('a renewal moves the end date on', () {
      final first = PlusGrant.apply(free, PlusOwned(until: now.add(const Duration(days: 2))), now);
      final later = now.add(const Duration(days: 1));
      final s = PlusGrant.apply(first, PlusOwned(until: now.add(const Duration(days: 32))), later);
      expect(s.plusUntil, now.add(const Duration(days: 32)));
      expect(s.plusSeenAt, later);
    });

    test('a refund takes it away at once, lifetime included', () {
      final sub = PlusGrant.apply(free, PlusOwned(until: now.add(const Duration(days: 300))), now);
      expect(PlusGrant.apply(sub, const PlusRevoked(), now).isPlus, isFalse);
      final lifetime = PlusGrant.apply(free, const PlusOwned(), now);
      final s = PlusGrant.apply(lifetime, const PlusRevoked(), now);
      expect(s.isPlus, isFalse);
      expect(s.plusUntil, isNull);
    });

    test('a trial that was cancelled ends a few days after the store stops listing it', () {
      final trialEnd = now.add(const Duration(days: 7));
      final s = PlusGrant.apply(free, PlusOwned(until: trialEnd), now);
      // Still listed during the trial: nothing to take away yet.
      expect(PlusGrant.apply(s, PlusOwned(until: trialEnd), now.add(const Duration(days: 6))).isPlus, isTrue);
      // Just over: it may be a renewal this phone hasn't heard of (offline at a dark site).
      expect(PlusGrant.apply(s, const PlusNotListed(), trialEnd.add(const Duration(hours: 2))).isPlus, isTrue);
      final after = PlusGrant.apply(s, const PlusNotListed(), trialEnd.add(PlusGrant.doubt + const Duration(minutes: 1)));
      expect(after.isPlus, isFalse);
      expect(after.plusUntil, isNull);
    });

    test('the doubt after a period ends runs from the end, or from a later vouch (billing grace)', () {
      final end = now.add(const Duration(days: 30));
      var s = PlusGrant.apply(free, PlusOwned(until: end), now);
      // The store still listed it two days past its date, counted from then.
      final vouched = end.add(const Duration(days: 2));
      s = PlusGrant.apply(s, PlusOwned(until: vouched), vouched);
      expect(PlusGrant.apply(s, const PlusNotListed(), vouched.add(const Duration(days: 2))).isPlus, isTrue);
      expect(PlusGrant.apply(s, const PlusNotListed(), vouched.add(const Duration(days: 4))).isPlus, isFalse);
    });

    test('an empty answer while the period is still running is doubted for a few days, then believed', () {
      final s = PlusGrant.apply(free, PlusOwned(until: now.add(const Duration(days: 300))), now);
      final nextDay = PlusGrant.apply(s, const PlusNotListed(), now.add(const Duration(days: 1)));
      expect(nextDay.isPlus, isTrue, reason: 'one empty answer is not a refund');
      expect(nextDay.plusSeenAt, now, reason: 'the doubt runs from when the store last vouched');
      final later = PlusGrant.apply(nextDay, const PlusNotListed(), now.add(PlusGrant.doubt + const Duration(hours: 1)));
      expect(later.isPlus, isFalse);
    });

    test('the same for the lifetime purchase: a refund that was never announced still ends it', () {
      final s = PlusGrant.apply(free, const PlusOwned(), now);
      expect(PlusGrant.apply(s, const PlusNotListed(), now.add(const Duration(days: 2))).isPlus, isTrue);
      expect(PlusGrant.apply(s, const PlusNotListed(), now.add(const Duration(days: 4))).isPlus, isFalse);
    });

    test('the store vouching again resets the doubt', () {
      var s = PlusGrant.apply(free, const PlusOwned(), now);
      s = PlusGrant.apply(s, const PlusNotListed(), now.add(const Duration(days: 2)));
      s = PlusGrant.apply(s, const PlusOwned(), now.add(const Duration(days: 2, hours: 1)));
      s = PlusGrant.apply(s, const PlusNotListed(), now.add(const Duration(days: 4)));
      expect(s.isPlus, isTrue);
    });

    test('a LookUp+ saved by an older build (no dates) gets the same few days from its first empty answer', () {
      const old = LookUpSettings(isPlus: true);
      final first = PlusGrant.apply(old, const PlusNotListed(), now);
      expect(first.isPlus, isTrue);
      expect(first.plusSeenAt, now);
      expect(PlusGrant.apply(first, const PlusNotListed(), now.add(const Duration(days: 4))).isPlus, isFalse);
      // ...and is kept for good the moment the store vouches for it.
      expect(PlusGrant.apply(first, const PlusOwned(), now.add(const Duration(days: 1))).isPlus, isTrue);
    });

    test('an empty answer changes nothing for someone on free', () {
      expect(PlusGrant.apply(free, const PlusNotListed(), now), same(free));
      expect(PlusGrant.apply(free, const PlusRevoked(), now), same(free));
    });
  });

  group('running out by the clock', () {
    final until = now.add(const Duration(days: 30));
    final sub = PlusGrant.apply(free, PlusOwned(until: until), now);

    test('holds through the period and the grace after it', () {
      expect(PlusGrant.asOf(sub, until.subtract(const Duration(seconds: 1))).isPlus, isTrue);
      expect(PlusGrant.asOf(sub, until.add(PlusGrant.grace)).isPlus, isTrue);
    });

    test('then stops, with nobody having opened the app', () {
      final s = PlusGrant.asOf(sub, until.add(PlusGrant.grace + const Duration(seconds: 1)));
      expect(s.isPlus, isFalse);
      expect(s.plusUntil, until, reason: 'kept, so the background refresh still looks for a renewal');
    });

    test('a renewal read late brings it back', () {
      final late = until.add(PlusGrant.grace + const Duration(days: 5));
      final lapsed = PlusGrant.asOf(sub, late);
      final s = PlusGrant.apply(lapsed, PlusOwned(until: until.add(const Duration(days: 60))), late);
      expect(PlusGrant.asOf(s, late).isPlus, isTrue);
    });

    test('the lifetime purchase and an older build\'s LookUp+ never run out by the clock', () {
      final lifetime = PlusGrant.apply(free, const PlusOwned(), now);
      expect(PlusGrant.asOf(lifetime, now.add(const Duration(days: 4000))).isPlus, isTrue);
      const old = LookUpSettings(isPlus: true);
      expect(PlusGrant.asOf(old, now.add(const Duration(days: 4000))), same(old));
    });

    test('free stays free', () {
      expect(PlusGrant.asOf(free, now), same(free));
    });
  });

  test('the dates survive being saved', () {
    final s = PlusGrant.apply(free, PlusOwned(until: now.add(const Duration(days: 30))), now);
    final back = LookUpSettings.fromJson(s.toJson());
    expect(back.isPlus, isTrue);
    expect(back.plusUntil, s.plusUntil);
    expect(back.plusSeenAt, s.plusSeenAt);
    final old = LookUpSettings.fromJson({'isPlus': true});
    expect(old.isPlus, isTrue);
    expect(old.plusUntil, isNull);
    expect(old.plusSeenAt, isNull);
  });

  group('reading an App Store transaction', () {
    final t0 = now.millisecondsSinceEpoch;

    test('a running subscription', () {
      final t = StoreTransaction.read('{"productId":"lookup_plus_monthly","expiresDate":${t0 + 86400000}}');
      expect(t.expires, now.add(const Duration(days: 1)));
      expect(t.activeAt(now), isTrue);
    });

    test('an expired one', () {
      final t = StoreTransaction.read('{"expiresDate":${t0 - 1000}}');
      expect(t.activeAt(now), isFalse);
    });

    test('a refunded one, even with time left', () {
      final t = StoreTransaction.read('{"expiresDate":${t0 + 86400000},"revocationDate":${t0 - 5000},"revocationReason":0}');
      expect(t.revoked, isTrue);
      expect(t.activeAt(now), isFalse);
    });

    test('one replaced by an upgrade', () {
      final t = StoreTransaction.read('{"expiresDate":${t0 + 86400000},"isUpgraded":true}');
      expect(t.activeAt(now), isFalse);
    });

    test('the lifetime purchase has no end', () {
      final t = StoreTransaction.read('{"productId":"lookup_plus_lifetime","type":"Non-Consumable"}');
      expect(t.expires, isNull);
      expect(t.activeAt(now), isTrue);
    });

    test('anything unreadable says nothing either way', () {
      for (final text in ['', 'not json', '[]', '{"expiresDate":"soon"}']) {
        final t = StoreTransaction.read(text);
        expect(t.expires, isNull, reason: text);
        expect(t.revoked, isFalse, reason: text);
        expect(t.activeAt(now), isTrue, reason: text);
      }
    });
  });
}
