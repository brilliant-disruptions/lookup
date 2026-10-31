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

  test('a night runs noon to noon: a dawn pass belongs to the night before', () {
    expect(nightOf(DateTime(2026, 10, 30, 18, 41)), DateTime(2026, 10, 30));
    expect(nightOf(DateTime(2026, 11, 4, 5, 40)), DateTime(2026, 11, 3));
    expect(nightOf(DateTime(2026, 11, 4, 12, 30)), DateTime(2026, 11, 4));
  });

  test('along the bar: 0 at 5 PM, 1 at 7 AM, clamped', () {
    expect(barPosition(DateTime(2026, 10, 30, 17)), 0);
    expect(barPosition(DateTime(2026, 10, 31, 0)), closeTo(0.5, 1e-9));
    expect(barPosition(DateTime(2026, 10, 31, 7)), 1);
    expect(barPosition(DateTime(2026, 10, 30, 14)), 0); // a daytime launch sits at the start
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
    expect(nights[4].events.map((e) => e.id), ['tiangong:dawn']); // Tuesday night
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
    expect(cloudy.first.clouds.first, 90);
    expect(cloudy[3].hasForecast, isFalse); // past the 48 h of forecast
    expect(cloudy[3].cloudy, isFalse);
    expect(weekNights(const [], now, weather: forecast(10)).first.cloudy, isFalse);
    expect(weekNights(const [], now).first.cloudy, isFalse);
  });

  test('the calendar is two weeks from this Monday, earlier days past and empty', () {
    final days = calendarNights([ev('iss:a', SkyEventType.iss, DateTime(2026, 10, 30, 18, 41))], now);
    expect(days, hasLength(14));
    expect(days.first.date, DateTime(2026, 10, 26)); // Monday
    expect(days.first.date.weekday, DateTime.monday);
    expect(days.where((d) => d.past).map((d) => d.date.day), [26, 27, 28, 29]);
    final tonight = days.firstWhere((d) => d.date == DateTime(2026, 10, 30));
    expect(tonight.past, isFalse);
    expect(tonight.events.single.id, 'iss:a');
    expect(days.last.date, DateTime(2026, 11, 8));
  });
}
