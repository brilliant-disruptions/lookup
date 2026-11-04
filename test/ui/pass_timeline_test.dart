import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/ui/widgets/pass_timeline.dart';

void main() {
  final pass = SkyEvent(
    id: 'iss:t',
    type: SkyEventType.iss,
    start: DateTime.utc(2026, 11, 3, 0, 5),
    peak: DateTime.utc(2026, 11, 3, 0, 7),
    end: DateTime.utc(2026, 11, 3, 0, 9),
    peakElevationDeg: 64,
    riseAzimuthDeg: 250,
    peakAzimuthDeg: 190,
    setAzimuthDeg: 100,
  );

  Future<void> pump(WidgetTester t, {bool degrees = false}) => t.pumpWidget(MaterialApp(
        home: Scaffold(body: PassTimeline(event: pass, now: pass.peak, degrees: degrees)),
      ));

  testWidgets('while it\'s up, the peak is a word, never a number', (t) async {
    await pump(t);
    expect(find.text('High'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
  });

  testWidgets('behind Details, the degrees', (t) async {
    await pump(t, degrees: true);
    expect(find.text('64°'), findsOneWidget);
  });
}
