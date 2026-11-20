import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/photo/camera.dart';
import 'package:lookup/domain/photo/capture_plan.dart' show CaptureOverrides;
import 'package:lookup/domain/photo/exposure.dart';
import 'package:lookup/domain/photo/frame_check.dart';
import 'package:lookup/domain/photo/shot_plan.dart';

void main() {
  const main_ = CameraLens(id: 'main', kind: LensKind.wide, longFovDeg: 66, shortFovDeg: 52, fNumber: 1.8);
  const ultra = CameraLens(id: 'ultra', kind: LensKind.ultraWide, longFovDeg: 106, shortFovDeg: 86, fNumber: 2.2);
  const tele = CameraLens(id: 'tele', kind: LensKind.tele, longFovDeg: 30, shortFovDeg: 23, fNumber: 2.8);
  // A three-lens phone that allows a 1 s shutter (as iPhones do).
  const phone = CameraCaps(lenses: [main_, ultra, tele], manual: true, minShutterS: 1 / 8000, maxShutterS: 1, minIso: 32, maxIso: 3200);
  // An Android phone that allows long frames.
  const android = CameraCaps(lenses: [main_, ultra], manual: true, minShutterS: 1 / 8000, maxShutterS: 30, minIso: 100, maxIso: 6400);
  const darkSite = 21.4, suburbs = 19.8;

  group('what to photograph', () {
    test('never the Sun: no Pro camera for a solar eclipse', () {
      expect(subjectForEvent(SkyEventType.solarEclipse), isNull);
    });
    test('passes go to Catch it; the Moon, planets, meteors and aurora have their own plans', () {
      expect(subjectForEvent(SkyEventType.iss), ShotSubject.pass);
      expect(subjectForEvent(SkyEventType.lunarEclipse), ShotSubject.moon);
      expect(subjectForEvent(SkyEventType.planetPairing), ShotSubject.planet);
      expect(subjectForEvent(SkyEventType.meteorShower), ShotSubject.meteors);
      expect(subjectForEvent(SkyEventType.auroraNow), ShotSubject.aurora);
      expect(subjectForThing('moon'), ShotSubject.moon);
      expect(subjectForThing('planet:jupiter'), ShotSubject.planet);
      expect(subjectForThing('con:Ori'), ShotSubject.stars);
    });
  });

  group('the Moon', () {
    final full = planShot(subject: ShotSubject.moon, caps: phone, sqm: suburbs);
    test('the zoom lens, a fast shutter and a low ISO: it is a sunlit landscape', () {
      expect(full.lens.kind, LensKind.tele);
      expect(full.exposure.shutterS, lessThan(1 / 250));
      expect(full.exposure.iso, lessThanOrEqualTo(64));
      expect(full.whiteBalanceK, 5000, reason: 'daylight: it is lit by the Sun');
      expect(full.focusAtInfinity, isTrue);
    });
    test('many quick frames, only the sharpest kept', () {
      expect(full.stack, StackKind.sharpest);
      expect(full.keep, lessThan(full.frames));
    });
    test('a half Moon gets a stop more light, a crescent two', () {
      final half = planShot(subject: ShotSubject.moon, caps: phone, sqm: suburbs, moonIllumination: 0.5);
      final crescent = planShot(subject: ShotSubject.moon, caps: phone, sqm: suburbs, moonIllumination: 0.25);
      double light(ShotPlan p) => p.exposure.shutterS * p.exposure.iso;
      expect(light(half) / light(full), closeTo(2, 0.2));
      expect(light(crescent) / light(full), closeTo(4, 0.4));
    });
    test('never slower than 1/30 s, whatever the phase', () {
      final thin = planShot(subject: ShotSubject.moon, caps: phone, sqm: suburbs, moonIllumination: 0.02);
      expect(thin.exposure.shutterS, lessThanOrEqualTo(1 / 30 + 1e-9));
    });
    test('without a zoom lens, the main one', () {
      expect(planShot(subject: ShotSubject.moon, caps: android, sqm: suburbs).lens.kind, LensKind.wide);
    });
  });

  test('a planet: the zoom lens, frames short enough not to smear, averaged', () {
    final p = planShot(subject: ShotSubject.planet, caps: phone, sqm: suburbs);
    expect(p.lens.kind, LensKind.tele);
    expect(p.exposure.shutterS, lessThanOrEqualTo(0.5));
    expect(p.stack, StackKind.average);
  });

  group('stars', () {
    test('the 300 rule: about 11 s on a main lens, longer on an ultra-wide, shorter on the zoom', () {
      expect(trailLimitS(main_), closeTo(10.8, 0.5));
      expect(trailLimitS(ultra), greaterThan(trailLimitS(main_)));
      expect(trailLimitS(tele), lessThan(trailLimitS(main_)));
    });
    test('the main lens (most light), frames as long as the phone and the turning sky allow', () {
      final p = planShot(subject: ShotSubject.stars, caps: android, sqm: darkSite);
      expect(p.lens.kind, LensKind.wide);
      expect(p.exposure.shutterS, closeTo(trailLimitS(main_), 0.01));
      expect(p.stack, StackKind.average);
      expect(p.frames * p.exposure.shutterS, lessThanOrEqualTo(averageSpanS(main_) + p.exposure.shutterS),
          reason: 'the run ends before the sky turns enough to blur it');
      final iphone = planShot(subject: ShotSubject.stars, caps: phone, sqm: darkSite);
      expect(iphone.exposure.shutterS, 1, reason: 'never longer than the phone allows');
      expect(iphone.frames, greaterThan(p.frames), reason: 'shorter frames, more of them');
    });
    test('a dark sky takes a higher ISO than a suburban one', () {
      final dark = planShot(subject: ShotSubject.stars, caps: android, sqm: darkSite);
      final town = planShot(subject: ShotSubject.stars, caps: android, sqm: suburbs);
      expect(dark.exposure.iso, greaterThan(town.exposure.iso));
    });
    test('trails and meteors stack the brightest of every frame; meteors and aurora take the widest lens', () {
      final trails = planShot(subject: ShotSubject.trails, caps: phone, sqm: darkSite, length: const Duration(minutes: 20));
      expect(trails.stack, StackKind.lighten);
      expect(trails.frames, closeTo(20 * 60 / trails.exposure.shutterS, 1));
      final meteors = planShot(subject: ShotSubject.meteors, caps: phone, sqm: darkSite);
      expect(meteors.stack, StackKind.lighten);
      expect(meteors.lens.kind, LensKind.ultraWide);
      final aurora = planShot(subject: ShotSubject.aurora, caps: android, sqm: darkSite);
      expect(aurora.lens.kind, LensKind.ultraWide);
      expect(aurora.exposure.shutterS, lessThanOrEqualTo(2), reason: 'it moves');
    });
  });

  test('a phone without manual exposure: quick frames, more of them, and it says so', () {
    const auto = CameraCaps.auto;
    final p = planShot(subject: ShotSubject.stars, caps: auto, sqm: darkSite);
    expect(p.manual, isFalse);
    expect(p.exposure.shutterS, closeTo(1 / 30, 1e-9));
    expect(p.frames, greaterThanOrEqualTo(30));
    expect(p.tips.last, contains('won\'t let apps set the shutter'));
  });

  test('numbers only in the detail line; it explains why there is no aperture control', () {
    final p = planShot(subject: ShotSubject.moon, caps: phone, sqm: suburbs);
    expect(p.detail, contains('f/2.8'));
    expect(p.detail, contains('ISO'));
    expect(p.apertureWords, contains('fixed aperture'));
    for (final t in p.tips) {
      expect(t, isNot(contains('°')));
      expect(t, isNot(contains('ISO')));
    }
  });

  test('Pro choices win, within what the phone allows', () {
    final p = planShot(
        subject: ShotSubject.stars, caps: phone, sqm: darkSite, overrides: const CaptureOverrides(shutterS: 30, iso: 800, lensId: 'ultra'));
    expect(p.exposure.shutterS, 1, reason: 'the phone stops at 1 s');
    expect(p.exposure.iso, 800);
    expect(p.lens.id, 'ultra');
    expect(p.overridden, isTrue);
  });

  test('a self-timer, so the tap has stopped shaking the phone', () {
    expect(planShot(subject: ShotSubject.stars, caps: phone, sqm: darkSite).selfTimer, const Duration(seconds: 3));
  });

  group('moving the exposure', () {
    test('darker: the shutter first', () {
      final e = adjustExposure(const Exposure(shutterS: 1 / 500, iso: 50), -1, phone);
      expect(e.shutterS, closeTo(1 / 1000, 1e-9));
      expect(e.iso, 50);
    });
    test('brighter past the longest shutter: then the ISO', () {
      final e = adjustExposure(const Exposure(shutterS: 1, iso: 800), 1, phone);
      expect(e.shutterS, 1);
      expect(e.iso, 1600);
    });
    test('a cap on the shutter (the Moon) is kept', () {
      final e = adjustExposure(const Exposure(shutterS: 1 / 60, iso: 50), 2, phone, maxShutterS: 1 / 30);
      expect(e.shutterS, closeTo(1 / 30, 1e-9));
      expect(e.iso, 100);
    });
  });

  group('checking a frame', () {
    const w = 200, h = 150;
    Uint8List sky(int level) => Uint8List(w * h)..fillRange(0, w * h, level);
    Uint8List moonOn(int level) {
      final y = sky(4);
      for (var yy = 0; yy < h; yy++) {
        for (var xx = 0; xx < w; xx++) {
          if (math.pow(xx - 100, 2) + math.pow(yy - 75, 2) < 30 * 30) y[yy * w + xx] = level;
        }
      }
      return y;
    }

    test('the Moon: too bright once it clips, too dark when it is dim, right in between', () {
      expect(checkExposure(moonOn(255), ShotSubject.moon).verdict, ExposureVerdict.tooBright);
      expect(checkExposure(moonOn(255), ShotSubject.moon).stops, lessThan(0));
      expect(checkExposure(moonOn(70), ShotSubject.moon).verdict, ExposureVerdict.tooDark);
      expect(checkExposure(moonOn(70), ShotSubject.moon).stops, greaterThan(0));
      expect(checkExposure(moonOn(225), ShotSubject.moon).verdict, ExposureVerdict.good);
    });

    test('the night sky: washed out, black, or right', () {
      expect(checkExposure(sky(160), ShotSubject.stars).verdict, ExposureVerdict.tooBright);
      expect(checkExposure(sky(3), ShotSubject.stars).verdict, ExposureVerdict.tooDark);
      expect(checkExposure(sky(35), ShotSubject.stars).verdict, ExposureVerdict.good);
      expect(checkExposure(sky(35), ShotSubject.stars).words, isNot(contains('ISO')));
    });

    test('a meteor: a thin new line counts; a flash, a blob or nothing new does not', () {
      final prev = sky(10);
      final line = Uint8List.fromList(prev);
      for (var i = 0; i <= 160; i++) {
        final xx = 20 + i, yy = 30 + (i * 90 / 160).round();
        line[yy * w + xx] = 220;
        line[(yy + 1) * w + xx] = 220;
      }
      expect(caughtStreak(prev, line, w), isTrue);
      expect(caughtStreak(prev, sky(90), w), isFalse, reason: 'the whole frame brightened: headlights');
      final blob = Uint8List.fromList(prev);
      for (var yy = 60; yy < 72; yy++) {
        for (var xx = 90; xx < 102; xx++) {
          blob[yy * w + xx] = 220;
        }
      }
      expect(caughtStreak(prev, blob, w), isFalse, reason: 'round, not a line');
      expect(caughtStreak(prev, Uint8List.fromList(prev), w), isFalse);
    });
  });
}
