import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';
import 'package:lookup/domain/weather/met_steps.dart';

final _t0 = DateTime.utc(2026, 11, 27, 20);
DateTime _h(int h) => _t0.add(Duration(hours: h));

void main() {
  test('hourly steps become hourly samples, nearest-hour lookup unchanged', () {
    final f = forecastFromRelay({
      'fetched': '2026-11-27T19:50:00Z',
      'steps': [
        {'t': '2026-11-27T20:00:00Z', 'hours': 1, 'cloud': 10},
        {'t': '2026-11-27T21:00:00Z', 'hours': 1, 'cloud': 55},
        {'t': '2026-11-27T22:00:00Z', 'hours': 1, 'cloud': 90},
        {'cloud': 5}, // not a step
      ],
    }, latitude: 1, longitude: 2, now: _h(1));
    expect(f.coverAt(_t0), 10);
    expect(f.coverAt(_t0.add(const Duration(minutes: 50))), 55);
    expect(f.coverAt(_h(2)), 90);
    // Three hours past the last step still has clouds; later doesn't.
    expect(f.coverAt(_h(5)), 90);
    expect(f.coverAt(_h(8)), isNull);
    final rt = CloudForecast.fromJson(f.toJson());
    expect(rt.hourly.map((s) => s.coverPercent), f.hourly.map((s) => s.coverPercent));
  });

  // Days 3–7 come six-hourly. Without filling the hours between, a night
  // four days out would have no clouds, and unknown cloud passes the gate.
  test('six-hourly days have a cloud figure for every hour', () {
    final steps = [
      MetStep(time: _h(0), hours: 6, cloud: 20, precipMm: 3, precipProb: 30),
      MetStep(time: _h(6), hours: 6, cloud: 80, precipMm: 0, precipProb: 10),
    ];
    final s = hourlyFromSteps(steps);
    expect(s.map((x) => x.time), [for (var h = 0; h <= 9; h++) _h(h)]);
    // Nearest step; at a tie (3 hours each way) the later one.
    expect(s.map((x) => x.coverPercent), [20, 20, 20, 80, 80, 80, 80, 80, 80, 80]);
    // 3 mm over six hours is half a millimetre each hour: wet.
    expect(s[0].precipMm, 0.5);
    expect(s[0].wet, isTrue);
    expect(s[5].precipProbability, 30);
    expect(s[6].precipMm, 0);
    expect(s[6].wet, isFalse);
  });

  test('a gap over 3 hours either way stays unknown, never clear', () {
    final s = hourlyFromSteps([
      MetStep(time: _h(0), hours: 1, cloud: 0),
      MetStep(time: _h(12), hours: 1, cloud: 0),
    ]);
    final f = CloudForecast(latitude: 0, longitude: 0, fetchedAt: _t0, hourly: s);
    expect(f.coverAt(_h(3)), 0);
    expect(f.coverAt(_h(6)), isNull);
    expect(f.coverAt(_h(9)), 0);
  });

  test('a step with no cloud figure gives no sample of its own', () {
    final s = hourlyFromSteps([MetStep(time: _h(0), hours: 1, precipProb: 90)]);
    expect(s, isEmpty);
  });

  test('old saved forecasts (four columns) still read, with no fog or rain amount', () {
    final f = CloudForecast.fromJson({
      'latitude': 1,
      'longitude': 2,
      'fetchedAt': '2026-11-27T19:50:00Z',
      'hourly': [
        [_t0.millisecondsSinceEpoch ~/ 1000, 10, 3000, 20],
      ],
    });
    final s = f.hourly.single;
    expect(s.visibilityM, 3000);
    expect(s.fogPercent, isNull);
    expect(s.precipMm, isNull);
    expect(s.foggy, isTrue);
  });
}
