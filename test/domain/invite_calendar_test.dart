import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/plan/invite_calendar.dart';

void main() {
  final start = DateTime.utc(2026, 11, 3, 3, 5);
  String ics({String look = 'Face west-southwest. It climbs high, then fades out toward the east.', String? place = 'Nashville', int? clouds = 8}) =>
      inviteIcs(
        uid: 'iss-1',
        title: 'ISS flyover',
        start: start,
        end: start.add(const Duration(minutes: 4)),
        look: look,
        place: place,
        clouds: clouds,
        now: DateTime.utc(2026, 11, 2, 22),
      );

  test('one event, at the right moment, with a reminder ten minutes before', () {
    final s = ics();
    expect(s, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(s, endsWith('END:VCALENDAR\r\n'));
    expect(s, contains('DTSTART:20261103T030500Z'));
    expect(s, contains('DTEND:20261103T030900Z'));
    expect(s, contains('SUMMARY:ISS flyover: look up'));
    expect(s, contains('LOCATION:Nashville'));
    expect(s, contains('TRIGGER:-PT10M'));
    expect(s.replaceAll('\r\n ', ''), contains(r'Clear skies forecast.'));
  });

  test('escaped and folded the way calendars expect', () {
    final s = ics(look: 'Look west, low; then up.\nSoon.');
    expect(s.replaceAll('\r\n ', ''), contains(r'Look west\, low\; then up.\nSoon.'));
    for (final line in s.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75), reason: line);
    }
    final long = ics(look: 'Never look at the Sun without certified eclipse glasses (ISO 12312-2), not even when it’s mostly covered. ' * 3);
    for (final line in long.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
    }
  });

  test('no place, no forecast: those lines just go', () {
    final s = ics(place: null, clouds: null);
    expect(s, isNot(contains('LOCATION')));
    expect(s, isNot(contains('forecast')));
  });

  test('cloud words match the invite page', () {
    expect(inviteCloudWords(10), 'Clear skies forecast.');
    expect(inviteCloudWords(45), 'Some cloud forecast: gaps are likely.');
    expect(inviteCloudWords(90), 'Cloudy forecast: it may be hidden.');
    expect(inviteCloudWords(null), '');
  });
}
