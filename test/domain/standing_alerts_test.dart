import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/standing_alerts.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/night_plan.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';

void main() {
  late SkyCatalog catalog;
  setUpAll(() {
    catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
        jsonDecode(File('assets/sky/constellations.json').readAsStringSync()));
  });

  /// Hourly cover from [from] for [hours]: [cover] gives each hour's percent.
  CloudForecast sky(DateTime from, int hours, int Function(int h) cover, {double lat = 0, double lon = 0}) =>
      CloudForecast(latitude: lat, longitude: lon, fetchedAt: from, hourly: [
        for (var h = 0; h < hours; h++)
          CloudSample(time: DateTime.utc(from.year, from.month, from.day, from.hour + h), coverPercent: cover(h)),
      ]);

  const planner = AlertPlanner();
  final saturn = SkyId.planet(Planet.saturn);

  group('favourite at its best', () {
    // Nashville, noon on 2026-10-20: Saturn, a fortnight past opposition, is
    // good tonight (see night_plan_test).
    const lat = 36.17, lon = -86.78;
    final noon = DateTime.utc(2026, 10, 20, 17);

    List<NightPlan> nights(CloudForecast? w) => [
          for (final win in darkWindows(noon, lat, lon))
            planNight(catalog: catalog, at: win.start, lat: lat, lon: lon, darkness: SkyDarkness.suburbs, weather: w),
        ];

    List<SkyEvent> build(CloudForecast? w, {StandingLog log = const {}, List<String>? favourites}) => favouriteEvents(
          favourites: favourites ?? [saturn],
          nights: nights(w),
          weather: w,
          names: {saturn: 'Saturn'},
          log: log,
          now: noon,
        );

    final clear = sky(noon, 48, (_) => 5);

    test('a clear night gives one tap, at its best, worded for people', () {
      final [e] = build(clear);
      expect(e.type, SkyEventType.favourite);
      expect(e.plusOnly, isTrue);
      expect(e.start.isAfter(noon), isTrue);
      final title = AlertPlanner.headsUpTitle(e, 10);
      expect(title, 'Saturn at its best in 10 min');
      expect(AlertPlanner.headsUpBody(e), contains('Look '));
      expect(AlertPlanner.headsUpBody(e), isNot(matches(RegExp(r'\d+°'))), reason: 'no numbers on the main path');
    });

    test('never through cloud, and never without a forecast', () {
      expect(build(sky(noon, 48, (_) => 90)), isEmpty);
      expect(build(null), isEmpty);
      // Clear the first night only: tonight's tap, not tomorrow's.
      final firstOnly = build(sky(noon, 48, (h) => h < 20 ? 5 : 90));
      expect(firstOnly, hasLength(1));
    });

    test('one tap per favourite even when both nights are good', () {
      expect(build(clear), hasLength(1));
    });

    test('spaced out: not again within six days, the same night still counts', () {
      final [tonight] = build(clear);
      expect(build(clear, log: {'fav:$saturn': tonight.start.subtract(const Duration(days: 3))}), isEmpty);
      expect(build(clear, log: {'fav:$saturn': tonight.start.subtract(const Duration(days: 7))}), hasLength(1));
      expect(build(clear, log: {'fav:$saturn': tonight.start.subtract(const Duration(minutes: 10))}), hasLength(1));
    });

    test('LookUp+ only, and a fleeting pass always wins the nightly slot', () {
      final [fav] = build(clear);
      final iss = SkyEvent(
        id: 'iss:x',
        type: SkyEventType.iss,
        start: fav.start.add(const Duration(minutes: 40)),
        peak: fav.start.add(const Duration(minutes: 42)),
        end: fav.start.add(const Duration(minutes: 44)),
        peakElevationDeg: 30,
        riseAzimuthDeg: 250,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 90,
        cloudCoverPercent: 5,
      );
      final base = LookUpSettings(
          latitude: lat, longitude: lon, favourites: [saturn], quietHours: const QuietHours(startMinute: 0, endMinute: 0), maxAlertsPerNight: 1);
      expect(planner.plan(events: [fav], settings: base, now: noon, utcOffsetMinutes: -300), isEmpty);
      final plus = base.copyWith(isPlus: true);
      final planned = planner.plan(events: [fav, iss], settings: plus, now: noon, utcOffsetMinutes: -300);
      expect(planned.map((p) => p.event.id).toSet(), {'iss:x'});
      final alone = planner.plan(events: [fav], settings: plus, now: noon, utcOffsetMinutes: -300);
      expect(alone.map((p) => p.kind), [AlertKind.headsUp], reason: 'no go-now nudge for something up for hours');
      expect(planner.plan(events: [fav], settings: plus.copyWith(favouriteAlertsEnabled: false), now: noon, utcOffsetMinutes: -300),
          isEmpty);
    });
  });

  group('Milky Way nights', () {
    // Pickett CCC State Park, TN (a dark-sky park), noon on 2026-10-10: new
    // Moon, the Cygnus Milky Way high after dark.
    const lat = 36.55, lon = -84.80;
    final noon = DateTime.utc(2026, 10, 10, 17);
    final clear = sky(noon, 48, (_) => 5, lat: lat, lon: lon);

    List<SkyEvent> build(DateTime now, CloudForecast? w, {bool here = true, StandingLog log = const {}}) =>
        milkyWayEvents(
          places: [(name: 'Pickett', lat: lat, lon: lon, here: here, weather: w)],
          now: now,
          log: log,
        );

    test('new Moon and clear: one tap for a run of hours after dark', () {
      expect(moonIllumination(DateTime.utc(2026, 10, 11, 2)), lessThan(0.02));
      final [e] = build(noon, clear);
      expect(e.type, SkyEventType.milkyWayNight);
      expect(e.plusOnly, isTrue);
      expect(e.end.difference(e.start), greaterThanOrEqualTo(const Duration(hours: 2)));
      // Starts after astronomical dusk (~8:40 PM EDT), not at sunset.
      expect(e.start.isAfter(DateTime.utc(2026, 10, 11, 0, 20)), isTrue);
      expect(AlertPlanner.headsUpTitle(e, 10), startsWith('Milky Way night from '));
    });

    test('never with the Moon up, through cloud, or without a forecast', () {
      // Full Moon on the 26th.
      final full = DateTime.utc(2026, 10, 26, 17);
      expect(build(full, sky(full, 48, (_) => 5, lat: lat, lon: lon)), isEmpty);
      expect(build(noon, sky(noon, 48, (_) => 70, lat: lat, lon: lon)), isEmpty);
      expect(build(noon, null), isEmpty);
    });

    test('a short gap in the cloud is not a Milky Way night', () {
      // Clear only 9–10 PM local (01–02Z).
      final gap = sky(noon, 48, (h) => (h == 8 || h == 9) ? 5 : 80, lat: lat, lon: lon);
      expect(build(noon, gap), isEmpty);
    });

    test('spaced out per place: not again within three days', () {
      final [e] = build(noon, clear);
      expect(build(noon, clear, log: {'mw:${e.details['placeKey']}': e.start.subtract(const Duration(days: 1))}), isEmpty);
      expect(build(noon, clear, log: {'mw:${e.details['placeKey']}': e.start.subtract(const Duration(days: 4))}), hasLength(1));
    });

    test('somewhere else: a trip tap three hours ahead, judged by when it arrives', () {
      final [away] = build(noon, clear, here: false);
      final s = LookUpSettings(latitude: 36.17, longitude: -86.78, isPlus: true);
      final [p] = planner.plan(events: [away], settings: s, now: noon, utcOffsetMinutes: -240);
      expect(p.fireAt, away.start.subtract(milkyWayTripLead));
      expect(p.title, 'Milky Way night at Pickett tonight');
      // A ~9 PM start is a ~6 PM tap: outside default quiet hours even
      // though the night itself runs into them.
      expect(AlertPlanner.passesQuietHours(away, s, -240), isTrue);

      final [here] = build(noon, clear);
      final [h] = planner.plan(events: [here], settings: s, now: noon, utcOffsetMinutes: -240);
      expect(h.fireAt, here.start.subtract(Duration(minutes: s.leadMinutes)));
    });
  });

  group('the log', () {
    final now = DateTime.utc(2026, 10, 20, 17);
    SkyEvent fav(String id) => SkyEvent(
          id: 'fav:$id:x',
          type: SkyEventType.favourite,
          start: now.add(const Duration(hours: 6)),
          peak: now.add(const Duration(hours: 6)),
          end: now.add(const Duration(hours: 7)),
          peakElevationDeg: 40,
          riseAzimuthDeg: 0,
          peakAzimuthDeg: 0,
          setAzimuthDeg: 0,
          details: {'favourite': id},
        );

    test('records what is planned, forgets what was dropped, keeps what fired', () {
      final at = now.add(const Duration(hours: 5, minutes: 50));
      var log = updateStandingLog({}, [(event: fav('a'), fireAt: at)], now);
      expect(log, {'fav:a': at});
      // Next refresh: the forecast turned and it's no longer planned.
      expect(updateStandingLog(log, const [], now), isEmpty);
      // Or it already fired before this refresh: it stays, so no repeat.
      log = updateStandingLog(log, const [], at.add(const Duration(minutes: 5)));
      expect(log.keys, ['fav:a']);
      // Two weeks on it's let go.
      expect(updateStandingLog(log, const [], at.add(const Duration(days: 15))), isEmpty);
    });
  });
}
