import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/pointing.dart';
import 'package:lookup/domain/sky/brightness.dart';

void main() {
  group('pointing', () {
    // Phone upright in portrait, screen facing the user, back camera facing
    // magnetic north: device x→east, y→up, z→south.
    const uprightNorth = [1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0];

    test('upright phone points at the horizon, north', () {
      final d = cameraDirection(uprightNorth);
      expect(d.elevationDeg, closeTo(0, 1e-9));
      expect(d.azimuthDeg, closeTo(0, 1e-9));
    });

    test('declination shifts magnetic to true azimuth', () {
      expect(cameraDirection(uprightNorth, declinationDeg: 15).azimuthDeg, closeTo(15, 1e-9));
      expect(cameraDirection(uprightNorth, declinationDeg: -4).azimuthDeg, closeTo(356, 1e-9));
    });

    test('flat on a table, face up, the camera looks at the ground', () {
      final d = cameraDirection(const [1.0, 0, 0, 0, 1, 0, 0, 0, 1]);
      expect(d.elevationDeg, closeTo(-90, 1e-9));
    });

    test('facing follows the camera, and the top edge when the phone is flat', () {
      expect(facingAzimuth(uprightNorth), closeTo(0, 1e-9));
      expect(facingAzimuth(uprightNorth, declinationDeg: -4), closeTo(356, 1e-9));
      // Upright, camera east: device x→south, y→up, z→west.
      expect(facingAzimuth(const [0.0, 0, -1, -1, 0, 0, 0, 1, 0]), closeTo(90, 1e-9));
      // Tilted back 45° to look up at the northern sky: still facing north,
      // though the top edge now leans south.
      const s = 0.7071067811865476;
      expect(facingAzimuth(const [1.0, 0, 0, 0, -s, -s, 0, s, -s]), closeTo(0, 1e-9));
      // Face up on a palm, top edge to the north: camera at the ground.
      expect(facingAzimuth(const [1.0, 0, 0, 0, 1, 0, 0, 0, 1]), closeTo(0, 1e-9));
      // Held overhead face down, tipped back from facing north.
      expect(facingAzimuth(const [1.0, 0, 0, 0, -1, 0, 0, 0, -1]), closeTo(0, 1e-9));
    });

    test('guidance words and on-target', () {
      expect(guide(const SkyDir(0, 10), const SkyDir(90, 40)).words, 'Turn right, tilt up a little');
      expect(guide(const SkyDir(350, 20), const SkyDir(10, 20)).dAzimuth, closeTo(20, 1e-9));
      expect(guide(const SkyDir(100, 30), const SkyDir(20, 30)).words, startsWith('Turn left'));
      final on = guide(const SkyDir(120, 45), const SkyDir(123, 47));
      expect(on.onTarget, isTrue);
      expect(on.words, 'You\'re looking right at it');
      // Near the zenith, azimuth stops mattering: no "turn" instruction, and
      // points across the zenith are measured by true angular distance.
      final zen = guide(const SkyDir(10, 85), const SkyDir(200, 89));
      expect(zen.dAzimuth, 0);
      expect(zen.distanceDeg, closeTo(6, 0.1));
      expect(zen.onTarget, isTrue);
      expect(guide(const SkyDir(10, 85), const SkyDir(200, 86)).onTarget, isFalse); // 9° apart
    });
  });

  group('brightness', () {
    test('standard magnitude at 1000 km and 90° phase', () {
      expect(satelliteMagnitude(stdMag: StdMag.iss, rangeKm: 1000, phaseDeg: 90), closeTo(-1.3, 1e-9));
    });

    test('a close, well-lit ISS pass is Venus-bright; a far, back-lit one is not', () {
      final close = satelliteMagnitude(stdMag: StdMag.iss, rangeKm: 450, phaseDeg: 50);
      final far = satelliteMagnitude(stdMag: StdMag.iss, rangeKm: 1500, phaseDeg: 140);
      expect(close, lessThan(-3.5));
      expect(magnitudeWord(close), 'as bright as Venus');
      expect(far, greaterThan(0));
    });

    test('magnitude words are monotonic', () {
      final words = [-4.0, -2.5, -1.0, 1.0, 2.5, 4.0].map(magnitudeWord).toList();
      expect(words.toSet(), hasLength(6));
    });
  });
}
