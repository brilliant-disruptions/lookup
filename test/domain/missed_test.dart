import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/missed.dart';

SkyEvent _past(String id, SkyEventType type, int? clouds) {
  final t = DateTime.utc(2026, 10, 27, 3);
  return SkyEvent(
    id: id,
    type: type,
    start: t,
    peak: t.add(const Duration(minutes: 2)),
    end: t.add(const Duration(minutes: 5)),
    peakElevationDeg: 50,
    riseAzimuthDeg: 250,
    peakAzimuthDeg: 180,
    setAzimuthDeg: 90,
    cloudCoverPercent: clouds,
    details: const {'past': true},
  );
}

void main() {
  test('only Plus-only sights that were really there to see', () {
    final missed = missedWithoutPlus([
      _past('starlink:clear', SkyEventType.starlinkTrain, 10),
      _past('iss:clear', SkyEventType.iss, 5), // free users got this one
      _past('tiangong:cloudy', SkyEventType.tiangong, 90), // nobody saw it
      _past('tiangong:unknown', SkyEventType.tiangong, null), // can't claim it
      _past('aurora:clear', SkyEventType.auroraNow, 30),
    ]);
    expect(missed.map((e) => e.id), ['starlink:clear', 'aurora:clear']);
  });
}
