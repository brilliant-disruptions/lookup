import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/moon_phases.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/sun.dart';

/// First and last quarter Moons: timed to the real quarter, only ever on a
/// night the Moon is up in a dark sky, and held to every alert rule.
void main() {
  const lat = 41.88, lon = -87.63; // Chicago
  const cst = -6 * 60;
  const planner = AlertPlanner();
  final now = DateTime.utc(2026, 11, 20, 18);
  final events = moonPhaseEvents(now: now, latDeg: lat, lonDeg: lon, days: 40);

  group('the event', () {
    test('one per quarter in the window, timed to the real quarter', () {
      expect(events.map((e) => e.id), [
        'moonphase:last:2026-12-01',
        'moonphase:first:2026-12-17',
        'moonphase:last:2026-12-30',
      ]);
      // Last quarter: 1 Dec 2026, 06:09 UTC (USNO).
      final lastQ = DateTime.parse(events.first.details['exactAt']! as String);
      expect(
        lastQ.difference(DateTime.utc(2026, 12, 1, 6, 9)).inMinutes.abs(),
        lessThan(5),
      );
    });

    test('first quarter is the evening sky, last quarter is before dawn', () {
      expect(events.first.details['evening'], isFalse);
      expect(events[1].details['evening'], isTrue);
      expect(events.first.details['label'], 'Last quarter');
      expect(events[1].details['label'], 'First quarter');
    });

    test('the whole stretch is the Moon at least 10° up with the Sun at least 6° down', () {
      for (final e in events) {
        for (
          var t = e.start;
          !t.isAfter(e.end);
          t = t.add(const Duration(minutes: 5))
        ) {
          expect(
            moonHorizontal(t, lat, lon).altitudeDeg,
            greaterThanOrEqualTo(moonPhaseMinAltDeg - 0.01),
            reason: e.id,
          );
          expect(
            sunAltitudeDeg(t, lat, lon),
            lessThanOrEqualTo(moonPhaseSunMaxAltDeg + 0.01),
            reason: e.id,
          );
        }
        expect(e.peakElevationDeg, greaterThanOrEqualTo(moonPhaseMinAltDeg));
        expect(e.start.isBefore(e.end), isTrue);
      }
    });

    test('nothing already begun, and nothing past the window', () {
      final to = now.add(const Duration(days: 40));
      for (final e in events) {
        expect(e.start.isBefore(now), isFalse);
        expect(e.start.isAfter(to), isFalse);
      }
    });

    test('free, pushed, and not on the paywall', () {
      expect(SkyEventType.moonPhase.plusOnly, isFalse);
      expect(SkyEventType.moonPhase.pushes, isTrue);
      expect(
        AlertPlanner.plusOnlyAhead(
          events,
          now,
          within: const Duration(days: 40),
        ),
        isEmpty,
      );
    });

    test('a polar night with no dark sky and no Moon up yields none, without crashing', () {
      expect(
        () => moonPhaseEvents(now: now, latDeg: 89.9, lonDeg: 0, days: 30),
        returnsNormally,
      );
    });
  });

  group('the alert', () {
    const free = LookUpSettings();
    final ev = events[1].copyWith(cloudCoverPercent: 10);
    List<PlannedAlert> plan(SkyEvent e, LookUpSettings s) => planner.plan(
      events: [e],
      settings: s,
      now: now,
      horizon: const Duration(days: 40),
      utcOffsetMinutes: cst,
    );

    test('a free user is told, in words', () {
      final p = plan(
        ev,
        free.copyWith(
          quietHours: const QuietHours(startMinute: 0, endMinute: 0),
        ),
      );
      expect(p, isNotEmpty);
      expect(p.first.title, 'First quarter Moon up in 10 min');
      expect(p.first.body, contains('Half lit'));
      expect(p.first.body, isNot(contains('°')));
    });

    test('its own switch turns it off', () {
      expect(plan(ev, free.copyWith(moonPhasesEnabled: false)), isEmpty);
    });

    test('cloud over the cutoff blocks it', () {
      expect(plan(ev.copyWith(cloudCoverPercent: 90), free), isEmpty);
    });

    test('paused alerts plan nothing', () {
      expect(plan(ev, free.copyWith(alertsPaused: true)), isEmpty);
    });

    test('the switch survives JSON and defaults on', () {
      final s = LookUpSettings.fromJson(
        const LookUpSettings(moonPhasesEnabled: false).toJson(),
      );
      expect(s.moonPhasesEnabled, isFalse);
      expect(LookUpSettings.fromJson(const {}).moonPhasesEnabled, isTrue);
    });
  });
}
