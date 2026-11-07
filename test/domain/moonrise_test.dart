import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/moonrise.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/sky/direction.dart';

/// The full-Moon moonrise alert: when it fires (pinned to USNO), and that it
/// obeys every rule a false alarm could slip through: cloud, quiet hours,
/// the nightly cap and its own switch.
void main() {
  const lat = 41.88, lon = -87.63; // Chicago
  const cst = -6 * 60;
  const planner = AlertPlanner();
  final now = DateTime.utc(2026, 11, 20, 18);
  final events = fullMoonRiseEvents(now: now, latDeg: lat, lonDeg: lon, days: 40);
  final nov = events.firstWhere((e) => e.id == 'fullmoon:2026-11-24');
  final dec = events.firstWhere((e) => e.id == 'fullmoon:2026-12-24');

  group('the event', () {
    test('one per full Moon in the window, at the USNO moonrise', () {
      expect(events.map((e) => e.id), ['fullmoon:2026-11-24', 'fullmoon:2026-12-24']);
      // USNO, Chicago: 22:08Z on 24 Nov (full at 14:53Z). December's full
      // Moon is 01:28Z on the 24th, 7:28 PM on the 23rd locally, so it's the
      // 23rd's rise (21:50Z), not the 24th's (23:08Z, a day past full).
      expect(nov.start.difference(DateTime.utc(2026, 11, 24, 22, 8)).inSeconds.abs(), lessThan(90));
      expect(dec.start.difference(DateTime.utc(2026, 12, 23, 21, 50)).inSeconds.abs(), lessThan(90));
    });

    test('rises north of east in winter, and is low for its first half hour', () {
      expect(nov.riseAzimuthDeg, inInclusiveRange(45, 90));
      // Low, so it never outranks a good pass under the nightly cap.
      expect(nov.peakElevationDeg, inInclusiveRange(0, 10));
    });

    test('only the close one is a supermoon', () {
      expect(nov.details['supermoon'], false);
      expect(nov.details['label'], 'Full Moon');
      expect(dec.details['supermoon'], true);
      expect(dec.details['label'], 'Supermoon');
    });

    test('free, pushed, and not on the paywall', () {
      expect(SkyEventType.fullMoonRise.plusOnly, isFalse);
      expect(SkyEventType.fullMoonRise.pushes, isTrue);
      expect(AlertPlanner.plusOnlyAhead(events, now, within: const Duration(days: 40)), isEmpty);
    });

    test('none when the window holds no moonrise near full', () {
      expect(fullMoonRiseEvents(now: DateTime.utc(2026, 11, 26), latDeg: lat, lonDeg: lon, days: 14), isEmpty);
    });
  });

  group('the alert', () {
    const free = LookUpSettings();

    test('a free user gets it, saying "rising" with a direction in words', () {
      final plan = planner.plan(
          events: [nov.copyWith(cloudCoverPercent: 10)], settings: free, now: now,
          horizon: const Duration(days: 7), utcOffsetMinutes: cst);
      expect(plan.map((a) => a.kind), [AlertKind.headsUp, AlertKind.goNow]);
      expect(plan[0].title, 'Full Moon rising in 10 min');
      expect(plan[0].body,
          'Coming up in the ${compassWord(nov.riseAzimuthDeg)}, on the horizon. You\'ll need a clear view that way. Clear skies.');
      expect(plan[1].body, 'Look ${compassWord(nov.riseAzimuthDeg)}, right on the horizon.');
      // No azimuth or elevation numbers on the main path.
      for (final a in plan) {
        expect(a.body, isNot(matches(RegExp(r'\d'))));
      }
    });

    test('a supermoon says so', () {
      final plan = planner.plan(
          events: [dec], settings: free, now: now, horizon: const Duration(days: 40), utcOffsetMinutes: cst);
      expect(plan[0].title, 'Supermoon rising in 10 min');
      expect(plan[0].body, contains('A supermoon'));
    });

    test('cloud over the cutoff blocks it; with the gate off the copy hedges', () {
      final cloudy = nov.copyWith(cloudCoverPercent: 85);
      expect(
          planner.plan(events: [cloudy], settings: free, now: now, horizon: const Duration(days: 7), utcOffsetMinutes: cst),
          isEmpty);
      final plan = planner.plan(
          events: [cloudy], settings: free.copyWith(clearSkyOnly: false), now: now,
          horizon: const Duration(days: 7), utcOffsetMinutes: cst);
      expect(plan[0].body, endsWith('Cloudy (85%) — might not see it.'));
    });

    test('quiet hours block it, and wake-me does not override them', () {
      // It rises at 4:08 PM local; quiet hours set to cover that.
      final s = free.copyWith(
          quietHours: const QuietHours(startMinute: 15 * 60, endMinute: 17 * 60), auroraWakeMe: true);
      expect(
          planner.plan(events: [nov], settings: s, now: now, horizon: const Duration(days: 7), utcOffsetMinutes: cst),
          isEmpty);
    });

    test('it counts under the nightly cap and loses to a better pass', () {
      final iss = SkyEvent(
        id: 'iss:x',
        type: SkyEventType.iss,
        start: nov.start.add(const Duration(hours: 1)),
        peak: nov.start.add(const Duration(hours: 1, minutes: 3)),
        end: nov.start.add(const Duration(hours: 1, minutes: 6)),
        peakElevationDeg: 60,
        riseAzimuthDeg: 247,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 100,
      );
      List<String> ids(int cap) => planner
          .plan(
              events: [nov, iss], settings: free.copyWith(maxAlertsPerNight: cap, goNowNudge: false), now: now,
              horizon: const Duration(days: 7), utcOffsetMinutes: cst)
          .map((a) => a.event.id)
          .toList();
      expect(ids(1), ['iss:x']);
      expect(ids(2), ['fullmoon:2026-11-24', 'iss:x']);
    });

    test('its own switch turns it off', () {
      expect(
          planner.plan(
              events: [nov], settings: free.copyWith(moonriseEnabled: false), now: now,
              horizon: const Duration(days: 7), utcOffsetMinutes: cst),
          isEmpty);
    });

    test('the switch survives JSON', () {
      final s = LookUpSettings.fromJson(const LookUpSettings(moonriseEnabled: false).toJson());
      expect(s.moonriseEnabled, isFalse);
      expect(LookUpSettings.fromJson(const {}).moonriseEnabled, isTrue);
    });
  });
}
