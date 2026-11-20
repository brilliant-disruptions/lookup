import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/catch_moment.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/sky_event.dart';

void main() {
  final setUp = DateTime.utc(2026, 10, 20, 19);

  test('the first badge is earned by setting up, before anything is caught', () {
    final log = SkyLog.from(const [], onboardedAt: setUp);
    final first = log.badges.first;
    expect(first.id, 'looked-up');
    expect(first.earnedAt, setUp);
    expect(log.earnedCount, 1);
    expect(log.total, 0, reason: 'a badge, not a sighting');
  });

  test('not set up yet: nothing earned', () {
    expect(SkyLog.from(const []).earnedCount, 0);
  });

  test('a first catch earns First light, and never re-announces Looked up', () {
    final at = DateTime.utc(2026, 10, 21, 0, 40);
    final log = SkyLog.from([Sighting(eventId: 'iss:1', seen: true, at: at, type: SkyEventType.iss)], onboardedAt: at);
    final m = CatchMoment.of(eventId: 'iss:1', log: log, upcoming: const [], now: at, isPlus: false);
    final ids = m!.newBadges.map((b) => b.id);
    expect(ids, contains('first-light'));
    expect(ids, isNot(contains('looked-up')));
  });
}
