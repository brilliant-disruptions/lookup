import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/pointing.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
import 'package:lookup/domain/photo/camera.dart';
import 'package:lookup/domain/photo/capture_plan.dart';
import 'package:lookup/domain/photo/exposure.dart';
import 'package:lookup/domain/photo/framing.dart';
import 'package:lookup/domain/photo/practice_sky.dart';
import 'package:lookup/domain/photo/streak_stacker.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/domain/sky/visibility.dart';

const _main = CameraLens(id: '0', kind: LensKind.wide, longFovDeg: 69, shortFovDeg: 54, fNumber: 1.8);
const _ultra = CameraLens(id: '2', kind: LensKind.ultraWide, longFovDeg: 108, shortFovDeg: 88, fNumber: 2.2);
const _pixel = CameraCaps(lenses: [_main, _ultra], manual: true, minShutterS: 1 / 8000, maxShutterS: 1.0, minIso: 50, maxIso: 6400);

void main() {
  late OmmRecord iss;
  late List<SkyEvent> london;
  setUpAll(() {
    iss = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync())).single;
    london = PassPredictor(latitude: 51.5, longitude: -0.12).predict(
      record: iss,
      type: SkyEventType.iss,
      from: DateTime.utc(2026, 10, 20, 16),
      to: DateTime.utc(2026, 10, 24),
      minPeakElevationDeg: 10,
    );
  });

  group('path', () {
    test('a real pass follows the elements from rise to set', () {
      final e = london.first;
      final path = passPath(e, 51.5, -0.12);
      expect(path.first.t, e.start);
      expect(path.last.t.difference(e.end).inSeconds.abs(), lessThanOrEqualTo(5));
      final peak = path.map((p) => p.d.elevationDeg).reduce(math.max);
      expect(peak, closeTo(e.peakElevationDeg, 1.5));
      // The station moves about a degree a second at most, seen from the ground.
      expect(peakAngularSpeed(path), inInclusiveRange(0.2, 1.3));
    });

    test('without elements it still draws an arc through rise, peak and set', () {
      final e = SkyEvent(
        id: 'x', type: SkyEventType.iss,
        start: DateTime.utc(2026, 11, 2, 18), peak: DateTime.utc(2026, 11, 2, 18, 2), end: DateTime.utc(2026, 11, 2, 18, 4),
        peakElevationDeg: 50, riseAzimuthDeg: 250, peakAzimuthDeg: 190, setAzimuthDeg: 100,
      );
      final path = arcPath(e);
      expect(path.first.d.azimuthDeg, closeTo(250, 0.1));
      expect(path.last.d.azimuthDeg, closeTo(100, 0.1));
      expect(path.map((p) => p.d.elevationDeg).reduce(math.max), closeTo(50, 0.1));
    });
  });

  group('framing', () {
    test('a level camera puts the horizon below the middle', () {
      final p = frameCoords(const SkyDir(180, 20), const SkyDir(180, 0))!;
      expect(p.x, closeTo(0, 1e-9));
      expect(p.y, closeTo(-math.tan(20 * math.pi / 180), 1e-9));
      // East of a south-facing camera is to its left.
      expect(frameCoords(const SkyDir(180, 20), const SkyDir(170, 20))!.x, lessThan(0));
      expect(frameCoords(const SkyDir(180, 20), const SkyDir(0, 20)), isNull);
    });

    test('every London pass gets a frame that catches most of it, horizon in view', () {
      for (final e in london) {
        final f = frameFor(passPath(e, 51.5, -0.12), _pixel.lenses)!;
        expect(f.coverage, greaterThan(0.45), reason: '${e.start} $f');
        expect(f.enters.isBefore(f.leaves), isTrue);
        expect(f.contains(f.center), isTrue);
      }
    });

    test('a short low pass stays on the main camera; a long one reaches for the ultra-wide', () {
      final low = [
        for (var i = 0; i <= 12; i++) (t: DateTime.utc(2026, 11, 2, 18, 0, i * 5), d: SkyDir(200 + i * 1.5, 14 + i * 0.5)),
      ];
      expect(frameFor(low, _pixel.lenses)!.lens.kind, LensKind.wide);
      final big = [
        for (var i = 0; i <= 60; i++)
          (t: DateTime.utc(2026, 11, 2, 18, 0, 0).add(Duration(seconds: i * 5)), d: SkyDir(260 - i * 2.6, 10 + 60 * math.sin(i / 60 * math.pi))),
      ];
      final f = frameFor(big, _pixel.lenses)!;
      expect(f.lens.kind, LensKind.ultraWide);
      expect(f.landscape, isTrue, reason: 'a pass that long and wide wants the phone on its side');
    });

    test('a pass that\'s only in one corner of the sky is still framed', () {
      final path = [for (var i = 0; i < 10; i++) (t: DateTime.utc(2026, 11, 2, 18, 0, i * 5), d: SkyDir(30.0 + i, 25.0))];
      final f = frameFor(path, const [_main])!;
      expect(f.coverage, closeTo(1, 1e-9));
    });
  });

  group('exposure', () {
    test('twilight and the Moon brighten the sky; a dark site at night is darkest', () {
      final night = skySqm(siteSqm: 21.4, sunAltDeg: -30);
      expect(night, closeTo(21.4, 0.3));
      expect(skySqm(siteSqm: 21.4, sunAltDeg: -8), lessThan(night - 2));
      expect(skySqm(siteSqm: 21.4, sunAltDeg: -30, moonIllumination: 1, moonAltDeg: 50), lessThan(19));
      expect(skySqm(siteSqm: 21.4, sunAltDeg: -30, moonIllumination: 1, moonAltDeg: -5), closeTo(night, 1e-9));
      expect(typicalSqm(SkyDarkness.city), lessThan(typicalSqm(SkyDarkness.dark)));
    });

    test('a city sky gets shorter frames than a dark one, and never past what the phone allows', () {
      Exposure at(double sqm) => exposureFor(
            mag: -2, speedDegPerS: 0.8, sqm: sqm, fNumber: 1.8, pixelScaleDeg: 69 / 1920,
            minShutterS: _pixel.minShutterS, maxShutterS: _pixel.maxShutterS, minIso: 50, maxIso: 6400,
          ).exposure;
      final city = at(16.5), dark = at(21.4);
      expect(city.shutterS * city.iso, lessThan(dark.shutterS * dark.iso));
      expect(dark.shutterS, lessThanOrEqualTo(_pixel.maxShutterS));
      expect(dark.iso, lessThanOrEqualTo(1600), reason: 'phone noise past 1600 isn\'t worth it for the sky');
      // Bright twilight: the fastest shutter isn't enough, so the ISO drops.
      final bright = exposureFor(
        mag: -2, speedDegPerS: 0.8, sqm: 11, fNumber: 1.8, pixelScaleDeg: 69 / 1920,
        minShutterS: 1 / 30, maxShutterS: 1, minIso: 50, maxIso: 6400,
      ).exposure;
      expect(bright.shutterS, closeTo(1 / 30, 1e-9));
      expect(bright.iso, lessThan(400));
    });

    test('a longer shutter brightens the sky, not the streak', () {
      final a = movingEquivalentMag(mag: -2, speedDegPerS: 0.8, pixelScaleDeg: 0.036);
      expect(a, closeTo(-2 + 2.5 * math.log(0.8 / 0.036) / math.ln10, 1e-9));
      expect(skyExposureIndex(18) < skyExposureIndex(21), isTrue);
    });

    test('the station is a strong streak even from a city; a Starlink train in town is too faint', () {
      final issCity = planCapture(path: passPath(london.first, 51.5, -0.12), magnitude: -2.5, caps: _pixel,
          siteSqm: typicalSqm(SkyDarkness.city), sunAltDeg: -25)!;
      expect(issCity.outlook, StreakOutlook.strong);
      final trainPath = [
        for (var i = 0; i <= 40; i++) (t: DateTime.utc(2026, 11, 2, 18).add(Duration(seconds: i * 5)), d: SkyDir(240 - i * 3, 15 + 40 * math.sin(i / 40 * math.pi))),
      ];
      final trainCity = planCapture(path: trainPath, magnitude: 4.0, caps: _pixel, siteSqm: typicalSqm(SkyDarkness.city), sunAltDeg: -25)!;
      expect(trainCity.outlook, StreakOutlook.tooFaint);
      final trainDark = planCapture(path: trainPath, magnitude: 2.0, caps: _pixel, siteSqm: typicalSqm(SkyDarkness.dark), sunAltDeg: -25)!;
      expect(trainDark.outlook, isNot(StreakOutlook.tooFaint));
    });

    test('a phone without manual control is planned honestly: auto, and a step less hopeful', () {
      final path = passPath(london.first, 51.5, -0.12);
      final manual = planCapture(path: path, magnitude: 1.0, caps: _pixel, siteSqm: 19.8, sunAltDeg: -25)!;
      final auto = planCapture(path: path, magnitude: 1.0, caps: CameraCaps.auto, siteSqm: 19.8, sunAltDeg: -25)!;
      expect(auto.manual, isFalse);
      expect(auto.outlook.index, greaterThanOrEqualTo(manual.outlook.index));
      expect(auto.detail, startsWith('Auto exposure'));
    });

    test('the Pro sheet\'s choices are kept, within what the phone allows', () {
      final path = passPath(london.first, 51.5, -0.12);
      final p = planCapture(path: path, magnitude: -2, caps: _pixel, siteSqm: 19.8, sunAltDeg: -25,
          overrides: const CaptureOverrides(shutterS: 30, iso: 400, lensId: '0'))!;
      expect(p.exposure.shutterS, _pixel.maxShutterS);
      expect(p.exposure.iso, 400);
      expect(p.lens.id, '0');
      expect(p.overridden, isTrue);
    });
  });

  group('plan words', () {
    test('the main line has directions in words and no numbers; numbers live in the detail', () {
      final p = planCapture(path: passPath(london.first, 51.5, -0.12), magnitude: -2, caps: _pixel, siteSqm: 19.8, sunAltDeg: -25)!;
      for (final s in [p.aimWords, p.holdWords, p.outlookWords, p.coverageWords]) {
        expect(s, isNot(matches(RegExp(r'\d'))), reason: s);
      }
      expect(p.detail, contains('ISO'));
      expect(p.startAt.isBefore(p.framing.enters), isTrue);
      expect(p.stopAt.isAfter(p.framing.leaves), isTrue);
      expect(p.frames, greaterThan(20));
    });

    test('steady and level', () {
      final still = [for (var i = 0; i < 10; i++) SkyDir(200 + i * 0.01, 30)];
      expect(isSteady(still), isTrue);
      expect(isSteady([...still, const SkyDir(203, 30)]), isFalse);
      expect(isSteady(still.take(3).toList()), isFalse);
      // Upright and level: device x is horizontal.
      const level = [1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 1.0, 0.0];
      expect(tiltDeg(level), closeTo(0, 1e-9));
      expect(heldQuarterTurns(level), 0);
      expect(levelWords(0.5), isNull);
      final s = math.sin(15 * math.pi / 180), c = math.cos(15 * math.pi / 180);
      // Right edge raised 15°: the left side is low.
      final tipped = [c, -s, 0.0, 0.0, 0.0, -1.0, s, c, 0.0];
      expect(tiltDeg(tipped), closeTo(15, 1e-6));
      expect(levelWords(15), contains('left side is low'));
    });

    test('a level pose points the camera where asked, however the phone is held', () {
      const c = SkyDir(213, 27);
      for (final turns in const [0, 1, 3]) {
        final r = levelPose(c, quarterTurns: turns);
        final d = cameraDirection(r);
        expect(d.azimuthDeg, closeTo(213, 1e-6));
        expect(d.elevationDeg, closeTo(27, 1e-6));
        expect(tiltDeg(r, quarterTurns: turns), closeTo(0, 1e-6));
        expect(heldQuarterTurns(r), turns);
      }
    });
  });

  group('stacking', () {
    const w = 160, h = 120;
    final rng = math.Random(3);
    double gauss() => math.sqrt(-2 * math.log(math.max(rng.nextDouble(), 1e-12))) * math.cos(2 * math.pi * rng.nextDouble());
    const stars = [(20, 30, 90.0), (100, 80, 60.0), (140, 15, 120.0)];

    Uint8List frame(int k, {bool dot = true}) {
      final f = Uint8List(w * h);
      for (var i = 0; i < f.length; i++) {
        f[i] = (30 + gauss() * 5).round().clamp(0, 255);
      }
      for (final (x, y, b) in stars) {
        f[y * w + x] = (30 + b).round().clamp(0, 255);
      }
      // A satellite crossing left to right, 4 px per frame, as a short dash.
      if (dot) {
        for (var s = 0; s < 4; s++) {
          final x = 5 + k * 4 + s;
          if (x < w) f[60 * w + x] = 200;
        }
      }
      return f;
    }

    test('the streak comes out unbroken, the stars stay, the sky stays dark', () {
      final st = StreakStacker(w, h);
      for (var k = 0; k < 36; k++) {
        st.add(frame(k));
      }
      final out = st.luma();
      for (var x = 5; x < 5 + 36 * 4 && x < w; x++) {
        expect(out[60 * w + x], greaterThan(150), reason: 'gap at x=$x');
      }
      for (final (x, y, b) in stars) {
        expect(out[y * w + x], closeTo(30 + b, 12));
      }
      var sum = 0.0;
      for (var y = 90; y < 110; y++) {
        for (var x = 0; x < w; x++) {
          sum += out[y * w + x];
        }
      }
      expect(sum / (20 * w), closeTo(30, 3), reason: 'noise must not build up');
    });

    test('a plain lighten stack would grey the sky; this one doesn\'t', () {
      final st = StreakStacker(w, h);
      final naive = Uint8List(w * h);
      for (var k = 0; k < 60; k++) {
        final f = frame(k, dot: false);
        st.add(f);
        for (var i = 0; i < f.length; i++) {
          if (f[i] > naive[i]) naive[i] = f[i];
        }
      }
      double mean(Uint8List a) => a.fold<int>(0, (s, v) => s + v) / a.length;
      expect(mean(naive), greaterThan(40));
      expect(mean(st.luma()), lessThan(33));
    });

    test('rotating the picture keeps every pixel', () {
      final st = StreakStacker(4, 2);
      st.add(Uint8List.fromList([10, 20, 30, 40, 50, 60, 70, 80]));
      final r = st.rgba(quarterTurns: 1);
      expect((r.width, r.height), (2, 4));
      // Top-left of the source ends up top-right.
      expect(r.rgba[(0 * 2 + 1) * 4], 10);
      expect(r.rgba[(3 * 2 + 0) * 4], 80);
    });
  });

  test('the practice sky shows the planned pass as a streak once stacked', () {
    final e = london.first;
    final path = passPath(e, 51.5, -0.12);
    final plan = planCapture(path: path, magnitude: -2.5, caps: _pixel, siteSqm: 19.8, sunAltDeg: -25)!;
    final catalog = SkyCatalog.fromJson(jsonDecode(File('assets/sky/stars.json').readAsStringSync()),
        jsonDecode(File('assets/sky/constellations.json').readAsStringSync()));
    final sky = PracticeSky(framing: plan.framing, path: path, magnitude: -2.5, exposure: plan.exposure, sqm: plan.sqm,
        latDeg: 51.5, lonDeg: -0.12, catalog: catalog, width: 240);
    final st = StreakStacker(sky.width, sky.height);
    final step = Duration(microseconds: (plan.exposure.shutterS * 1e6).round());
    for (var t = plan.startAt; t.isBefore(plan.stopAt); t = t.add(step)) {
      final f = sky.frameAt(t);
      st.add(f.y, u: f.u, v: f.v);
    }
    // The streak layer lights up along the predicted path.
    final streak = st.streak();
    var lit = 0, checked = 0;
    for (final p in path) {
      final q = plan.framing.toPicture(p.d);
      if (q == null || q.x < 0.03 || q.x > 0.97 || q.y < 0.03 || q.y > 0.97 || p.d.elevationDeg < 12) continue;
      checked++;
      final x = (q.x * sky.width).floor(), y = (q.y * sky.height).floor();
      var best = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final i = (y + dy).clamp(0, sky.height - 1) * sky.width + (x + dx).clamp(0, sky.width - 1);
          best = math.max(best, streak[i]);
        }
      }
      if (best > 20) lit++;
    }
    expect(checked, greaterThan(10));
    expect(lit / checked, greaterThan(0.9));
  });
}
