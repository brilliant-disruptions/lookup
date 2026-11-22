import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/week_view.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';

void main() {
  // Local times throughout, so this holds in any time zone.
  final now = DateTime(2026, 10, 30, 16); // Friday afternoon

  SkyEvent ev(String id, SkyEventType type, DateTime localStart) => SkyEvent(
        id: id,
        type: type,
        start: localStart.toUtc(),
        peak: localStart.add(const Duration(minutes: 2)).toUtc(),
        end: localStart.add(const Duration(minutes: 5)).toUtc(),
        peakElevationDeg: 50,
        riseAzimuthDeg: 250,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 90,
      );

  test('a day is its own midnight-to-midnight: a dawn pass is on its own morning', () {
    expect(dayOf(DateTime(2026, 10, 30, 18, 41)), DateTime(2026, 10, 30));
    expect(dayOf(DateTime(2026, 11, 4, 5, 40)), DateTime(2026, 11, 4));
    expect(dayOf(DateTime(2026, 11, 4, 0, 5)), DateTime(2026, 11, 4));
    expect(dayOf(DateTime(2026, 11, 3, 23, 59)), DateTime(2026, 11, 3));
  });

  test('seven nights from tonight, each with its own sights in order', () {
    final events = [
      ev('iss:b', SkyEventType.iss, DateTime(2026, 10, 30, 19, 12)),
      ev('iss:a', SkyEventType.iss, DateTime(2026, 10, 30, 18, 41)),
      ev('transit:a', SkyEventType.issTransit, DateTime(2026, 10, 30, 21, 3)),
      ev('tiangong:dawn', SkyEventType.tiangong, DateTime(2026, 11, 4, 5, 40)),
      ev('gone', SkyEventType.iss, DateTime(2026, 10, 30, 6)), // this morning, over
      ev('far', SkyEventType.iss, DateTime(2026, 11, 12, 19)), // past the week
    ];
    final nights = weekNights(events, now);
    expect(nights, hasLength(7));
    expect(nights.first.date, DateTime(2026, 10, 30));
    expect(nights.last.date, DateTime(2026, 11, 5));
    expect(nights.first.events.map((e) => e.id), ['iss:a', 'iss:b', 'transit:a']);
    expect(nights.first.alerts.map((e) => e.id), ['iss:a', 'iss:b']);
    expect(nights.first.quiet.map((e) => e.id), ['transit:a']);
    expect(nights[5].events.map((e) => e.id), ['tiangong:dawn']); // Wednesday morning, its own line
    expect(nights[4].events, isEmpty, reason: 'not on Tuesday');
    expect(nights.expand((n) => n.events).map((e) => e.id), isNot(contains('gone')));
    expect(nights.expand((n) => n.events).map((e) => e.id), isNot(contains('far')));
  });

  test('cloudy only when the forecast says so, never for lack of one', () {
    CloudForecast forecast(int cover) => CloudForecast(
          latitude: 36.17,
          longitude: -86.78,
          fetchedAt: now.toUtc(),
          hourly: [
            for (var h = 0; h < 48; h++)
              CloudSample(time: DateTime(2026, 10, 30, 12 + h).toUtc(), coverPercent: cover),
          ],
        );
    final cloudy = weekNights(const [], now, weather: forecast(90));
    expect(cloudy.first.cloudy, isTrue);
    expect(cloudy.first.clouds, hasLength(24));
    expect(cloudy.first.clouds[0], isNull, reason: 'before the forecast begins');
    expect(cloudy.first.clouds[14], 90);
    expect(cloudy[3].hasForecast, isFalse); // past the 48 h of forecast
    expect(cloudy[3].cloudy, isFalse);
    expect(weekNights(const [], now, weather: forecast(10)).first.cloudy, isFalse);
    expect(weekNights(const [], now).first.cloudy, isFalse);
  });

  test('at a glance scrolls from last week, through tonight, to two weeks ahead', () {
    final nights = glanceNights(
      [ev('iss:a', SkyEventType.iss, DateTime(2026, 10, 30, 18, 41))],
      [
        ev('iss:old', SkyEventType.iss, DateTime(2026, 10, 27, 19, 5)),
        // A dawn pass on the 29th is on the 29th's line.
        ev('iss:dawn', SkyEventType.iss, DateTime(2026, 10, 29, 5, 40)),
        ev('iss:too-old', SkyEventType.iss, DateTime(2026, 10, 20, 19)),
      ],
      now,
    );
    expect(nights, hasLength(7 + 7), reason: 'a week ahead when nothing is known further out');
    expect(nights.first.date, DateTime(2026, 10, 23));
    expect(nights.where((n) => n.past), hasLength(7));
    expect(nights.firstWhere((n) => !n.past).date, DateTime(2026, 10, 30), reason: 'tonight comes right after');
    expect(nights.singleWhere((n) => n.date == DateTime(2026, 10, 27)).events.single.id, 'iss:old');
    expect(nights.singleWhere((n) => n.date == DateTime(2026, 10, 29)).events.single.id, 'iss:dawn');
    expect(nights.expand((n) => n.events).map((e) => e.id), isNot(contains('iss:too-old')));
    expect(nights.where((n) => n.past).every((n) => !n.hasForecast), isTrue);
    expect(nights.last.date, DateTime(2026, 11, 5));
    // Something further out (a meteor peak) takes the list to it, up to two weeks.
    final longer = glanceNights([ev('meteors', SkyEventType.meteorShower, DateTime(2026, 11, 9, 2))], const [], now);
    expect(longer.last.date, DateTime(2026, 11, 9));
    final far = glanceNights([ev('eclipse', SkyEventType.lunarEclipse, DateTime(2027, 2, 1, 22))], const [], now);
    expect(far.where((n) => !n.past), hasLength(14));
  });
}
