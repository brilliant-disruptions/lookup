import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/ui/widgets/countdown_ring.dart';

void main() {
  final start = DateTime.utc(2026, 10, 21, 23, 10);
  final e = SkyEvent(
    id: 'iss:x',
    type: SkyEventType.iss,
    start: start,
    peak: start.add(const Duration(minutes: 2)),
    end: start.add(const Duration(minutes: 4)),
    peakElevationDeg: 50,
    riseAzimuthDeg: 0,
    peakAzimuthDeg: 0,
    setAzimuthDeg: 0,
  );

  test('hidden when far off, fills over the last 15 minutes, drains during', () {
    expect(ringProgress(e, start.subtract(const Duration(hours: 1))), isNull);
    expect(ringProgress(e, start.subtract(const Duration(minutes: 15))), closeTo(0, 1e-9));
    expect(ringProgress(e, start.subtract(const Duration(minutes: 5))), closeTo(2 / 3, 1e-9));
    expect(ringProgress(e, start), closeTo(1, 1e-9));
    expect(ringProgress(e, start.add(const Duration(minutes: 1))), closeTo(0.75, 1e-9));
    expect(ringProgress(e, e.end), isNull);
  });
}
