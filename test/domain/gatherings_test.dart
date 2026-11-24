import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/gatherings.dart';
import 'package:lookup/domain/events/pairings.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';

/// Memorable moments: Mars, Jupiter and Regulus gather in Leo in the
/// mornings of late November 2026 (Mars–Jupiter 1.2° on the 16th, Mars–
/// Regulus 1.7° on the 26th; all three inside 4° from about the 18th to the
/// 26th), and the Moon joins Mars and Regulus around the 30th.
void main() {
  // Denver, the morning of 24 Nov 2026 (MST).
  const lat = 39.74, lon = -104.99;
  const mst = -7 * 60;
  final now = DateTime.utc(2026, 11, 24, 0);
  const plus = LookUpSettings(isPlus: true, quietHours: QuietHours(startMinute: 0, endMinute: 0));
  final numbers = RegExp(r'\d\s*°|azimuth|elevation', caseSensitive: false);

  List<SkyEvent> found([DateTime? at]) => gatheringEvents(now: at ?? now, latDeg: lat, lonDeg: lon, days: 14);
  SkyEvent trio([DateTime? at]) => found(at).firstWhere((e) => e.id.startsWith('gather:Mars+Jupiter+Regulus:'));

  test('finds Mars, Jupiter and Regulus together in the morning', () {
    final e = trio();
    expect(e.type, SkyEventType.gathering);
    expect(e.plusOnly, isTrue);
    expect(e.details['bodies'], ['Mars', 'Jupiter', 'Regulus']);
    expect(e.details['label'], 'Mars, Jupiter and Regulus');
    expect(e.details['when'], 'morning');
    expect((e.details['separation'] as num), lessThanOrEqualTo(gatheringFitDeg));
    expect(e.peakElevationDeg, greaterThanOrEqualTo(gatheringMinAltDeg));
    expect(e.start.isAfter(now), isTrue);
    // Several nights, so one cloudy morning isn't the only chance.
    expect(e.details['nightsLeft'] as int, greaterThanOrEqualTo(2));
    // Before dawn in Denver: between 1 AM and 7 AM MST.
    final local = e.start.add(const Duration(minutes: mst));
    expect(local.hour, inInclusiveRange(1, 6));
    expect(local.day, inInclusiveRange(24, 27));
  });

  test('the Moon joining makes its own moment, not the trio again', () {
    final withMoon = found(DateTime.utc(2026, 11, 27)).where((e) => (e.details['bodies'] as List).contains('Moon')).toList();
    expect(withMoon, hasLength(1), reason: 'one tap for one patch of sky');
    for (final e in withMoon) {
      expect((e.details['bodies'] as List).length, greaterThanOrEqualTo(3));
      final local = e.start.add(const Duration(minutes: mst));
      expect(DateTime(local.year, local.month, local.day), anyOf(DateTime(2026, 11, 29), DateTime(2026, 11, 30), DateTime(2026, 12, 1)));
    }
  });

  test('keeps its id as the nights go by, so nothing is sent twice', () {
    expect(trio(DateTime.utc(2026, 11, 22, 18)).id, trio().id);
    expect(trio(DateTime.utc(2026, 11, 24, 18)).id, trio().id);
  });

  test('LookUp+ gets a heads-up in words, never numbers', () {
    final e = trio();
    final plan = const AlertPlanner().plan(events: [e], settings: plus, now: now, utcOffsetMinutes: mst);
    expect(plan, isNotEmpty);
    expect(plan.first.title, startsWith('Mars, Jupiter and Regulus together'));
    for (final a in plan) {
      expect(a.body, isNot(matches(numbers)));
    }
    expect(plan.first.body, contains('nights'));
  });

  test('free: listed, but no tap', () {
    expect(const AlertPlanner().plan(events: [trio()], settings: const LookUpSettings(), now: now, utcOffsetMinutes: mst), isEmpty);
    expect(AlertPlanner.plusOnlyAhead([trio()], now), isNotEmpty);
  });

  test('never through cloud, never with planet sights switched off', () {
    final e = trio();
    expect(const AlertPlanner().plan(events: [e.copyWith(cloudCoverPercent: 95)], settings: plus, now: now, utcOffsetMinutes: mst), isEmpty);
    expect(const AlertPlanner().plan(events: [e], settings: plus.copyWith(pairingsEnabled: false), now: now, utcOffsetMinutes: mst), isEmpty);
  });

  test('LookUp+ is not tapped for a pair inside the gathering as well', () {
    final g = found();
    final pairs = pairingEvents(now: now, latDeg: lat, lonDeg: lon, days: 14);
    final kept = withoutGathered(pairs, g, isPlus: true).toList();
    for (final p in kept) {
      final b = p.details['bodies'] as List;
      final overlapsTrio = b.every(['Mars', 'Jupiter', 'Regulus'].contains);
      expect(overlapsTrio, isFalse, reason: '${p.id} is part of the trio');
    }
    expect(withoutGathered(pairs, g, isPlus: false).length, pairs.length, reason: 'free keeps its pairing tap');
  });

  test('stars alone never gather, and nothing far apart does', () {
    // Mid-December: Mars has moved on (9° from Jupiter).
    final later = found(DateTime.utc(2026, 12, 14));
    expect(later.where((e) => e.id.contains('Mars+Jupiter+Regulus')), isEmpty);
    for (final e in [...found(), ...later]) {
      final movers = (e.details['bodies'] as List).where((b) => !gatheringStars.any((s) => s.$1 == b));
      expect(movers.length, greaterThanOrEqualTo(2));
    }
  });

  test('Home calls it out as "Don\'t miss" for LookUp+ only, within the week', () {
    final events = found();
    expect(dontMiss(events, now, isPlus: true)?.id, trio().id);
    expect(dontMiss(events, now, isPlus: false), isNull);
    expect(dontMiss(events, now.subtract(const Duration(days: 30)), isPlus: true), isNull);
  });
}
