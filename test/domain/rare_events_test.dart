import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/rare_events.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/sky/visibility.dart';

/// Rare comets and novae from the relay's curated list. "Comet NEOWISE
/// tonight" is a promise, so a night only counts when [canSee] says the
/// naked eye gets it from here: twilight, moonlight and a bright sky all
/// say no before any alert is planned. Fixtures: NEOWISE (July 2020,
/// Horizons positions) and RS Ophiuchi (August 2021).
void main() {
  final json = jsonDecode(File('test/fixtures/rare_events.json').readAsStringSync());
  final objects = parseRareEvents(json);
  RareObject neowise() => objects.firstWhere((o) => o.kind == RareKind.comet);
  RareObject rsOph() => objects.firstWhere((o) => o.kind == RareKind.nova);

  const planner = AlertPlanner();
  const plus = LookUpSettings(isPlus: true, quietHours: QuietHours(startMinute: 0, endMinute: 0));
  const free = LookUpSettings(quietHours: QuietHours(startMinute: 0, endMinute: 0));
  const mdt = -6 * 60;
  final numbers = RegExp(r'\d\s*°|azimuth|elevation', caseSensitive: false);

  // Denver, from a dark site.
  List<SkyEvent> denver(DateTime now, {SkyDarkness darkness = SkyDarkness.dark, int days = 1, List<RareObject>? from}) =>
      rareEventEvents(objects: from ?? objects, now: now, latDeg: 39.74, lonDeg: -104.99, darkness: darkness, days: days);

  // The evening of 20 July 2020: NEOWISE low in the northwest after dusk.
  final cometNow = DateTime.utc(2020, 7, 20, 18);
  // The evening of 9 August 2021, RS Oph at its peak.
  final novaNow = DateTime.utc(2021, 8, 9, 18);

  group('parsing: a bad entry is dropped, never guessed at', () {
    Map<String, Object?> entry(Map<String, Object?> over) => {
          'id': 'x',
          'kind': 'comet',
          'name': 'Comet X',
          'magnitude': 3.0,
          'validUntil': '2030-01-03',
          'note': 'n',
          'ephemeris': [
            {'date': '2030-01-01', 'ra': 10.0, 'dec': 20.0},
            {'date': '2030-01-02', 'ra': 11.0, 'dec': 21.0},
          ],
          ...over,
        };

    test('the fixture parses whole', () {
      expect(objects.map((o) => o.id), ['comet-c2020f3', 'nova-rsoph-2021']);
      expect(neowise().rows, hasLength(21));
      expect(rsOph().rows, hasLength(1));
    });

    test('bad kind, place, order, a lone comet row, missing words', () {
      expect(RareObject.fromJson(entry({})), isNotNull);
      expect(RareObject.fromJson(entry({'kind': 'asteroid'})), isNull);
      expect(RareObject.fromJson(entry({'name': null})), isNull);
      expect(RareObject.fromJson(entry({'note': 3})), isNull);
      expect(RareObject.fromJson(entry({'magnitude': 'bright'})), isNull);
      expect(RareObject.fromJson(entry({'validUntil': 'soon'})), isNull);
      expect(
          RareObject.fromJson(entry({
            'ephemeris': [
              {'date': '2030-01-01', 'ra': 360.0, 'dec': 0.0},
              {'date': '2030-01-02', 'ra': 1.0, 'dec': 0.0},
            ]
          })),
          isNull);
      expect(
          RareObject.fromJson(entry({
            'ephemeris': [
              {'date': '2030-01-01', 'ra': 1.0, 'dec': 91.0},
              {'date': '2030-01-02', 'ra': 1.0, 'dec': 0.0},
            ]
          })),
          isNull);
      expect(
          RareObject.fromJson(entry({
            'ephemeris': [
              {'date': '2030-01-02', 'ra': 1.0, 'dec': 0.0},
              {'date': '2030-01-01', 'ra': 1.0, 'dec': 0.0},
            ]
          })),
          isNull,
          reason: 'rows out of order');
      expect(
          RareObject.fromJson(entry({
            'ephemeris': [
              {'date': '2030-01-01', 'ra': 1.0, 'dec': 0.0}
            ]
          })),
          isNull,
          reason: 'a comet moves: one row is not enough');
      expect(
          RareObject.fromJson(entry({
            'kind': 'nova',
            'ephemeris': [
              {'date': '2030-01-01', 'ra': 1.0, 'dec': 0.0}
            ]
          })),
          isNotNull,
          reason: 'a nova stays put');
    });

    test('a broken list is nothing, and one bad entry leaves the rest', () {
      expect(parseRareEvents(null), isEmpty);
      expect(parseRareEvents({'events': 'no'}), isEmpty);
      expect(parseRareEvents({'events': [entry({'kind': 'x'}), entry({})]}).single.id, 'x');
    });

    test('between rows it interpolates, across 0h of RA the short way', () {
      final o = RareObject.fromJson(entry({
        'ephemeris': [
          {'date': '2030-01-01', 'ra': 359.0, 'dec': 10.0, 'mag': 3.0},
          {'date': '2030-01-02', 'ra': 1.0, 'dec': 12.0, 'mag': 4.0},
        ]
      }))!;
      final mid = o.at(DateTime.utc(2030, 1, 1, 12))!;
      expect(mid.ra, closeTo(0, 1e-9));
      expect(mid.dec, closeTo(11, 1e-9));
      expect(mid.mag, closeTo(3.5, 1e-9));
      expect(o.at(DateTime.utc(2029, 12, 31, 23)), isNull, reason: 'before its first row');
      expect(o.at(DateTime.utc(2030, 1, 2, 1)), isNull, reason: 'after its last row');
    });

    test('a nova is there from the day it was found until valid-until, never before', () {
      final o = rsOph();
      expect(o.at(DateTime.utc(2021, 8, 8, 23)), isNull);
      expect(o.at(DateTime.utc(2021, 8, 9, 3))!.mag, 4.8);
      expect(o.at(DateTime.utc(2021, 8, 20, 23)), isNotNull);
      expect(o.at(DateTime.utc(2021, 8, 21)), isNull);
      // The July 2020 comet nights must not show a nova from a year later.
      expect(denver(DateTime.utc(2020, 7, 14, 18), days: 14).where((e) => e.type == SkyEventType.nova), isEmpty);
    });
  });

  group('the nights it can really be seen', () {
    test('NEOWISE from a dark site near Denver: low in the northwest after dusk', () {
      final e = denver(cometNow).single;
      expect(e.type, SkyEventType.comet);
      expect(e.id, 'comet:comet-c2020f3:20200720');
      expect(e.details['name'], 'Comet NEOWISE');
      expect(e.peakElevationDeg, inInclusiveRange(10, 30));
      expect(e.peakAzimuthDeg, inInclusiveRange(290, 340));
      // After the end of nautical twilight (~9:30 PM MDT) and gone by 11.
      expect(e.start.isAfter(DateTime.utc(2020, 7, 21, 3, 20)), isTrue);
      expect(e.end.isBefore(DateTime.utc(2020, 7, 21, 5)), isTrue);
      expect(e.details['magnitude'] as double, lessThanOrEqualTo(rareMaxMagnitude));
    });

    test('a fuzzy comet in a suburban or city twilight is not promised', () {
      // The same night: magnitude ~4 diffuse, never higher than ~20° once
      // it's dark enough. canSee says no, so there's no event to alert on.
      expect(denver(cometNow, darkness: SkyDarkness.suburbs), isEmpty);
      expect(denver(cometNow, darkness: SkyDarkness.city, days: 14), isEmpty);
    });

    test('magnitude floor: once it fades past 5 it is gone, however dark', () {
      final nights = denver(DateTime.utc(2020, 7, 14, 18), days: 14).where((e) => e.type == SkyEventType.comet);
      expect(nights, isNotEmpty);
      for (final e in nights) {
        expect(e.details['magnitude'] as double, lessThanOrEqualTo(rareMaxMagnitude), reason: e.id);
      }
      // Rows past 26 July are fainter than 5.0.
      expect(nights.map((e) => e.id), isNot(contains(anyOf('comet:comet-c2020f3:20200726', 'comet:comet-c2020f3:20200727'))));
      // And a copy of it at 5.3 throughout never shows up.
      final faint = RareObject.fromJson({
        ...(json['events'] as List).first as Map<String, Object?>,
        'ephemeris': [
          for (final r in ((json['events'] as List).first as Map)['ephemeris'] as List) {...r as Map, 'mag': 5.3}
        ],
      })!;
      expect(denver(DateTime.utc(2020, 7, 14, 18), days: 14, from: [faint]), isEmpty);
    });

    test('RS Oph at 4.8 needs a dark sky: listed there, not from the suburbs', () {
      final e = denver(novaNow).single;
      expect(e.type, SkyEventType.nova);
      expect(e.id, 'nova:nova-rsoph-2021:20210809');
      expect(e.details['name'], 'RS Ophiuchi');
      expect(denver(novaNow, darkness: SkyDarkness.suburbs), isEmpty);
      expect(denver(novaNow, darkness: SkyDarkness.city), isEmpty);
    });

    test('ids and starts hold as the night goes on, so nothing re-fires', () {
      final early = denver(cometNow).single;
      // A day ahead from mid-event also reaches the next night: take tonight's.
      final later = denver(early.start.add(const Duration(minutes: 20))).first;
      expect(later.id, early.id);
      expect(later.start, early.start);
    });
  });

  group('alerts', () {
    test('the defaults: comets are LookUp+, a nova is for everyone, both pushed', () {
      expect(SkyEventType.comet.plusOnly, rareCometPlusOnly);
      expect(SkyEventType.nova.plusOnly, rareNovaPlusOnly);
      expect(rareCometPlusOnly, isTrue);
      expect(rareNovaPlusOnly, isFalse);
      expect(SkyEventType.comet.pushes, isTrue);
      expect(SkyEventType.nova.pushes, isTrue);
    });

    test('a nova reaches free users, in words', () {
      final e = denver(novaNow).single;
      final plan = planner.plan(events: [e], settings: free, now: novaNow, utcOffsetMinutes: mdt);
      expect(plan.map((a) => a.kind), [AlertKind.headsUp, AlertKind.goNow]);
      expect(plan[0].title, 'New star: RS Ophiuchi tonight');
      expect(plan[0].body, contains('A recurrent nova in Ophiuchus'));
      expect(plan[1].fireAt.isBefore(e.start), isTrue);
      for (final a in plan) {
        expect(a.body, isNot(matches(numbers)), reason: 'words, not az/el numbers, on the main path');
      }
    });

    test('a comet is LookUp+: free users see it in the preview, Plus gets the tap', () {
      final e = denver(cometNow).single;
      expect(planner.plan(events: [e], settings: free, now: cometNow, utcOffsetMinutes: mdt), isEmpty);
      expect(AlertPlanner.plusOnlyAhead([e], cometNow).single.id, e.id);
      final plan = planner.plan(events: [e], settings: plus, now: cometNow, utcOffsetMinutes: mdt);
      expect(plan.map((a) => a.kind), [AlertKind.headsUp, AlertKind.goNow]);
      expect(plan[0].title, 'Comet NEOWISE tonight');
      for (final a in plan) {
        expect(a.body, isNot(matches(numbers)), reason: 'words, not az/el numbers, on the main path');
      }
    });

    test('cloud-gated, behind its own switch', () {
      for (final e in [denver(cometNow).single, denver(novaNow).single]) {
        final now = e.type == SkyEventType.comet ? cometNow : novaNow;
        expect(planner.plan(events: [e.copyWith(cloudCoverPercent: 90)], settings: plus, now: now, utcOffsetMinutes: mdt),
            isEmpty, reason: e.id);
        expect(planner.plan(events: [e], settings: plus.copyWith(rareEventsEnabled: false), now: now, utcOffsetMinutes: mdt),
            isEmpty, reason: e.id);
        expect(
            planner.plan(events: [e.copyWith(cloudCoverPercent: 10)], settings: plus, now: now, utcOffsetMinutes: mdt)[0].body,
            endsWith('Clear skies.'),
            reason: e.id);
      }
    });

    test('quiet hours hold, with no wake-me exception', () {
      final e = denver(novaNow).single;
      const allNight = QuietHours(startMinute: 20 * 60, endMinute: 6 * 60);
      expect(
          planner.plan(
              events: [e], settings: plus.copyWith(quietHours: allNight, auroraWakeMe: true), now: novaNow, utcOffsetMinutes: mdt),
          isEmpty);
    });
  });
}
