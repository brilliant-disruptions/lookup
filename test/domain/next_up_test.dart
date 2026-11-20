import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/plan/next_up.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20, 20);
  SkyEvent ev(String id, SkyEventType type, int startMin, int lengthMin) => SkyEvent(
        id: id,
        type: type,
        start: now.add(Duration(minutes: startMin)),
        peak: now.add(Duration(minutes: startMin + 1)),
        end: now.add(Duration(minutes: startMin + lengthMin)),
        peakElevationDeg: 50,
        riseAzimuthDeg: 250,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 90,
      );

  test('the soonest alert-worthy sight still to come', () {
    final e = nextUp([ev('later', SkyEventType.iss, 90, 5), ev('soon', SkyEventType.tiangong, 30, 5)], now);
    expect(e?.id, 'soon');
  });

  test('one going over now counts; one already over does not', () {
    expect(nextUp([ev('over', SkyEventType.iss, -10, 5), ev('now', SkyEventType.iss, -2, 5)], now)?.id, 'now');
  });

  test('never counts down to something LookUp would not tap you for', () {
    expect(nextUp([ev('transit', SkyEventType.issTransit, 5, 1), ev('iss', SkyEventType.iss, 60, 5)], now)?.id, 'iss');
    expect(nextUp([ev('transit', SkyEventType.issTransit, 5, 1)], now), isNull);
  });
}
