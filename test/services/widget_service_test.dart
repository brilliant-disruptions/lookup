import 'dart:convert';

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
    expect(p['next_tint'], 0xFF5AA2FF); // the station's blue
    expect(p['next_art'], '');
    expect(WidgetService.payloadFor(e, artPath: '/x/widget.png')['next_art'], '/x/widget.png');
    expect(p['next_kicker'], startsWith('Next up · '));
  });

  test('the island and widgets get the pass in words, never degrees', () {
    final start = DateTime.utc(2026, 10, 26, 0, 42);
    SkyEvent ev(String id, SkyEventType t, Duration after, {int? cloud}) => SkyEvent(
          id: id,
          type: t,
          start: start.add(after),
          peak: start.add(after + const Duration(minutes: 2)),
          end: start.add(after + const Duration(minutes: 4)),
          peakElevationDeg: 62,
          riseAzimuthDeg: 247,
          peakAzimuthDeg: 180,
          setAzimuthDeg: 95,
          cloudCoverPercent: cloud,
        );
    final iss = ev('iss:w', SkyEventType.iss, Duration.zero, cloud: 10);
    final later = ev('iss:x', SkyEventType.iss, const Duration(hours: 9));
    final p = WidgetService.payloadFor(iss, upcoming: [iss, later]);
    expect(p['next_end_ms'], iss.end.millisecondsSinceEpoch);
    expect(p['next_rise'], 'WSW');
    expect(p['next_set'], 'E');
    expect(p['next_peak'], 'high');
    expect(p['next_rise_word'], 'west-southwest');
    final rows = (jsonDecode(p['upcoming_json']! as String) as List).cast<Map<String, Object?>>();
    expect(rows, hasLength(2));
    expect(rows.first['title'], 'ISS flyover');
    expect(rows.first['where'], 'from the west-southwest, high');
    expect(rows.first['sky'], 'clear');
    expect(rows.first['end_ms'], iss.end.millisecondsSinceEpoch);
    expect(rows.last['sky'], '', reason: 'no forecast, no word');
    // Words only: no degrees anywhere the widgets read.
    expect(jsonEncode(p), isNot(contains('°')));
    expect(jsonEncode(p), isNot(contains('247')));
    expect(WidgetService.payloadFor(null)['upcoming_json'], '[]');
  });
}
