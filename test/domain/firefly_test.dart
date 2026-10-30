import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/firefly.dart';
import 'package:lookup/domain/finder/pointing.dart';

void main() {
  test('sits on the target when it is on screen', () {
    final g = fireflyGoal(width: 400, height: 800, target: (x: 50, y: -120), toward: (x: 1, y: 0));
    expect((g.x, g.y, g.waiting), (50.0, -120.0, false));
  });

  test('waits at the edge on the side to turn', () {
    // Far to the right and a little up: parked on the right edge.
    final right = fireflyGoal(width: 400, height: 800, target: (x: 900, y: -100), toward: (x: 1, y: 0));
    expect(right.waiting, isTrue);
    expect(right.x, closeTo(170, 1e-9)); // 400/2 − 30
    expect(right.y, lessThan(0));
    // Behind you: it follows "which way to turn".
    final behind = fireflyGoal(width: 400, height: 800, target: null, toward: (x: -120, y: 0));
    expect(behind.waiting, isTrue);
    expect(behind.x, closeTo(-170, 1e-9));
    expect(behind.y, 0);
    // Straight up: the top edge.
    final up = fireflyGoal(width: 400, height: 800, target: null, toward: (x: 0, y: -40));
    expect(up.y, closeTo(-370, 1e-9));
  });

  test('which way to turn reads like the words', () {
    final g = guide(const SkyDir(90, 10), const SkyDir(120, 40));
    final t = towardOnScreen(g);
    expect(t.x, greaterThan(0)); // turn right
    expect(t.y, lessThan(0)); // tilt up
  });

  test('flies there on a spring without overshooting', () {
    final m = FireflyMotion();
    var maxX = 0.0;
    for (var i = 0; i < 60; i++) {
      m.step((x: 100, y: -50), 1 / 60);
      if (m.x > maxX) maxX = m.x;
    }
    expect(m.x, closeTo(100, 2));
    expect(m.y, closeTo(-50, 1));
    expect(maxX, lessThanOrEqualTo(100.5));
    // A long frame (the app was paused) doesn't fling it.
    m.step((x: -100, y: 0), 3);
    expect(m.x.abs(), lessThan(150));
  });

  test('blinks faster as you close in, and glows steady on target', () {
    final far = fireflyBlink(80)!, mid = fireflyBlink(25)!, near = fireflyBlink(10)!;
    expect(far, greaterThan(mid));
    expect(mid, greaterThan(near));
    expect(fireflyBlink(5), isNull);
  });

  test('the ghost run flies rise to set once, eased, then stops', () {
    expect(ghostProgress(Duration.zero), 0);
    expect(ghostProgress(ghostRunLength ~/ 2), closeTo(0.5, 1e-9));
    expect(ghostProgress(ghostRunLength), isNull);
    expect(ghostProgress(const Duration(milliseconds: -1)), isNull);
    var last = -1.0;
    for (var ms = 0; ms < ghostRunLength.inMilliseconds; ms += 100) {
      final f = ghostProgress(Duration(milliseconds: ms))!;
      expect(f, greaterThanOrEqualTo(last));
      last = f;
    }
  });

  test('along the route, the short way round through north', () {
    const route = [SkyDir(340, 10), SkyDir(20, 50), SkyDir(60, 10)];
    expect(alongRoute(route, 0).azimuthDeg, 340);
    expect(alongRoute(route, 1).azimuthDeg, 60);
    final quarter = alongRoute(route, 0.25);
    expect(quarter.azimuthDeg, closeTo(0, 1e-9));
    expect(quarter.elevationDeg, closeTo(30, 1e-9));
  });

  test('ghost run, then the landmark, then the spot by it; once it is up, only the thing itself', () {
    FireflyStep step({bool before = true, bool ghost = false, bool lm = true, bool found = false, bool skipped = false}) =>
        fireflyStep(beforePass: before, ghostRunning: ghost, hasLandmark: lm, landmarkFound: found, skipped: skipped);
    expect(step(ghost: true), FireflyStep.ghostRun);
    expect(step(), FireflyStep.findLandmark);
    expect(step(found: true), FireflyStep.meetingPoint);
    expect(step(skipped: true), FireflyStep.target);
    expect(step(lm: false), FireflyStep.target);
    expect(step(before: false, ghost: true), FireflyStep.target);
    expect(step(before: false), FireflyStep.target);
  });
}
