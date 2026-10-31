import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/tonight_verdict.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/domain/weather/cloud_forecast.dart';

final now = DateTime.utc(2026, 11, 6, 22); // 4 pm in Nashville
final tonightEnds = DateTime.utc(2026, 11, 7, 11, 30); // dawn

SkyEvent ev(String id, Duration fromNow, {int? clouds, SkyEventType type = SkyEventType.iss, Map<String, Object?> details = const {}}) =>
    SkyEvent(
      id: id,
      type: type,
      start: now.add(fromNow),
      peak: now.add(fromNow + const Duration(minutes: 2)),
      end: now.add(fromNow + const Duration(minutes: 4)),
      peakElevationDeg: 60,
      riseAzimuthDeg: 247,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 95,
      cloudCoverPercent: clouds,
      details: details,
    );

NightOutlook outlook(List<int> covers) {
  final start = DateTime.utc(2026, 11, 7, 0);
  return NightOutlook.from(
    start: start,
    end: start.add(Duration(hours: covers.length)),
    weather: CloudForecast(
      latitude: 36.17,
      longitude: -86.78,
      fetchedAt: now,
      hourly: [
        for (final (i, c) in covers.indexed)
          CloudSample(
            time: start.add(Duration(hours: i)),
            coverPercent: c,
          ),
      ],
    ),
  );
}

TonightVerdict decide(List<SkyEvent> events, {NightOutlook? o, bool planetUp = false, DateTime? at}) =>
    TonightVerdict.decide(events: events, now: at ?? now, tonightEnds: tonightEnds, outlook: o, planetUp: planetUp);

void main() {
  group('something tonight', () {
    test('clear: go, for the soonest thing', () {
      final v = decide([ev('iss:2', const Duration(hours: 9), clouds: 5), ev('iss:1', const Duration(hours: 6), clouds: 10)]);
      expect(v.kind, VerdictKind.go);
      expect(v.event?.id, 'iss:1');
    });

    test('no forecast reaching it yet is still a go', () {
      expect(decide([ev('iss:1', const Duration(hours: 6))]).kind, VerdictKind.go);
    });

    test('some cloud: worth a look, never a go', () {
      for (final c in [41, 55, 70]) {
        expect(decide([ev('iss:1', const Duration(hours: 6), clouds: c)]).kind, VerdictKind.maybe, reason: '$c%');
      }
    });

    test('heavy cloud: stay in, saying what is missed and the next clear thing', () {
      final v = decide([
        ev('iss:1', const Duration(hours: 6), clouds: 90),
        ev('iss:2', const Duration(days: 1, hours: 6), clouds: 80), // also cloudy
        ev('iss:3', const Duration(days: 2, hours: 6), clouds: 15),
      ]);
      expect(v.kind, VerdictKind.stayIn);
      expect(v.cloudedOut, isTrue);
      expect(v.event?.id, 'iss:1');
      expect(v.nextGood?.id, 'iss:3');
    });

    test('heavy cloud wins even while it is up', () {
      final live = ev('iss:1', const Duration(minutes: -1), clouds: 95);
      expect(decide([live]).kind, VerdictKind.stayIn);
    });

    test('up right now and clear enough: live', () {
      expect(decide([ev('iss:1', const Duration(minutes: -1), clouds: 20)]).kind, VerdictKind.live);
    });
  });

  group('nothing tonight', () {
    final thursday = ev('iss:thu', const Duration(days: 2, hours: 5), clouds: 10);

    test('a clear night with a planet up', () {
      final v = decide([thursday], o: outlook([5, 5, 10, 5]), planetUp: true);
      expect(v.kind, VerdictKind.clearNight);
      expect(v.nextGood?.id, 'iss:thu');
    });

    test('clear but nothing bright: quiet, pointing at the next good night', () {
      final v = decide([thursday], o: outlook([5, 5, 10, 5]));
      expect(v.kind, VerdictKind.quiet);
      expect(v.nextGood?.id, 'iss:thu');
    });

    test('cloudy all night: stay in, even with a planet up', () {
      final v = decide([thursday], o: outlook([90, 95, 85, 90]), planetUp: true);
      expect(v.kind, VerdictKind.stayIn);
      expect(v.cloudedOut, isTrue);
    });

    test('no forecast and nothing up: quiet', () {
      expect(decide(const []).kind, VerdictKind.quiet);
    });
  });

  test('never about things LookUp does not push, past records or what is over', () {
    final v = decide([
      ev('transit:1', const Duration(hours: 5), type: SkyEventType.issTransit, clouds: 0),
      ev('outlook:1', const Duration(hours: 5), type: SkyEventType.auroraOutlook, clouds: 0),
      ev('iss:past', const Duration(hours: 5), clouds: 0, details: {'past': true}),
      ev('iss:over', const Duration(hours: -2), clouds: 0),
    ]);
    expect(v.kind, VerdictKind.quiet);
    expect(v.event, isNull);
  });
}
