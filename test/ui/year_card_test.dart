import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/year_review.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/ui/year_card.dart';

void main() {
  testWidgets('the shared year card speaks in words: no magnitudes, no degrees', (t) async {
    final at = DateTime.utc(2026, 10, 20, 1);
    final r = YearReview.from([
      Sighting(eventId: 'iss:a', seen: true, at: at, type: SkyEventType.iss, eventTime: at, peakElevationDeg: 81, magnitude: -3.7),
      Sighting(eventId: 'iss:b', seen: true, at: at.add(const Duration(days: 3)), type: SkyEventType.iss,
          eventTime: at.add(const Duration(days: 3)), peakElevationDeg: 40, magnitude: -2.1),
    ], 2026, utcOffsetMinutes: 0)!;
    // The test font draws every letter as a wide block: give it room.
    t.view.physicalSize = const Size(2400, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 1400, child: YearCard(r))))));
    expect(find.text('Brightest: as bright as Venus'), findsOneWidget);
    expect(find.text('Highest pass: straight overhead'), findsOneWidget);
    expect(find.text('2 ISS passes'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(find.textContaining('magnitude'), findsNothing);
  });
}
