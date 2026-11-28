import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';
import 'package:lookup/domain/weather/cloud_history.dart';

final _t0 = DateTime.utc(2026, 11, 27, 0);
DateTime _h(int h) => _t0.add(Duration(hours: h));

CloudForecast _f(DateTime fetched, int from, int to, int cover, {double lat = 36.17}) => CloudForecast(
      latitude: lat,
      longitude: -86.78,
      fetchedAt: fetched,
      hourly: [for (var h = from; h <= to; h++) CloudSample(time: _h(h), coverPercent: cover)],
    );

void main() {
  // MET has no past_days: last night's clouds come from what the phone saw.
  test('the hours before a new forecast come forward from the one it replaces', () {
    final old = _f(_h(18), 18, 60, 10);
    final fresh = _f(_h(24), 24, 80, 90);
    final m = withPast(fresh, old, now: _h(24));
    expect(m.coverAt(_h(20)), 10, reason: 'last night, kept');
    expect(m.coverAt(_h(24)), 90, reason: 'the new forecast wins where it speaks');
    expect(m.coverAt(_h(70)), 90);
    expect(m.fetchedAt, _h(24));
    // And it keeps going: a third fetch still has the first night.
    final third = withPast(_f(_h(30), 30, 90, 50), m, now: _h(30));
    expect(third.coverAt(_h(20)), 10);
    expect(third.coverAt(_h(26)), 90);
  });

  test('a gap stays unknown: an old long-range guess is never kept as what happened', () {
    // Fetched at 18:00, then nothing for two days.
    final old = _f(_h(18), 18, 100, 5);
    final fresh = _f(_h(66), 66, 120, 80);
    final m = withPast(fresh, old, now: _h(66));
    expect(m.coverAt(_h(28)), 5, reason: '10 hours ahead: kept');
    expect(m.coverAt(_h(31)), isNull, reason: 'more than 12 hours ahead of its fetch: unknown');
    expect(m.coverAt(_h(50)), isNull);
  });

  test('another place, or older than a week: dropped', () {
    final old = _f(_h(18), 18, 40, 10);
    expect(withPast(_f(_h(24), 24, 80, 90, lat: 40), old, now: _h(24)).coverAt(_h(20)), isNull);
    final aged = withPast(_f(_h(24 * 9), 24 * 9, 24 * 10, 90), _f(_h(18), 18, 30, 10), now: _h(24 * 9));
    expect(aged.hourly.every((s) => !s.time.isBefore(_h(24 * 2))), isTrue);
  });

  test('a first fetch is just the forecast', () {
    final fresh = _f(_h(24), 24, 30, 40);
    expect(identical(withPast(fresh, null, now: _h(24)), fresh), isTrue);
  });
}
