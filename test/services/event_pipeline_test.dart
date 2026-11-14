import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/data/open_meteo_client.dart';
import 'package:lookup/domain/aurora/aurora_rules.dart';
import 'package:lookup/domain/aurora/seen_nearby.dart';
import 'package:lookup/domain/events/rare_events.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/visibility.dart' show SkyDarkness;
import 'package:lookup/domain/weather/cloud_forecast.dart';
import 'package:lookup/services/event_pipeline.dart';

void main() {
  final iss = OmmRecord.listFromJson(
      jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync()));
  final starlink = OmmRecord.listFromJson(
      jsonDecode(File('test/fixtures/starlink_sample.json').readAsStringSync()));
  final now = DateTime.utc(2026, 10, 20, 16);
  const nashville = LookUpSettings(latitude: 36.17, longitude: -86.78, isPlus: true);

  test('no location → no events', () {
    expect(const EventPipeline().build(PipelineInputs(settings: const LookUpSettings(), now: now)), isEmpty);
  });

  test('builds ISS + Starlink + aurora outlook/now, sorted by start', () {
    final forecast = [
      for (var h = 0; h < 72; h += 3)
        KpForecastPoint(time: now.add(Duration(hours: h)), kp: 9, kind: 'predicted'),
    ];
    final events = const EventPipeline(horizon: Duration(days: 21)).build(PipelineInputs(
      settings: nashville,
      now: DateTime.utc(2026, 10, 22, 4), // 11pm CDT: dark
      iss: iss,
      starlink: starlink,
      aurora: AuroraSnapshot(fetchedAt: now, kpNow: 9, forecast: forecast, ovationProbability: 80),
    ));
    final types = events.map((e) => e.type).toSet();
    expect(types, contains(SkyEventType.iss));
    expect(types, contains(SkyEventType.auroraOutlook));
    expect(types, contains(SkyEventType.auroraNow));
    for (var i = 1; i < events.length; i++) {
      expect(events[i].start.isBefore(events[i - 1].start), isFalse);
    }
    final sl = events.where((e) => e.type == SkyEventType.starlinkTrain);
    for (final e in sl) {
      expect(e.details['count'], 8);
      expect(e.id, startsWith('starlink-2026-'));
    }
    final an = events.singleWhere((e) => e.type == SkyEventType.auroraNow);
    expect(an.id, 'aurora-now:20261022T0300Z'); // 3-hour bucket
    expect(an.start, DateTime.utc(2026, 10, 22, 4));
  });

  test('lists ISS transits for London with where to stand, and respects the toggle', () {
    const london = LookUpSettings(latitude: 51.5, longitude: -0.12);
    final events = const EventPipeline().build(PipelineInputs(settings: london, now: now, iss: iss));
    final transits = events.where((e) => e.type == SkyEventType.issTransit).toList();
    expect(transits, isNotEmpty);
    for (final t in transits) {
      expect(t.details['body'], anyOf('Sun', 'Moon'));
      expect((t.details['travelKm'] as num), lessThanOrEqualTo(50));
      expect(t.end.difference(t.start).inMilliseconds, t.details['crossingMs']);
    }
    final off = const EventPipeline().build(PipelineInputs(
        settings: london.copyWith(transitsEnabled: false), now: now, iss: iss));
    expect(off.where((e) => e.type == SkyEventType.issTransit), isEmpty);
  });

  test('Saturn\'s opposition shows up as a planet highlight at dusk', () {
    final events = const EventPipeline().build(PipelineInputs(settings: nashville, now: DateTime.utc(2026, 10, 1, 12)));
    final saturn = events.where((e) => e.type == SkyEventType.planetHighlight && e.details['planet'] == 'Saturn').toList();
    expect(saturn, hasLength(1));
    expect(saturn.single.start.toUtc().day, anyOf(4, 5)); // evening of Oct 4 CDT is Oct 5 UTC
    expect(saturn.single.details['label'], 'Saturn at its brightest');
    final off = const EventPipeline()
        .build(PipelineInputs(settings: nashville.copyWith(pairingsEnabled: false), now: DateTime.utc(2026, 10, 1, 12)));
    expect(off.where((e) => e.type == SkyEventType.planetHighlight), isEmpty);
  });

  test('the Moon covering Mars is listed for everyone, behind its own switch', () {
    // 8 Dec 2022 from Los Angeles (IOTA-pinned in occultations_test.dart).
    // Listed for free users too; only LookUp+ gets the tap (the planner).
    final catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
        jsonDecode(File('assets/sky/constellations.json').readAsStringSync()),
        jsonDecode(File('assets/sky/proper_motion.json').readAsStringSync()));
    const la = LookUpSettings(latitude: 33.94, longitude: -118.41);
    final when = DateTime.utc(2022, 12, 7, 12);
    final events = const EventPipeline().build(PipelineInputs(settings: la, now: when, catalog: catalog));
    final mars = events.where((e) => e.type == SkyEventType.occultation && e.details['body'] == 'Mars').single;
    expect(mars.start.toUtc().day, 8);
    final off = const EventPipeline()
        .build(PipelineInputs(settings: la.copyWith(occultationsEnabled: false), now: when, catalog: catalog));
    expect(off.where((e) => e.type == SkyEventType.occultation || e.type == SkyEventType.occultationNear), isEmpty);
  });

  test('a curated comet is listed from a dark site, behind its own switch', () {
    // NEOWISE from near Denver, 20 July 2020 (rare_events_test.dart).
    final rare = parseRareEvents(jsonDecode(File('test/fixtures/rare_events.json').readAsStringSync()));
    const denver = LookUpSettings(latitude: 39.74, longitude: -104.99, skyDarkness: SkyDarkness.dark);
    final when = DateTime.utc(2020, 7, 20, 18);
    final events = const EventPipeline().build(PipelineInputs(settings: denver, now: when, rareEvents: rare));
    expect(events.where((e) => e.type == SkyEventType.comet).first.id, 'comet:comet-c2020f3:20200720');
    final off = const EventPipeline()
        .build(PipelineInputs(settings: denver.copyWith(rareEventsEnabled: false), now: when, rareEvents: rare));
    expect(off.where((e) => e.type == SkyEventType.comet || e.type == SkyEventType.nova), isEmpty);
  });

  test('the full Moon rising is in the week, with clouds at moonrise, and its switch removes it', () {
    // Nashville, full Moon 24 Nov 2026 14:53Z: it rises that evening.
    final now = DateTime.utc(2026, 11, 20, 12);
    // Cloudy only around the evening it rises: the gate must see that hour.
    final clouds = CloudForecast(latitude: 36.17, longitude: -86.78, fetchedAt: now, hourly: [
      for (var h = 0; h < 24 * 7; h++)
        CloudSample(
          time: now.add(Duration(hours: h)),
          coverPercent: now.add(Duration(hours: h)).isAfter(DateTime.utc(2026, 11, 24, 19)) &&
                  now.add(Duration(hours: h)).isBefore(DateTime.utc(2026, 11, 25, 1))
              ? 80
              : 10,
        ),
    ]);
    final events = const EventPipeline().build(PipelineInputs(settings: nashville, now: now, clouds: clouds));
    final moon = events.where((e) => e.type == SkyEventType.fullMoonRise).toList();
    expect(moon.map((e) => e.id), ['fullmoon:2026-11-24']);
    expect(moon.single.start.day, 24);
    expect(moon.single.cloudCoverPercent, 80);
    final off = const EventPipeline().build(PipelineInputs(settings: nashville.copyWith(moonriseEnabled: false), now: now));
    expect(off.where((e) => e.type == SkyEventType.fullMoonRise), isEmpty);
  });

  test('aurora now is skipped in daylight and when Kp is low', () {
    final events = const EventPipeline().build(PipelineInputs(
      settings: nashville,
      now: DateTime.utc(2026, 10, 21, 18), // 1pm CDT
      aurora: AuroraSnapshot(fetchedAt: now, kpNow: 9, forecast: const [], ovationProbability: 80),
    ));
    expect(events.where((e) => e.type == SkyEventType.auroraNow), isEmpty);
    final low = const EventPipeline().build(PipelineInputs(
      settings: nashville,
      now: DateTime.utc(2026, 10, 22, 4),
      aurora: AuroraSnapshot(fetchedAt: now, kpNow: 3, forecast: const [], ovationProbability: 80),
    ));
    expect(low.where((e) => e.type == SkyEventType.auroraNow), isEmpty);
  });

  group('Seen near you', () {
    // Edinburgh at night; Kp 3.5: a little short of the 4 needed there, and
    // Ovation says no, so the model alone stays quiet.
    const edinburgh = LookUpSettings(latitude: 55.95, longitude: -3.19, isPlus: true, seenNearby: true);
    final night = DateTime.utc(2026, 11, 2, 22);
    final snap = AuroraSnapshot(fetchedAt: night, kpNow: 3.5, forecast: const [], ovationProbability: 5);
    // Kp 4.5 and Ovation 40%: the model says go there by itself.
    final go = AuroraSnapshot(fetchedAt: night, kpNow: 4.5, forecast: const [], ovationProbability: 40);
    AuroraReport r(String who, double lat, double lon) {
      final c = reportCell(lat, lon);
      return AuroraReport(cellLat: c.lat, cellLon: c.lon, at: night.subtract(const Duration(minutes: 3)), how: SeenHow.eye, reporter: who);
    }

    final crowd = [r('a', 55.86, -4.25), r('b', 56.40, -3.43), r('c', 55.60, -2.73), r('d', 56.12, -3.16)];
    List<SkyEvent> build(LookUpSettings s, List<AuroraReport> reports, {AuroraSnapshot? aurora}) => const EventPipeline()
        .build(PipelineInputs(settings: s, now: night, aurora: aurora ?? snap, auroraReports: reports))
        .where((e) => e.type == SkyEventType.auroraNow)
        .toList();

    test('people nearby say where an aurora the model calls is being seen', () {
      final plain = build(edinburgh, const [], aurora: go).single;
      expect(plain.details['crowd'], isNull);
      final e = build(edinburgh, crowd, aurora: go).single;
      expect(e.details['crowd'], isTrue);
      expect(e.details['people'], 4);
      expect(e.details['headline'], startsWith('Aurora being seen'));
      expect(e.id, plain.id, reason: 'same 3-hour id: one aurora-now alert, whoever confirmed it');
    });

    test('but never raise one the model calls a little short: anyone can post a report', () {
      expect(build(edinburgh, const []), isEmpty);
      expect(build(edinburgh, crowd), isEmpty, reason: 'Kp 3.5 and Ovation 5%: the model alone stays quiet, so the crowd does too');
      final shortKp = AuroraSnapshot(fetchedAt: night, kpNow: 2.7, forecast: const [], ovationProbability: 40);
      expect(build(edinburgh, crowd, aurora: shortKp), isEmpty, reason: 'Kp within 1.5 of what\'s needed is no longer enough');
    });

    test('nothing without the switch, the aurora toggle, or the model\'s agreement', () {
      expect(build(edinburgh.copyWith(seenNearby: false), crowd), isEmpty);
      expect(build(edinburgh.copyWith(auroraEnabled: false), crowd), isEmpty);
      final quiet = const EventPipeline().build(PipelineInputs(
          settings: edinburgh,
          now: night,
          aurora: AuroraSnapshot(fetchedAt: night, kpNow: 1, forecast: const [], ovationProbability: 0),
          auroraReports: crowd));
      expect(quiet.where((e) => e.type == SkyEventType.auroraNow), isEmpty);
    });
  });

  test('Open-Meteo payload parses to a forecast with nearest-hour lookup', () {
    final f = OpenMeteoClient.parseCloudForecast({
      'hourly': {
        'time': [1760918400, 1760922000, 1760925600],
        'cloud_cover': [10, 55, 90],
      },
    }, latitude: 1, longitude: 2, fetchedAt: now);
    expect(f.hourly.length, 3);
    final t0 = DateTime.fromMillisecondsSinceEpoch(1760918400 * 1000, isUtc: true);
    expect(f.coverAt(t0), 10);
    expect(f.coverAt(t0.add(const Duration(minutes: 50))), 55);
    expect(f.coverAt(t0.add(const Duration(hours: 5))), isNull);
    final rt = f.toJson();
    expect(rt['hourly'], hasLength(3));
  });

  test('aurora snapshot round-trips', () {
    final a = AuroraSnapshot(
        fetchedAt: now,
        kpNow: 4.33,
        ovationProbability: 12,
        forecast: [KpForecastPoint(time: now, kp: 5, kind: 'predicted')]);
    final rt = AuroraSnapshot.fromJson(a.toJson());
    expect(rt.kpNow, 4.33);
    expect(rt.ovationProbability, 12);
    expect(rt.forecast.single.kp, 5);
  });

  group('quiet weeks', () {
    // The week after the fixture epoch has no visible ISS pass over
    // Nashville (see pass_predictor_test), the classic "nothing up" case.
    final quietNow = DateTime.utc(2026, 10, 20, 16);
    const free = LookUpSettings(latitude: 36.17, longitude: -86.78);

    test('an empty week looks ahead for the next ISS pass', () {
      final events = const EventPipeline().build(PipelineInputs(settings: free, now: quietNow, iss: iss));
      final issEvents = events.where((e) => e.type == SkyEventType.iss).toList();
      expect(issEvents, hasLength(1));
      final next = issEvents.single;
      expect(next.details['lookahead'], isTrue);
      expect(next.start.isAfter(quietNow.add(const Duration(days: 7))), isTrue);
      expect(next.start.isBefore(quietNow.add(const Duration(days: 30))), isTrue);
      expect(next.peakElevationDeg, greaterThanOrEqualTo(free.minIssPeakElevationDeg));
    });

    test('no lookahead when the horizon already has a pass', () {
      final events = const EventPipeline(horizon: Duration(days: 21)).build(PipelineInputs(settings: free, now: quietNow, iss: iss));
      expect(events.where((e) => e.type == SkyEventType.iss), isNotEmpty);
      expect(events.any((e) => e.details['lookahead'] == true), isFalse);
    });

    test('no lookahead when ISS alerts are off', () {
      final events = const EventPipeline().build(
          PipelineInputs(settings: free.copyWith(issEnabled: false), now: quietNow, iss: iss));
      expect(events.where((e) => e.type == SkyEventType.iss), isEmpty);
    });
  });

  group('last 7 nights', () {
    // Nov 5: the 7 days before include the Nov 2 near-overhead dawn pass.
    final later = DateTime.utc(2026, 11, 5, 16);
    const nash = LookUpSettings(latitude: 36.17, longitude: -86.78);

    test('past ISS passes, newest first, inside the window, with clouds', () {
      final clouds = CloudForecast(
        latitude: 36.17,
        longitude: -86.78,
        fetchedAt: later,
        hourly: [
          for (var h = -24 * 8; h < 0; h++)
            CloudSample(time: later.add(Duration(hours: h)), coverPercent: 15),
        ],
      );
      final recent = const EventPipeline().buildRecent(
          PipelineInputs(settings: nash, now: later, iss: iss, clouds: clouds));
      expect(recent, isNotEmpty);
      for (final e in recent) {
        expect(e.details['past'], isTrue);
        expect(e.start.isBefore(later), isTrue);
        expect(e.start.isAfter(later.subtract(const Duration(days: 7))), isTrue);
        expect(e.cloudCoverPercent, 15);
      }
      for (var k = 1; k < recent.length; k++) {
        expect(recent[k].start.isAfter(recent[k - 1].start), isFalse);
      }
      expect(recent.any((e) => e.peak.difference(DateTime.utc(2026, 11, 2, 10, 59)).abs() < const Duration(minutes: 5)), isTrue);
    });

    test('aurora nights only when observed Kp met the bar in the dark', () {
      final mpls = const LookUpSettings(latitude: 44.98, longitude: -93.27);
      // 06Z = 1am CDT (dark). 18Z = 1pm (daylight).
      final forecast = [
        KpForecastPoint(time: DateTime.utc(2026, 11, 3, 6), kp: 7.33, kind: 'observed'),
        KpForecastPoint(time: DateTime.utc(2026, 11, 3, 18), kp: 8.0, kind: 'observed'),
        KpForecastPoint(time: DateTime.utc(2026, 11, 4, 6), kp: 2.0, kind: 'observed'),
        KpForecastPoint(time: DateTime.utc(2026, 11, 6, 6), kp: 9.0, kind: 'predicted'),
      ];
      final recent = const EventPipeline().buildRecent(PipelineInputs(
        settings: mpls,
        now: later,
        aurora: AuroraSnapshot(fetchedAt: later, kpNow: 1, forecast: forecast, ovationProbability: 0),
      ));
      final aurora = recent.where((e) => e.type == SkyEventType.auroraNow).toList();
      expect(aurora, hasLength(1));
      expect(aurora.single.details['kp'], 7.33);
      expect(aurora.single.details['past'], isTrue);
    });

    test('nothing without a location', () {
      expect(const EventPipeline().buildRecent(PipelineInputs(settings: const LookUpSettings(), now: later, iss: iss)), isEmpty);
    });
  });
}
