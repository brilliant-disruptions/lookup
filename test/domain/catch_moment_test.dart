import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/catch_moment.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/sky_event.dart';

SkyEvent ev(String id, SkyEventType type, DateTime start) => SkyEvent(
  id: id,
  type: type,
  start: start,
  peak: start.add(const Duration(minutes: 2)),
  end: start.add(const Duration(minutes: 4)),
  peakElevationDeg: 50,
  riseAzimuthDeg: 247,
  peakAzimuthDeg: 180,
  setAzimuthDeg: 100,
);

void main() {
  final now = DateTime.utc(2026, 10, 21, 20);
  // Answers given in the early evening (UTC), well clear of the night-owl hours.
  Sighting s(String id, int day, {bool seen = true, SkyEventType? type, double? el}) =>
      Sighting(eventId: id, seen: seen, at: DateTime.utc(2026, 10, day, 20), type: type, peakElevationDeg: el);

  test('the first ever yes is "Your first sighting" and earns First light', () {
    final log = SkyLog.from([s('iss:a', 20)]);
    final m = CatchMoment.of(log: log, eventId: 'iss:a', upcoming: const [], now: now, isPlus: false)!;
    expect(m.isFirst, isTrue);
    expect(m.countLine, 'Your first sighting');
    expect(m.nthOfType, 1);
    expect([for (final b in m.newBadges) b.id], ['first-light']);
  });

  test('counts this sighting among all and among its kind, ignoring the nos', () {
    final log = SkyLog.from([
      s('iss:a', 10),
      s('starlink-x:1', 11, type: SkyEventType.starlinkTrain),
      s('iss:b', 12, seen: false),
      s('iss:c', 13),
      s('iss:d', 14),
    ]);
    final m = CatchMoment.of(log: log, eventId: 'iss:c', upcoming: const [], now: now, isPlus: false)!;
    expect(m.nth, 3);
    expect(m.countLine, 'Your 3rd sighting');
    expect(m.nthOfType, 2);
    expect(m.newBadges, isEmpty);
  });

  test('only the badges this very sighting earned', () {
    final log = SkyLog.from([
      for (var d = 1; d <= 4; d++) s('iss:$d', d),
      s('iss:5', 5, el: 80), // 5th ISS, and straight overhead
    ]);
    final m = CatchMoment.of(log: log, eventId: 'iss:5', upcoming: const [], now: now, isPlus: false)!;
    expect([for (final b in m.newBadges) b.id], unorderedEquals(['station-spotter', 'overhead']));
  });

  test('null for an event they said no to', () {
    final log = SkyLog.from([s('iss:a', 20, seen: false)]);
    expect(CatchMoment.of(log: log, eventId: 'iss:a', upcoming: const [], now: now, isPlus: false), isNull);
  });

  group('what comes next', () {
    final log = SkyLog.from([s('iss:a', 20)]);
    final tiangong = ev('tiangong:1', SkyEventType.tiangong, now.add(const Duration(days: 1)));
    final iss = ev('iss:next', SkyEventType.iss, now.add(const Duration(days: 2)));
    final transit = ev('transit-moon:1', SkyEventType.issTransit, now.add(const Duration(hours: 3)));
    final outlook = ev('aurora-outlook:1', SkyEventType.auroraOutlook, now.add(const Duration(hours: 2)));
    final past = ev('iss:past', SkyEventType.iss, now.subtract(const Duration(hours: 1)));
    final same = ev('iss:a', SkyEventType.iss, now.add(const Duration(minutes: 1)));
    final upcoming = [past, same, outlook, transit, iss, tiangong];

    test('free: next is the next free pushed sight; Plus-only is offered separately', () {
      final m = CatchMoment.of(log: log, eventId: 'iss:a', upcoming: upcoming, now: now, isPlus: false)!;
      expect(m.next?.id, 'iss:next');
      expect(m.nextPlus?.id, 'tiangong:1');
    });

    test('Plus: next is whatever is soonest, and nothing is sold', () {
      final m = CatchMoment.of(log: log, eventId: 'iss:a', upcoming: upcoming, now: now, isPlus: true)!;
      expect(m.next?.id, 'tiangong:1');
      expect(m.nextPlus, isNull);
    });

    test('never points at something LookUp would not push (transits, outlooks)', () {
      final m = CatchMoment.of(log: log, eventId: 'iss:a', upcoming: [outlook, transit], now: now, isPlus: false)!;
      expect(m.next, isNull);
      expect(m.nextPlus, isNull);
    });

    test('a Plus-only sight more than a fortnight out is not sold', () {
      final far = ev('tiangong:far', SkyEventType.tiangong, now.add(const Duration(days: 20)));
      final m = CatchMoment.of(log: log, eventId: 'iss:a', upcoming: [far], now: now, isPlus: false)!;
      expect(m.nextPlus, isNull);
    });
  });

  test('ordinals', () {
    expect(
      [
        for (final n in [1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111, 112]) ordinal(n),
      ],
      ['1st', '2nd', '3rd', '4th', '11th', '12th', '13th', '21st', '22nd', '23rd', '101st', '111th', '112th'],
    );
  });
}
