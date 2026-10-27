import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/ui/sky/sky_panorama.dart';
import 'package:lookup/ui/sky/sky_track.dart';
import 'package:lookup/ui/theme.dart';

final start = DateTime.utc(2026, 10, 28, 9, 57);

SkyEvent pass(
  String id, {
  SkyEventType type = SkyEventType.iss,
  Duration from = Duration.zero,
  double rise = 247,
  double peak = 180,
  double set = 95,
}) => SkyEvent(
  id: id,
  type: type,
  start: start.add(from),
  peak: start.add(from + const Duration(minutes: 2)),
  end: start.add(from + const Duration(minutes: 4)),
  peakElevationDeg: 62,
  riseAzimuthDeg: rise,
  peakAzimuthDeg: peak,
  setAzimuthDeg: set,
);

void main() {
  test('without orbit data the track arcs from rise, through the peak, to set', () {
    final tr = passTrack(pass('a'), 36.17, -86.78);
    expect(tr.points.first.h.azimuthDeg, closeTo(247, 0.01));
    expect(tr.points.first.h.altitudeDeg, closeTo(0, 0.01));
    expect(tr.points.last.h.azimuthDeg, closeTo(95, 0.01));
    expect(tr.points.last.h.altitudeDeg, closeTo(0, 0.01));
    final top = tr.points.reduce((a, b) => a.h.altitudeDeg > b.h.altitudeDeg ? a : b);
    expect(top.h.altitudeDeg, closeTo(62, 0.01));
    expect(top.t, start.add(const Duration(minutes: 2)));
  });

  test('where it is now: null outside the pass, in between during it', () {
    final tr = passTrack(pass('a'), 36.17, -86.78);
    expect(tr.at(start.subtract(const Duration(seconds: 1))), isNull);
    expect(tr.at(start.add(const Duration(minutes: 5))), isNull);
    final mid = tr.at(start.add(const Duration(minutes: 2)))!;
    expect(mid.altitudeDeg, closeTo(62, 0.5));
    expect(mid.azimuthDeg, closeTo(180, 1));
  });

  test('a pass across north turns the short way round', () {
    final tr = passTrack(pass('n', rise: 330, peak: 0, set: 30), 36.17, -86.78);
    for (final p in tr.points) {
      expect(p.h.azimuthDeg < 31 || p.h.azimuthDeg > 329, isTrue, reason: '${p.h.azimuthDeg}');
    }
  });

  test('only passes that move, soon, and a few at most', () {
    final events = [
      pass('live', from: const Duration(minutes: -1)),
      SkyEvent(
        id: 'aurora',
        type: SkyEventType.auroraOutlook,
        start: start,
        peak: start,
        end: start.add(const Duration(hours: 6)),
        peakElevationDeg: 15,
        riseAzimuthDeg: 0,
        peakAzimuthDeg: 0,
        setAzimuthDeg: 0,
      ),
      pass('soon', type: SkyEventType.starlinkTrain, from: const Duration(hours: 2)),
      pass('tomorrow', from: const Duration(hours: 20)),
      pass('gone', from: const Duration(hours: -2)),
    ];
    expect(upcomingPasses(events, start).map((e) => e.id), ['live', 'soon']);
    expect(upcomingPasses(events, start, max: 1).map((e) => e.id), ['live']);
  });

  testWidgets('tapping a pass on the panorama opens it', (t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final opened = <SkyEvent>[];
    final tr = passTrack(pass('a'), 36.17, -86.78);
    await t.pumpWidget(
      MaterialApp(
        theme: buildLookUpTheme(),
        home: Scaffold(
          body: SkyPanorama(
            time: start.add(const Duration(minutes: 2)),
            lat: 36.17,
            lon: -86.78,
            catalog: SkyCatalog.empty,
            things: const [],
            tracks: [tr],
            onTrackTap: opened.add,
          ),
        ),
      ),
    );
    // Mid-pass it opens facing the station, which is at the top of its arc.
    expect(find.text('Facing south'), findsOneWidget);
    final box = t.getRect(find.byKey(SkyPanorama.canvasKey));
    final horizon = box.height - 64;
    await t.tapAt(Offset(box.center.dx, box.top + horizon - 62 / 90 * (horizon - 18)));
    expect(opened.map((e) => e.id), ['a']);
  });
}
