import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/occultations.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/sky/catalog.dart';

/// Occultation alerts (LookUp+). "The Moon covers Mars at 6:30" is a
/// promise: it's only pushed when the track is well inside the Moon's edge,
/// and a graze is listed as "near the Moon" and never pushed. The events
/// are the IOTA-pinned ones from occultations_test.dart.
void main() {
  late SkyCatalog catalog;
  setUpAll(() {
    catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
        jsonDecode(File('assets/sky/constellations.json').readAsStringSync()),
        jsonDecode(File('assets/sky/proper_motion.json').readAsStringSync()));
  });

  const planner = AlertPlanner();
  const plus = LookUpSettings(isPlus: true);
  const noQuiet = QuietHours(startMinute: 0, endMinute: 0);
  final numbers = RegExp(r'\d\s*°|azimuth|elevation', caseSensitive: false);

  List<SkyEvent> at(double lat, double lon, DateTime now) =>
      occultationEvents(now: now, latDeg: lat, lonDeg: lon, stars: catalog.stars, days: 1);

  // Mars behind the Moon from Los Angeles, 8 Dec 2022: 6:30 PM PST, not in
  // quiet hours. IOTA: goes in 02:30:23 UTC, out 03:30:11.
  final laNow = DateTime.utc(2022, 12, 7, 20);
  const pst = -8 * 60;
  List<SkyEvent> mars() => at(33.943, -118.408, laNow);

  test('Mars from Los Angeles: a Plus alert that lands before it can happen', () {
    final e = mars().single;
    expect(e.type, SkyEventType.occultation);
    expect(e.type.pushes, isTrue);
    expect(e.plusOnly, isTrue);
    expect(e.id, startsWith('occ:Mars-'));
    final d = DateTime.parse(e.details['disappears'] as String);
    final pm = Duration(seconds: e.details['plusMinusSeconds'] as int);
    // The window opens at the earliest it could go in, so the go-now
    // tap is never late even at the edge of the error.
    expect(e.start, d.subtract(pm));
    expect(d.difference(DateTime.utc(2022, 12, 8, 2, 30, 23)).abs(), lessThanOrEqualTo(pm));

    final plan = planner.plan(events: [e], settings: plus, now: laNow, utcOffsetMinutes: pst);
    expect(plan.map((a) => a.kind), [AlertKind.headsUp, AlertKind.goNow]);
    expect(plan[0].title, 'The Moon covers Mars in 10 min');
    expect(plan[0].body, matches(RegExp(r'^Mars goes behind the Moon at \d+:\d\d [AP]M and comes back at \d+:\d\d [AP]M \(give or take \d+ (s|min)\)\. The Moon is .+ in the .+\. Binoculars help\.$')));
    expect(plan[1].fireAt.isBefore(d.subtract(pm)), isTrue);
    expect(plan[1].body, startsWith('Look '));
    expect(plan[1].body, contains('at the Moon'));
    for (final a in plan) {
      expect(a.body, isNot(matches(numbers)), reason: 'words, not az/el numbers, on the main path');
    }
  });

  test('free users see it listed and in the LookUp+ preview, but get no tap', () {
    final e = mars().single;
    expect(planner.plan(events: [e], settings: const LookUpSettings(), now: laNow, utcOffsetMinutes: pst), isEmpty);
    expect(AlertPlanner.plusOnlyAhead([e], laNow).single.id, e.id);
  });

  test('cloud-gated, behind its own switch', () {
    final e = mars().single;
    expect(planner.plan(events: [e.copyWith(cloudCoverPercent: 90)], settings: plus, now: laNow, utcOffsetMinutes: pst),
        isEmpty);
    expect(planner.plan(events: [e], settings: plus.copyWith(occultationsEnabled: false), now: laNow, utcOffsetMinutes: pst),
        isEmpty);
    expect(planner.plan(events: [e.copyWith(cloudCoverPercent: 10)], settings: plus, now: laNow, utcOffsetMinutes: pst)[0].body,
        endsWith('Clear skies.'));
  });

  test('quiet hours hold, with no wake-me exception: Spica from Lagos at 4 AM', () {
    final now = DateTime.utc(2025, 1, 20, 15);
    final e = at(6.577, 3.322, now).single;
    expect(e.type, SkyEventType.occultation);
    expect(planner.plan(events: [e], settings: plus.copyWith(auroraWakeMe: true), now: now, utcOffsetMinutes: 60), isEmpty);
    expect(planner.plan(events: [e], settings: plus.copyWith(quietHours: noQuiet), now: now, utcOffsetMinutes: 60),
        isNotEmpty);
  });

  test('only the contacts that can be seen: Luanda sees Spica go in, not come out', () {
    final now = DateTime.utc(2025, 1, 20, 15);
    final e = at(-8.858, 13.232, now).single;
    expect(e.details.containsKey('reappears'), isFalse);
    final body = planner.plan(events: [e], settings: plus.copyWith(quietHours: noQuiet), now: now, utcOffsetMinutes: 60)[0].body;
    expect(body, startsWith('Spica goes behind the Moon at '));
    expect(body, isNot(contains('comes back')));
  });

  test('a graze is "near the Moon": listed, never pushed, never "covers"', () {
    // Aldebaran at Taiwan's southern limit, 9 Jan 2017. Quiet hours off so
    // the only thing stopping it is that it's a graze.
    final now = DateTime.utc(2017, 1, 9, 3);
    final e = at(24.023, 121.618, now).single; // Hualien
    expect(e.type, SkyEventType.occultationNear);
    expect(e.type.pushes, isFalse);
    expect(e.id, startsWith('occnear:Aldebaran-'));
    expect(e.details['label'], 'Aldebaran near the Moon');
    expect(e.details.keys, isNot(contains('disappears')));
    expect(AlertPlanner.headsUpTitle(e, 10), isNot(contains('covers')));
    final settings = plus.copyWith(quietHours: noQuiet);
    expect(planner.plan(events: [e], settings: settings, now: now, utcOffsetMinutes: 480), isEmpty);
    expect(AlertPlanner.plusOnlyAhead([e], now), isEmpty);
  });
}
