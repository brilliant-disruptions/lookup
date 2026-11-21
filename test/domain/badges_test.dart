import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/catch_moment.dart';
import 'package:lookup/domain/log/next_chance.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/sky_event.dart';

final _t0 = DateTime.utc(2026, 11, 1, 23);

Sighting caught(String id, int day, {SkyEventType? type, double? el, double? mag, int hour = 23}) {
  final at = DateTime.utc(2026, 11, day, hour);
  return Sighting(eventId: id, seen: true, at: at, eventTime: at, type: type, peakElevationDeg: el, magnitude: mag);
}

SkyEvent ev(String id, SkyEventType type, DateTime at, {double el = 40, Map<String, Object?> details = const {}}) => SkyEvent(
      id: id,
      type: type,
      start: at,
      peak: at,
      end: at.add(const Duration(minutes: 5)),
      peakElevationDeg: el,
      riseAzimuthDeg: 200,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 100,
      details: details,
    );

Badge badge(SkyLog l, String id) => l.badges.firstWhere((b) => b.id == id);

void main() {
  test('Station spotter goes bronze, silver, gold at 1, 5 and 25 passes; the catch moment names the level', () {
    final all = [
      for (var i = 0; i < 25; i++)
        Sighting(eventId: 'iss:$i', seen: true, at: _t0.add(Duration(days: i)), type: SkyEventType.iss),
    ];
    var log = SkyLog.from(all.take(1).toList());
    expect(badge(log, 'station-spotter').tier, BadgeTier.bronze);
    expect(badge(log, 'station-spotter').progress, (got: 1, of: 5));
    log = SkyLog.from(all.take(5).toList());
    expect(badge(log, 'station-spotter').fullTitle, 'Station spotter · Silver');
    final m = CatchMoment.of(log: log, eventId: 'iss:4', upcoming: const [], now: _t0, isPlus: false)!;
    expect(m.newBadges.map((b) => b.fullTitle), contains('Station spotter · Silver'), reason: 'a new level is announced');
    final quiet = CatchMoment.of(log: SkyLog.from(all.take(3).toList()), eventId: 'iss:2', upcoming: const [], now: _t0, isPlus: false)!;
    expect(quiet.newBadges.map((b) => b.id), isNot(contains('station-spotter')), reason: 'the 3rd pass moves the bar, no new step');
    log = SkyLog.from(all);
    expect(badge(log, 'station-spotter').tier, BadgeTier.gold);
    expect(badge(log, 'station-spotter').progress, isNull, reason: 'nothing left after gold');
    expect(badge(log, 'regular').tier, BadgeTier.silver, reason: '25 catches');
  });

  test('the planet set fills from sky-camera catches and planet alerts, one slot per planet', () {
    final log = SkyLog.from([
      caught('obj:planet:jupiter', 2, type: SkyEventType.skyObject),
      caught('planet-venus-greatest-elongation:20261103', 3, type: SkyEventType.planetHighlight),
      caught('obj:planet:saturn', 4, type: SkyEventType.skyObject),
      caught('obj:planet:jupiter', 5, type: SkyEventType.skyObject),
    ]);
    final p = badge(log, 'planet-set');
    expect([for (final s in p.slots!) if (s.got) s.label], ['Venus', 'Jupiter', 'Saturn']);
    expect(p.progress, (got: 3, of: 5));
    expect(p.earned, isFalse);
    final all = SkyLog.from([for (final (i, n) in ['mercury', 'venus', 'mars', 'jupiter', 'saturn'].indexed) caught('obj:planet:$n', 2 + i)]);
    expect(badge(all, 'planet-set').earned, isTrue);
  });

  test('every Moon: each night\'s Moon is its own catch, sorted by how it looked', () {
    // One Moon catch for each look seen through the month (the phases are worked out, not guessed).
    final byLook = <String, Sighting>{};
    for (var d = 1; d <= 30; d++) {
      final s = caught('obj:moon:202611${d.toString().padLeft(2, '0')}', d, type: SkyEventType.skyObject, hour: 6);
      final look = moonLookOf(s);
      if (look != null && look != 'Full') byLook.putIfAbsent(look, () => s);
    }
    expect(byLook.keys.toSet(), {'Crescent', 'Half', 'Gibbous'});
    final log = SkyLog.from(byLook.values.toList());
    expect({for (final s in badge(log, 'moon-phases').slots!) if (s.got) s.label}, {'Crescent', 'Half', 'Gibbous'});
    expect(badge(log, 'moon-phases').earned, isFalse);
    final full = SkyLog.from([...log.seen, caught('fullmoon:202611', 24, type: SkyEventType.fullMoonRise)]);
    expect(badge(full, 'moon-phases').earned, isTrue, reason: 'a full Moon rising fills the last slot');
  });

  test('a meteor-shower catch earns that year\'s seasonal patch; coming ones show with their best night', () {
    final log = SkyLog.from([caught('meteor-LEO:2026', 17, type: SkyEventType.meteorShower)]);
    final leo = badge(log, 'season-LEO-2026');
    expect((leo.title, leo.earned), ('Leonids 2026', true));
    expect(badge(log, 'meteor-watcher').earned, isTrue);
    final gem = DateTime.utc(2026, 12, 14, 2);
    final coming = log.comingSeason([
      ev('meteor-GEM:2026', SkyEventType.meteorShower, gem),
      ev('meteor-LEO:2026', SkyEventType.meteorShower, DateTime.utc(2026, 11, 22)), // already earned
      ev('meteor-LYR:2027', SkyEventType.meteorShower, DateTime.utc(2027, 4, 22)), // too far
    ], DateTime.utc(2026, 11, 21));
    expect([for (final b in coming) (b.title, b.season)], [('Geminids 2026', gem)]);
  });

  test('secrets stay riddles until earned: up past three, and two things one night', () {
    final none = SkyLog.from(const []);
    final s = badge(none, 'up-past-three');
    expect((s.hidden, s.riddle), (true, 'Pip knows one you only get by staying up very late.'));
    expect(nextChance(s, [ev('iss:x', SkyEventType.iss, _t0.add(const Duration(hours: 1)))], _t0), isNull,
        reason: 'no hints for a secret');
    // Two different things the same night (the second just after midnight local).
    final a = DateTime.utc(2026, 11, 3, 1), b = a.add(const Duration(hours: 2));
    final log = SkyLog.from([
      Sighting(eventId: 'iss:a', seen: true, at: a, eventTime: a, type: SkyEventType.iss),
      Sighting(eventId: 'obj:planet:jupiter', seen: true, at: b, eventTime: b, type: SkyEventType.skyObject),
    ]);
    expect(badge(log, 'double-night').earned, isTrue);
    expect(badge(log, 'double-night').earnedAt, b);
  });

  test('"missed it" answers never earn anything', () {
    final at = DateTime.utc(2026, 11, 3, 2);
    final log = SkyLog.from([Sighting(eventId: 'starlink:1', seen: false, at: at, type: SkyEventType.starlinkTrain, reason: 'clouds')]);
    expect(log.earnedCount, 0);
  });

  test('next chance: the soonest real event that would earn it or its next level', () {
    final now = DateTime.utc(2026, 11, 21, 18);
    final up = [
      ev('iss:soon', SkyEventType.iss, now.add(const Duration(hours: 2)), el: 35),
      ev('iss:high', SkyEventType.iss, now.add(const Duration(days: 3)), el: 82),
      ev('starlink:t', SkyEventType.starlinkTrain, now.add(const Duration(days: 1))),
      ev('planet-mars-opposition:20261125', SkyEventType.planetHighlight, now.add(const Duration(days: 4))),
      ev('aurora-outlook:x', SkyEventType.auroraOutlook, now.add(const Duration(hours: 5))), // never pushed
      ev('iss:gone', SkyEventType.iss, now.subtract(const Duration(hours: 1))),
    ];
    final log = SkyLog.from([caught('obj:planet:jupiter', 2), caught('iss:old', 3, type: SkyEventType.iss)]);
    expect(nextChance(badge(log, 'station-spotter'), up, now)?.id, 'iss:soon', reason: 'towards silver');
    expect(nextChance(badge(log, 'overhead'), up, now)?.id, 'iss:high', reason: 'nearly straight up only');
    expect(nextChance(badge(log, 'train-spotter'), up, now)?.id, 'starlink:t');
    expect(nextChance(badge(log, 'planet-set'), up, now)?.id, 'planet-mars-opposition:20261125', reason: 'a planet not yet in the set');
    expect(nextChance(badge(log, 'aurora-chaser'), up, now), isNull, reason: 'an outlook is not a chance');
    expect(nextChance(badge(log, 'first-light'), up, now), isNull, reason: 'already earned, nothing left');
  });

  test('no badge says degrees', () {
    for (final b in SkyLog.from(const []).badges) {
      expect(b.description, isNot(contains('°')), reason: b.id);
      expect(b.riddle ?? '', isNot(contains('°')), reason: b.id);
    }
  });
}
