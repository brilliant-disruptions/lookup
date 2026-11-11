import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';

void main() {
  late OmmRecord iss;
  setUpAll(() {
    iss = OmmRecord.listFromJson(
            jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync()))
        .single;
  });

  test('OMM record maps to elements', () {
    expect(iss.noradCatId, Norad.iss);
    expect(iss.epoch, DateTime.utc(2026, 10, 20, 15, 51, 33, 979, 680));
    expect(iss.toElements().epoch, iss.epoch);
    expect(iss.isStale(DateTime.utc(2026, 10, 22)), isFalse);
    expect(iss.isStale(DateTime.utc(2026, 10, 30)), isTrue);
  });

  test('no visible ISS passes over Nashville in the week after epoch', () {
    // Visibility comes in cycles; this particular week has dark passes that
    // are all in shadow and dawn passes that are all after civil twilight.
    final predictor = PassPredictor(latitude: 36.17, longitude: -86.78);
    final from = DateTime.utc(2026, 10, 20, 16);
    expect(
        predictor.predict(
            record: iss,
            type: SkyEventType.iss,
            from: from,
            to: from.add(const Duration(days: 7)),
            minPeakElevationDeg: 10),
        isEmpty);
  });

  test('ISS visible passes over Nashville within three weeks', () {
    final predictor = PassPredictor(latitude: 36.17, longitude: -86.78);
    final from = DateTime.utc(2026, 10, 20, 16);
    final events = predictor.predict(
      record: iss,
      type: SkyEventType.iss,
      from: from,
      to: from.add(const Duration(days: 21)),
      minPeakElevationDeg: 10,
    );
    expect(events, isNotEmpty);
    // The 2026-11-02 ~10:59Z dawn pass peaks near overhead.
    final big = events.where((e) =>
        e.peak.difference(DateTime.utc(2026, 11, 2, 10, 59)).abs() <
        const Duration(minutes: 5));
    expect(big, hasLength(1));
    expect(big.single.peakElevationDeg, greaterThan(70));
    expect(big.single.isEstimate, isTrue, reason: 'elements are 13 days old');
    expect(events.first.isEstimate, isTrue);
    for (final e in events) {
      expect(e.type, SkyEventType.iss);
      expect(e.start.isBefore(e.peak) || e.start == e.peak, isTrue);
      expect(e.end.isAfter(e.start), isTrue);
      expect(e.duration.inSeconds, greaterThanOrEqualTo(60));
      expect(e.duration.inMinutes, lessThanOrEqualTo(12));
      expect(e.peakElevationDeg, greaterThanOrEqualTo(10));
      expect(e.riseAzimuthDeg, inInclusiveRange(0, 360));
      expect(e.id, startsWith('iss:'));
      expect(e.details['brightness'], isA<String>());
      // Visible passes happen within a few hours of dusk or dawn, never at
      // local midday (17–19Z).
      expect(e.peak.hour, isNot(inInclusiveRange(15, 21)));
    }
    // Ids are stable across runs.
    final again = predictor.predict(
      record: iss,
      type: SkyEventType.iss,
      from: from,
      to: from.add(const Duration(days: 21)),
      minPeakElevationDeg: 10,
    );
    expect(again.map((e) => e.id), events.map((e) => e.id));
  });

  test('higher elevation threshold yields a subset', () {
    final predictor = PassPredictor(latitude: 36.17, longitude: -86.78);
    final from = DateTime.utc(2026, 10, 20, 16);
    final to = from.add(const Duration(days: 21));
    final all = predictor.predict(
        record: iss, type: SkyEventType.iss, from: from, to: to,
        minPeakElevationDeg: 10);
    final high = predictor.predict(
        record: iss, type: SkyEventType.iss, from: from, to: to,
        minPeakElevationDeg: 40);
    expect(high.length, lessThanOrEqualTo(all.length));
    expect(high.every((e) => e.peakElevationDeg >= 40), isTrue);
  });

  // STARLINK-5046 in the fixture is re-entering (BSTAR 0.0035): SGP4 gives
  // up on it around 2026-11-18. That threw out of predict and took the whole
  // refresh down with it, alerts included, from 2026-11-11 on.
  test('a re-entering satellite has no passes instead of throwing', () {
    final falling = OmmRecord.listFromJson(jsonDecode(
            File('test/fixtures/starlink_sample.json').readAsStringSync()))
        .singleWhere((r) => r.objectName == 'STARLINK-5046');
    final predictor = PassPredictor(latitude: 40.0, longitude: -75.0);
    List<SkyEvent> over(DateTime from, int days) => predictor.predict(
        record: falling,
        type: SkyEventType.starlinkTrain,
        from: from,
        to: from.add(Duration(days: days)),
        minPeakElevationDeg: 10);
    expect(over(DateTime.utc(2026, 11, 11), 10), isEmpty);
    // Before its decay it still propagates like any other satellite.
    expect(() => over(DateTime.utc(2026, 10, 21), 3), returnsNormally);
  });

  test('cloud forecast is attached when provided', () {
    final predictor = PassPredictor(latitude: 36.17, longitude: -86.78);
    final from = DateTime.utc(2026, 10, 20, 16);
    final clouds = CloudForecast(
      latitude: 36.17,
      longitude: -86.78,
      fetchedAt: from,
      hourly: [
        for (var h = 0; h < 24 * 22; h++)
          CloudSample(time: from.add(Duration(hours: h)), coverPercent: 42),
      ],
    );
    final events = predictor.predict(
        record: iss,
        type: SkyEventType.iss,
        from: from,
        to: from.add(const Duration(days: 21)),
        minPeakElevationDeg: 10,
        clouds: clouds);
    expect(events.every((e) => e.cloudCoverPercent == 42), isTrue);
    expect(events.first.score, closeTo(
        events.first.peakElevationDeg * events.first.duration.inSeconds * 0.58,
        0.01));
    // Round-trips through JSON.
    final rt = SkyEvent.fromJson(events.first.toJson());
    expect(rt.id, events.first.id);
    expect(rt.peak, events.first.peak);
  });
}
