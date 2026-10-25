import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/orbit/orbit_facts.dart';
import 'package:lookup/domain/satellites/bright_tonight.dart';
import 'package:lookup/domain/satellites/crew.dart';

void main() {
  // Celestrak's "visual" group as fetched on 2026-10-25.
  final visual = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/visual_omm.json').readAsStringSync()));
  final iss = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync())).single;

  test('friendly names', () {
    OmmRecord named(String n, [int id = 1]) => OmmRecord.fromJson({'OBJECT_NAME': n, 'NORAD_CAT_ID': id});
    expect(friendlySatelliteName(named('HST')), 'Hubble Space Telescope');
    expect(friendlySatelliteName(named('SL-16 R/B')), 'Zenit rocket stage');
    expect(friendlySatelliteName(named('SPACEMOBILE-003')), 'BlueBird 3 (AST SpaceMobile)');
    expect(friendlySatelliteName(named('ENVISAT')), 'Envisat');
    expect(friendlySatelliteName(named('ISS (ZARYA)', Norad.iss)), 'Space station (ISS)');
  });

  test('a night over London: bright, high, sunlit passes, brightest first then by time', () {
    // 17:00Z Oct 25 → 06:30Z Oct 26: one London night.
    final from = DateTime.utc(2026, 10, 25, 17), to = DateTime.utc(2026, 10, 26, 6, 30);
    final sw = Stopwatch()..start();
    final events = brightTonight(records: visual, latDeg: 51.5, lonDeg: -0.12, from: from, to: to);
    expect(sw.elapsed, lessThan(const Duration(seconds: 20)));
    expect(events, isNotEmpty);
    expect(events.length, lessThanOrEqualTo(15));
    for (final e in events) {
      expect(e.type, SkyEventType.satellitePass);
      expect((e.details['magnitude'] as num), lessThanOrEqualTo(3.5));
      expect(e.peakElevationDeg, greaterThanOrEqualTo(20));
      expect(e.id, startsWith('sat:'));
      expect(e.details['omm'], isA<Map>()); // the finder can track it
      expect(e.details['noradId'], isNot(Norad.iss));
    }
    for (var i = 1; i < events.length; i++) {
      expect(events[i].start.isBefore(events[i - 1].start), isFalse);
    }
  });

  test('crew by station from Launch Library expeditions', () {
    final crew = crewFromExpeditions(jsonDecode(File('test/fixtures/expeditions_sample.json').readAsStringSync()));
    expect(crew[Station.iss], hasLength(7));
    expect(crew[Station.tiangong], hasLength(3));
    expect(crew[Station.iss]!.first.role, 'Commander');
    expect(crewFromExpeditions({'detail': 'throttled'}), isEmpty);
  });

  test('ISS orbit facts are the textbook numbers', () {
    final f = OrbitFacts.at(iss, DateTime.utc(2026, 10, 21));
    expect(f.speedKmS, closeTo(7.66, 0.05));
    expect(f.altitudeKm, inInclusiveRange(380, 440));
    expect(f.minutesPerOrbit, closeTo(93, 1));
    expect(f.speedMph, closeTo(17100, 150));
  });

  test('trimmed expeditions keep what the parser needs', () {
    final full = jsonDecode(File('test/fixtures/expeditions_sample.json').readAsStringSync());
    final trimmed = trimExpeditions(full);
    expect(crewFromExpeditions(trimmed)[Station.iss]!.map((c) => c.name),
        crewFromExpeditions(full)[Station.iss]!.map((c) => c.name));
  });
}
