import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/year_review.dart';
import 'package:lookup/domain/models/sky_event.dart';

void main() {
  const cdt = -5 * 60;
  Sighting s(String id, DateTime utc, {bool seen = true, double? mag, double? el, SkyEventType? type}) =>
      Sighting(eventId: id, seen: seen, at: utc, eventTime: utc, magnitude: mag, peakElevationDeg: el, type: type);

  test('summarises one calendar year in local time', () {
    final all = [
      s('iss:1', DateTime.utc(2026, 3, 2, 1), mag: -3.6, el: 80), // Mar 1, 8pm local
      s('iss:2', DateTime.utc(2026, 3, 2, 10), mag: -1.2, el: 40), // Mar 2, 5am: same night out
      s('starlink-x:1', DateTime.utc(2026, 8, 12, 7), type: SkyEventType.starlinkTrain, el: 50), // 2am local
      s('meteor-perseids:1', DateTime.utc(2026, 8, 13, 8), type: SkyEventType.meteorShower),
      s('iss:3', DateTime.utc(2026, 8, 20, 2), seen: false),
      s('iss:5', DateTime.utc(2026, 8, 21, 2)), // Aug 20, 9pm local
      s('iss:4', DateTime.utc(2027, 1, 1, 3)), // Jan 1 2027 UTC but Dec 31 2026 local
      s('iss:old', DateTime.utc(2025, 6, 1, 3)),
    ];
    final r = YearReview.from(all, 2026, utcOffsetMinutes: cdt)!;
    expect(r.seen, 6);
    expect(r.nights, 5);
    expect(r.byType.first, (SkyEventType.iss, 4));
    expect(r.brightest?.eventId, 'iss:1');
    expect(r.highest?.eventId, 'iss:1');
    expect(r.first?.eventId, 'iss:1');
    expect(r.bestMonth, 8);
    expect(r.lateNights, 2);
  });

  test('null for a year with nothing seen', () {
    expect(YearReview.from([s('iss:1', DateTime.utc(2026, 3, 2), seen: false)], 2026, utcOffsetMinutes: 0), isNull);
  });
}
