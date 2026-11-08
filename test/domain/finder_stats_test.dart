import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/finder_stats.dart';

void main() {
  // The lock rate says whether Pip works: a session that never locks must
  // pull it down, or the number flatters a finder that loses people.
  test('lock rate counts sessions that never lock', () {
    var s = const FinderStats();
    expect(s.lockRate, isNull);
    s = s.record(const Duration(seconds: 4)).record(null).record(const Duration(seconds: 10)).record(null);
    expect(s.lockRate, 0.5);
    expect(s.medianLockSeconds, 7, reason: 'misses add no time');
  });

  // Recent sessions matter: the median follows the latest finder, not the
  // first week's.
  test('median time to lock covers the latest 50 locks only, and survives a round trip', () {
    var s = const FinderStats();
    for (var i = 0; i < 60; i++) {
      s = s.record(Duration(seconds: i < 10 ? 100 : 5));
    }
    expect(s.lockSeconds, hasLength(FinderStats.keep));
    expect(s.medianLockSeconds, 5);
    expect(s.locks, 60);
    final back = FinderStats.fromJson(s.toJson());
    expect((back.sessions, back.locks, back.medianLockSeconds), (60, 60, 5.0));
  });
}
