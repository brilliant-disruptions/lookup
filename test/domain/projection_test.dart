import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/pointing.dart';

void main() {
  // Upright phone, back camera facing magnetic north (see finder_test).
  const north = [1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0];
  const h = 1000.0, fov = 60.0;
  final f = (h / 2) / math.tan(fov / 2 * math.pi / 180);

  ({double x, double y})? p(double az, double el, {double decl = 0}) =>
      projectToScreen(north, SkyDir(az, el), declinationDeg: decl, previewHeightPx: h, verticalFovDeg: fov);

  test('straight ahead lands in the centre', () {
    final c = p(0, 0)!;
    expect(c.x, closeTo(0, 1e-9));
    expect(c.y, closeTo(0, 1e-9));
  });

  test('east is to the right, up is up, by the pinhole tangent', () {
    final r = p(10, 0)!;
    expect(r.x, closeTo(f * math.tan(10 * math.pi / 180), 1e-6));
    expect(r.y, closeTo(0, 1e-6));
    final u = p(0, 10)!;
    expect(u.y, closeTo(-f * math.tan(10 * math.pi / 180), 1e-6));
  });

  test('declination: true north sits left of magnetic north when it is east', () {
    // Declination +5° (magnetic north is 5° east of true): true north is 5° left.
    expect(p(0, 0, decl: 5)!.x, lessThan(0));
  });

  test('behind the camera is not drawn', () {
    expect(p(180, 0), isNull);
    expect(p(90, 0), isNull);
  });

  test('haptic ticks speed up as you close in and stop on target', () {
    expect(pulseInterval(60), isNull);
    expect(pulseInterval(5), isNull);
    final far = pulseInterval(30)!, near = pulseInterval(10)!;
    expect(near < far, isTrue);
    expect(pulseInterval(35)!.inMilliseconds, 700);
  });
}
