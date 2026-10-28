import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/widget_service.dart';

void main() {
  test('widget payload: next event or a quiet sky', () {
    expect(WidgetService.payloadFor(null)['next_title'], 'A quiet sky');
    final start = DateTime.utc(2026, 10, 26, 0, 42);
    final e = SkyEvent(
      id: 'iss:w',
      type: SkyEventType.iss,
      start: start,
      peak: start.add(const Duration(minutes: 2)),
      end: start.add(const Duration(minutes: 4)),
      peakElevationDeg: 62,
      riseAzimuthDeg: 247,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 95,
    );
    final p = WidgetService.payloadFor(e);
    expect(p['next_title'], 'ISS flyover');
    expect(p['next_direction'], 'Look west-southwest, high in the sky');
    expect(p['next_start_ms'], start.millisecondsSinceEpoch);
  });

  test('without LookUp+ the widget says what it is instead of the next event', () {
    final p = WidgetService.payloadFor(null, isPlus: false);
    expect(p['next_when'], 'The widget is part of LookUp+');
    expect(p['next_start_ms'], 0);
  });
}
