import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plus/free_plan.dart';
import 'package:lookup/domain/plus/missed_it.dart';
import 'package:lookup/domain/plus/nudges.dart';
import 'package:lookup/domain/plus/plus_grant.dart';
import 'package:lookup/domain/plus/storm.dart';
import 'package:lookup/domain/plus/trial_reminder.dart';

final now = DateTime.utc(2026, 11, 21, 14);

SkyEvent ev(String id, SkyEventType type, DateTime start,
        {Duration length = const Duration(minutes: 5), int? cloud, Map<String, Object?> details = const {}}) =>
    SkyEvent(
      id: id,
      type: type,
      start: start,
      peak: start.add(length ~/ 2),
      end: start.add(length),
      peakElevationDeg: 40,
      riseAzimuthDeg: 270,
      peakAzimuthDeg: 0,
      setAzimuthDeg: 90,
      cloudCoverPercent: cloud,
      details: details,
    );

void main() {
  group('one budget for every soft ask', () {
    bool allows(SoftAsk a, {bool plus = false, DateTime? onboarded, int declines = 0, SoftAsk? session}) => NudgeBudget.allows(a,
        isPlus: plus, now: now, onboardedAt: onboarded ?? now.subtract(const Duration(days: 30)), declines: declines, shownThisSession: session);

    test('never on LookUp+', () {
      for (final a in SoftAsk.values) {
        expect(allows(a, plus: true), isFalse, reason: '$a');
      }
    });

    test('one per session: whichever showed first keeps the slot', () {
      expect(allows(SoftAsk.missedIt), isTrue);
      expect(allows(SoftAsk.missedIt, session: SoftAsk.missedIt), isTrue, reason: 'the same one, still on screen');
      expect(allows(SoftAsk.proTip, session: SoftAsk.missedIt), isFalse);
      expect(allows(SoftAsk.storm, session: SoftAsk.nearYou), isFalse);
    });

    test('quiet for two days after setting up, except a storm', () {
      final fresh = now.subtract(const Duration(hours: 30));
      for (final a in SoftAsk.values.where((a) => a != SoftAsk.storm)) {
        expect(allows(a, onboarded: fresh), isFalse, reason: '$a');
      }
      expect(allows(SoftAsk.storm, onboarded: fresh), isTrue, reason: 'it\'s what they installed for');
      expect(allows(SoftAsk.nearYou, onboarded: now.subtract(const Duration(hours: 48))), isTrue);
    });

    test('two "Not now"s and soft asks stop, storms included', () {
      expect(allows(SoftAsk.nearYou, declines: 1), isTrue);
      for (final a in SoftAsk.values) {
        expect(allows(a, declines: 2), isFalse, reason: '$a');
      }
    });

    test('Home shows the most time-critical one', () {
      expect(NudgeBudget.pickForHome([SoftAsk.nearYou, SoftAsk.missedIt, SoftAsk.storm]), SoftAsk.storm);
      expect(NudgeBudget.pickForHome([SoftAsk.nearYou, SoftAsk.missedIt]), SoftAsk.missedIt);
      expect(NudgeBudget.pickForHome([SoftAsk.nearYou]), SoftAsk.nearYou);
      expect(NudgeBudget.pickForHome(const []), isNull);
    });
  });

  group('You missed it: only when it is true', () {
    final lastNight = DateTime.utc(2026, 11, 21, 3, 12);
    final starlink = ev('starlink-x', SkyEventType.starlinkTrain, lastNight, cloud: 10, details: {'past': true});

    test('a Plus-only sight, last night, clear: said', () {
      expect(missedIt(recent: [starlink], now: now)?.id, 'starlink-x');
    });

    test('never through cloud, and unknown cloud is never "clear"', () {
      expect(missedIt(recent: [ev('s', SkyEventType.starlinkTrain, lastNight, cloud: 45, details: {'past': true})], now: now), isNull);
      expect(missedIt(recent: [ev('s', SkyEventType.starlinkTrain, lastNight, details: {'past': true})], now: now), isNull);
    });

    test('never for what free already alerts (the ISS), nor for what is never pushed', () {
      expect(missedIt(recent: [ev('iss', SkyEventType.iss, lastNight, cloud: 0, details: {'past': true})], now: now), isNull);
      expect(missedIt(recent: [ev('o', SkyEventType.auroraOutlook, lastNight, cloud: 0, details: {'past': true})], now: now), isNull);
    });

    test('an aurora night that met the bar, in a clear dark sky, counts', () {
      final a = ev('aurora-past:x', SkyEventType.auroraNow, DateTime.utc(2026, 11, 21, 2), length: const Duration(hours: 3), cloud: 5, details: {'past': true, 'kp': 6.3});
      expect(missedIt(recent: [a], now: now)?.id, 'aurora-past:x');
    });

    test('only last night: not something from days ago, not something still to come', () {
      expect(missedIt(recent: [ev('s', SkyEventType.starlinkTrain, now.subtract(const Duration(days: 3)), cloud: 0, details: {'past': true})], now: now), isNull);
      expect(missedIt(recent: [ev('s', SkyEventType.starlinkTrain, now.add(const Duration(hours: 5)), cloud: 0, details: {'past': true})], now: now), isNull);
    });

    test('once per sight, and at most once a week', () {
      expect(missedIt(recent: [starlink], now: now, toldId: 'starlink-x'), isNull);
      expect(missedIt(recent: [starlink], now: now, toldAt: now.subtract(const Duration(days: 3))), isNull);
      expect(missedIt(recent: [starlink], now: now, toldAt: now.subtract(const Duration(days: 8)))?.id, 'starlink-x');
    });

    test('the most recent one', () {
      final earlier = ev('tiangong-x', SkyEventType.tiangong, lastNight.subtract(const Duration(hours: 4)), cloud: 0, details: {'past': true});
      expect(missedIt(recent: [earlier, starlink], now: now)?.id, 'starlink-x');
    });
  });

  group('storm tonight', () {
    SkyEvent outlook(double kp, {DateTime? start}) => ev('aurora-outlook:x', SkyEventType.auroraOutlook, start ?? now.add(const Duration(hours: 8)),
        length: const Duration(hours: 6), details: {'kp': kp, 'kpNeeded': 6.0, 'level': 'possible'});

    test('the outlook says it could reach them and Kp is storm strength', () {
      expect(stormTonight([outlook(6.7)], now)?.id, 'aurora-outlook:x');
      expect(stormTonight([outlook(5)], now), isNotNull);
    });

    test('not an ordinary night, not one that has ended, not one days away', () {
      expect(stormTonight([outlook(4.3)], now), isNull);
      expect(stormTonight([outlook(7, start: now.subtract(const Duration(hours: 9)))], now), isNull);
      expect(stormTonight([outlook(7, start: now.add(const Duration(days: 2)))], now), isNull);
    });
  });

  group('trial reminder', () {
    const fresh = LookUpSettings();
    test('a first LookUp+ ending in 7 days is a trial: remind 2 days before the end', () {
      final until = now.add(const Duration(days: 7));
      expect(trialReminderAt(fresh, PlusOwned(until: until, bought: true), now), until.subtract(const Duration(days: 2)));
    });

    // A long-time subscriber who reinstalls a few days before their renewal
    // looks just like a trial by its dates; it wasn't bought just now.
    test('never for LookUp+ that was found already owned (a restore, a new phone)', () {
      expect(trialReminderAt(fresh, PlusOwned(until: now.add(const Duration(days: 5))), now), isNull);
    });

    test('not a monthly, one with no end, a renewal, or someone who had it before', () {
      expect(trialReminderAt(fresh, PlusOwned(until: now.add(const Duration(days: 30)), bought: true), now), isNull);
      expect(trialReminderAt(fresh, const PlusOwned(bought: true), now), isNull);
      expect(trialReminderAt(fresh.copyWith(isPlus: true), PlusOwned(until: now.add(const Duration(days: 7)), bought: true), now), isNull);
      expect(trialReminderAt(fresh.copyWith(plusUntil: DateTime.utc(2026, 1, 1)), PlusOwned(until: now.add(const Duration(days: 7)), bought: true), now), isNull);
      expect(trialReminderAt(fresh, const PlusNotListed(), now), isNull);
    });
  });

  group('history: a week either side and three famous nights free', () {
    test('free within a week of now; LookUp+ anywhere', () {
      expect(FreePlan.canVisit(now.add(const Duration(days: 7)), now, isPlus: false), isTrue);
      expect(FreePlan.canVisit(now.subtract(const Duration(days: 7)), now, isPlus: false), isTrue);
      expect(FreePlan.canVisit(now.add(const Duration(days: 8)), now, isPlus: false), isFalse);
      expect(FreePlan.canVisit(DateTime.utc(1912, 4, 15), now, isPlus: false), isFalse);
      expect(FreePlan.canVisit(DateTime.utc(1912, 4, 15), now, isPlus: true), isTrue);
    });

    test('the pyramids, Galileo and Apollo 11 are free; the rest are LookUp+', () {
      for (final id in ['giza', 'galileo', 'apollo11']) {
        expect(FreePlan.canVisitFamous(id, isPlus: false), isTrue, reason: id);
      }
      for (final id in ['conjunction-7bc', 'conjunction-2bc', 'columbus', 'titanic']) {
        expect(FreePlan.canVisitFamous(id, isPlus: false), isFalse, reason: id);
        expect(FreePlan.canVisitFamous(id, isPlus: true), isTrue, reason: id);
      }
    });
  });

  test('the photo caption stays on free; the new settings survive a restart', () {
    expect(FreePlan.canUse(PlusFeature.noCaption, isPlus: false), isFalse);
    expect(FreePlan.canUse(PlusFeature.noCaption, isPlus: true), isTrue);
    expect(FreePlan.caption(isPlus: false, wanted: false), isTrue, reason: 'free always says where it came from');
    expect(FreePlan.caption(isPlus: true, wanted: false), isFalse);
    expect(FreePlan.caption(isPlus: true, wanted: true), isTrue);
    final s = const LookUpSettings().copyWith(
        plusDeclines: 1, trialOfferShown: true, missedItId: 'm', missedItAt: now, photoCaption: false);
    final b = LookUpSettings.fromJson(s.toJson());
    expect((b.plusDeclines, b.trialOfferShown, b.missedItId, b.missedItAt, b.photoCaption), (1, true, 'm', now, false));
    expect(LookUpSettings.fromJson(const LookUpSettings().toJson()).photoCaption, isTrue);
  });
}
