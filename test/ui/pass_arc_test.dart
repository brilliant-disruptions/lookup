import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/widgets/pass_arc.dart';

void main() {
  final start = DateTime.utc(2026, 10, 28, 9, 57);
  final pass = SkyEvent(
    id: 'iss:t',
    type: SkyEventType.iss,
    start: start,
    peak: start.add(const Duration(minutes: 2)),
    end: start.add(const Duration(minutes: 4)),
    peakElevationDeg: 62,
    riseAzimuthDeg: 247,
    peakAzimuthDeg: 180,
    setAzimuthDeg: 95,
  );

  test('progress runs from rise to set, and is null before', () {
    expect(passProgress(pass, start.subtract(const Duration(minutes: 1))), isNull);
    expect(passProgress(pass, start), 0);
    expect(passProgress(pass, start.add(const Duration(minutes: 2))), closeTo(0.5, 1e-9));
    expect(passProgress(pass, start.add(const Duration(minutes: 9))), 1);
  });

  Future<void> pump(WidgetTester t, DateTime now) => t.pumpWidget(MaterialApp(
        theme: buildLookUpTheme(),
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: LivePassArc(event: pass, now: now))),
      ));

  testWidgets('labels ends and peak in words, no degrees', (t) async {
    await pump(t, start.subtract(const Duration(hours: 3)));
    expect(find.text('WSW'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
    expect(find.text('High in the sky'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(
        find.bySemanticsLabel(RegExp(r'^Rises in the west-southwest at .*, climbs high in the sky, sets in the east at ')),
        findsOneWidget);
  });

  testWidgets('before the pass the preview runs once, then rests', (t) async {
    await pump(t, start.subtract(const Duration(hours: 3)));
    await t.pump(); // post-frame start
    expect(t.hasRunningAnimations, isTrue); // drawing in
    await t.pump(const Duration(milliseconds: 1200));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.hasRunningAnimations, isTrue); // the light running the route
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 3));
    expect(t.hasRunningAnimations, isFalse); // and it doesn't loop
  });

  testWidgets('during the pass it only draws itself in (the dot follows the clock)', (t) async {
    await pump(t, start.add(const Duration(minutes: 1)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 1200));
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('names what it goes by beside the route, and says so', (t) async {
    final withMarks = pass.copyWith(details: {
      'landmarks': 'passing right by Jupiter, then close to Vega',
      'landmarkPoints': [
        {'name': 'Jupiter', 'f': 0.3, 'above': true, 'close': true},
        {'name': 'Vega', 'f': 0.8, 'above': false, 'close': false},
      ],
    });
    await t.pumpWidget(MaterialApp(
      theme: buildLookUpTheme(),
      home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: LivePassArc(event: withMarks, now: start.subtract(const Duration(hours: 3))))),
    ));
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Jupiter', skipOffstage: false), findsOneWidget);
    expect(find.text('Vega', skipOffstage: false), findsOneWidget);
    // Jupiter labels to the right of its dot, Vega (late in the pass) to the left.
    expect(t.getTopLeft(find.text('Jupiter')).dx, lessThan(t.getTopLeft(find.text('Vega')).dx));
    expect(find.bySemanticsLabel(RegExp(r'passing right by Jupiter, then close to Vega\.$')), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
