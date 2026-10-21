import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/data/open_meteo_client.dart';
import 'package:lookup/domain/aurora/aurora_rules.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
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
}
