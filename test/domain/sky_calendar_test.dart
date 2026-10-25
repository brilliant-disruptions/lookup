import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/eclipses.dart';
import 'package:lookup/domain/events/launches.dart';
import 'package:lookup/domain/events/meteors.dart';
import 'package:lookup/domain/events/pairings.dart';
import 'package:lookup/domain/models/sky_event.dart';

void main() {
  group('meteor showers', () {
    test('peaks land on IMO 2027 maxima', () {
      // IMO 2027 calendar: Perseids ~08–10 UT Aug 13; Quadrantids 03:30 UT Jan 4.
      final per = solarLongitudeTime(140.0, DateTime.utc(2027, 7, 1));
      expect(per.difference(DateTime.utc(2027, 8, 13, 9)).inHours.abs(), lessThanOrEqualTo(12));
      final qua = solarLongitudeTime(283.15, DateTime.utc(2026, 12, 20));
      expect(qua.difference(DateTime.utc(2027, 1, 4, 3, 30)).inHours.abs(), lessThanOrEqualTo(8));
    });

    test('Geminids night from Nashville: evening tap, best after midnight, rate and moon', () {
      final events = meteorShowerEvents(now: DateTime.utc(2026, 12, 1), latDeg: 36.17, lonDeg: -86.78);
      final gem = events.where((e) => e.details['shower'] == 'Geminids').single;
      expect(gem.type, SkyEventType.meteorShower);
      expect(gem.start.isBefore(gem.peak) || gem.start == gem.peak, isTrue);
      expect(gem.peak.month, 12);
      expect(gem.peak.day, inInclusiveRange(13, 15));
      expect(gem.details['perHour'] as int, greaterThan(20));
      expect(gem.peakElevationDeg, greaterThan(50)); // radiant near overhead
      expect(gem.details['moonIllumination'], isA<double>());
    });

    test('southern showers stay quiet far north', () {
      final events = meteorShowerEvents(now: DateTime.utc(2027, 4, 20), latDeg: 64.1, lonDeg: -21.9);
      expect(events.where((e) => e.details['shower'] == 'Eta Aquariids'), isEmpty);
    });
  });

  group('lunar eclipses', () {
    test('March 2026 total: visible from Los Angeles, not London (daytime)', () {
      final from = DateTime.utc(2026, 2, 25);
      final la = lunarEclipseEvents(now: from, latDeg: 34.05, lonDeg: -118.24);
      expect(la, hasLength(1));
      expect(la.single.details['kind'], 'total');
      expect(la.single.peak, DateTime.utc(2026, 3, 3, 11, 34));
      expect(lunarEclipseEvents(now: from, latDeg: 51.5, lonDeg: -0.12), isEmpty);
    });

    test('penumbral eclipses never alert', () {
      final e = lunarEclipseEvents(now: DateTime.utc(2027, 2, 15), latDeg: 51.5, lonDeg: -0.12);
      expect(e, isEmpty);
    });
  });

  test('planet pairing: Venus and Jupiter, Aug 12 2025 dawn, Nashville', () {
    final events = pairingEvents(now: DateTime.utc(2025, 8, 11), latDeg: 36.17, lonDeg: -86.78, days: 3);
    final vj = events.where((e) => (e.details['bodies'] as List).toSet().containsAll({'Venus', 'Jupiter'})).toList();
    expect(vj, isNotEmpty);
    expect(vj.every((e) => e.details['when'] == 'morning'), isTrue);
    expect(vj.map((e) => e.details['separation'] as double).reduce((a, b) => a < b ? a : b), lessThan(1.5));
  });

  group('rocket launches', () {
    final raw = {
      'id': 'abc',
      'name': 'Falcon 9 Block 5 | Starlink Group 15-16',
      'net': '2026-10-27T04:45:00Z',
      'status': {'abbrev': 'Go'},
      'pad': {'latitude': '34.632', 'longitude': '-120.611', 'location': {'name': 'Vandenberg SFB, CA, USA'}},
      'launch_service_provider': {'name': 'SpaceX'},
    };
    final launch = Launch.fromLaunchLibrary(raw)!;
    final now = DateTime.utc(2026, 10, 25);

    test('parses Launch Library 2', () {
      expect(launch.padLat, 34.632);
      expect(launch.padName, contains('Vandenberg'));
      expect(launch.net, DateTime.utc(2026, 10, 27, 4, 45));
    });

    test('a night Vandenberg launch is visible from LA, not Nashville', () {
      final la = launchEvents(launches: [launch], now: now, latDeg: 34.05, lonDeg: -118.24);
      expect(la, hasLength(1));
      expect(la.single.details['distanceKm'] as int, inInclusiveRange(150, 300));
      expect(la.single.peakAzimuthDeg, inInclusiveRange(270, 320)); // north-west of LA
      expect(launchEvents(launches: [launch], now: now, latDeg: 36.17, lonDeg: -86.78), isEmpty);
    });

    test('daytime and scrubbed launches are skipped', () {
      final day = Launch(id: 'd', name: 'Day', net: DateTime.utc(2026, 10, 26, 19), padLat: 34.632, padLon: -120.611, padName: 'V', status: 'Go');
      final scrub = Launch(id: 's', name: 'Scrub', net: launch.net, padLat: 34.632, padLon: -120.611, padName: 'V', status: 'Hold');
      expect(launchEvents(launches: [day, scrub], now: now, latDeg: 34.05, lonDeg: -118.24), isEmpty);
    });
  });
}
