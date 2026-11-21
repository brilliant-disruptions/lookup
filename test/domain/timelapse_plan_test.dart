import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/pointing.dart';
import 'package:lookup/domain/photo/camera.dart';
import 'package:lookup/domain/photo/framing.dart';
import 'package:lookup/domain/photo/timelapse_plan.dart';

void main() {
  final now = DateTime.utc(2026, 10, 20, 23);

  group('when it records', () {
    test('an event: from just before it starts to just after it ends', () {
      final w = timelapseWindow(now: now, eventStart: now.add(const Duration(minutes: 20)), eventEnd: now.add(const Duration(minutes: 26)))!;
      expect(w.start, now.add(const Duration(minutes: 19, seconds: 30)));
      expect(w.end, now.add(const Duration(minutes: 26, seconds: 30)));
    });

    test('an event already going: from now; one that is over: nothing', () {
      final going = timelapseWindow(now: now, eventStart: now.subtract(const Duration(minutes: 2)), eventEnd: now.add(const Duration(minutes: 3)))!;
      expect(going.start, now);
      expect(timelapseWindow(now: now, eventStart: now.subtract(const Duration(hours: 1)), eventEnd: now.subtract(const Duration(minutes: 50))),
          isNull);
    });

    // Rises at 01:00, highest at 04:00, sets at 07:00.
    double rising(DateTime t) => 40 * math.sin((t.difference(DateTime.utc(2026, 10, 21, 1)).inMinutes / 360) * math.pi);

    test('something rising: starts once it is clear of the trees, stops when it sinks back', () {
      final w = timelapseWindow(now: now, altitudeAt: rising, maxLength: const Duration(hours: 8))!;
      expect(w.start.isAfter(DateTime.utc(2026, 10, 21, 1)), isTrue, reason: 'after it rises');
      expect(rising(w.start), greaterThanOrEqualTo(timelapseMinAltitudeDeg));
      expect(rising(w.start.subtract(const Duration(minutes: 2))), lessThan(timelapseMinAltitudeDeg));
      expect(rising(w.end), lessThan(timelapseMinAltitudeDeg));
      expect(w.end.isBefore(DateTime.utc(2026, 10, 21, 7)), isTrue);
    });

    test('the night ending, or the longest run, stops it first', () {
      final dawn = DateTime.utc(2026, 10, 21, 5);
      expect(timelapseWindow(now: now, altitudeAt: rising, nightEnd: dawn, maxLength: const Duration(hours: 8))!.end, dawn);
      final w = timelapseWindow(now: now, altitudeAt: rising, maxLength: const Duration(hours: 2))!;
      expect(w.end.difference(w.start), const Duration(hours: 2));
    });

    test('already up: from now; never up today: nothing', () {
      expect(timelapseWindow(now: now, altitudeAt: (_) => 30)!.start, now);
      expect(timelapseWindow(now: now, altitudeAt: (_) => -10), isNull);
    });
  });

  group('the plan', () {
    test('a three-hour window makes a clip of about 15 s', () {
      final p = planTimelapse(start: now, end: now.add(const Duration(hours: 3)), shutterS: 1);
      expect(p.interval, const Duration(seconds: 24));
      expect(p.clipSeconds, closeTo(15, 0.5));
      expect(p.speedUp, 720);
    });

    test('a short pass: a frame as often as the camera can, not faster', () {
      final p = planTimelapse(start: now, end: now.add(const Duration(minutes: 6)), shutterS: 1);
      expect(p.interval, const Duration(milliseconds: 1500), reason: 'the shutter plus a moment');
      final fast = planTimelapse(start: now, end: now.add(const Duration(minutes: 6)), shutterS: 1 / 100);
      expect(fast.interval, const Duration(seconds: 1), reason: 'never more than one a second');
    });

    test('a whole night: never sparser than a frame a minute', () {
      final p = planTimelapse(start: now, end: now.add(const Duration(hours: 12)), shutterS: 1);
      expect(p.interval, const Duration(seconds: 60));
    });

    test('framed along the path it takes, with a lens that fits it', () {
      final path = <PathPoint>[
        for (var i = 0; i <= 12; i++) (t: now.add(Duration(minutes: i * 15)), d: SkyDir(100 + i * 4.0, 10 + i * 2.0)),
      ];
      const lenses = [
        CameraLens(id: 'main', kind: LensKind.wide, longFovDeg: 66, shortFovDeg: 52),
        CameraLens(id: 'ultra', kind: LensKind.ultraWide, longFovDeg: 106, shortFovDeg: 86, fNumber: 2.2),
      ];
      final p = planTimelapse(start: now, end: now.add(const Duration(hours: 3)), shutterS: 1, path: path, lenses: lenses);
      expect(p.framing, isNotNull);
      for (final pt in path) {
        expect(p.framing!.contains(pt.d), isTrue, reason: '${pt.d}');
      }
    });
  });

  group('running it', () {
    final p = planTimelapse(start: now.add(const Duration(minutes: 10)), end: now.add(const Duration(minutes: 40)), shutterS: 1);

    test('waits, records by itself, then stops by itself', () {
      expect(timelapseStage(now, p), TimelapseStage.waiting);
      expect(timelapseStage(now.add(const Duration(minutes: 10)), p), TimelapseStage.recording);
      expect(timelapseStage(now.add(const Duration(minutes: 40)), p), TimelapseStage.done);
    });

    test('you can start it early, or stop it whenever you like', () {
      final early = now.add(const Duration(minutes: 2));
      expect(timelapseStage(now.add(const Duration(minutes: 3)), p, startedEarly: early), TimelapseStage.recording);
      final stopped = now.add(const Duration(minutes: 15));
      expect(timelapseStage(now.add(const Duration(minutes: 16)), p, stoppedAt: stopped), TimelapseStage.done);
    });

    test('one frame kept per interval, tolerant of a camera a hair early', () {
      final i = p.interval;
      expect(keepTimelapseFrame(now, null, i), isTrue);
      expect(keepTimelapseFrame(now.add(i ~/ 2), now, i), isFalse);
      expect(keepTimelapseFrame(now.add(i - const Duration(milliseconds: 50)), now, i), isTrue);
    });
  });
}
