/// The Pro camera's plan for one photograph of the sky: which lens, what
/// shutter and ISO, focus, white balance, how many frames and how they
/// become one picture, and what to tell the person holding the phone.
/// Satellite passes have their own plan (capture_plan.dart, Catch it); this
/// covers everything else. Pure Dart.
///
/// Phones can't change aperture: every lens has a fixed f-number. So
/// "aperture" here means choosing the lens, and the plan says so.
library;

import 'dart:math' as math;

import '../models/sky_event.dart';
import 'camera.dart';
import 'capture_plan.dart' show CaptureOverrides;
import 'exposure.dart';

enum ShotSubject {
  moon('The Moon'),
  planet('A planet'),
  pass('A pass'),
  stars('Stars and the Milky Way'),
  trails('Star trails'),
  meteors('Meteors'),
  aurora('Aurora');

  const ShotSubject(this.label);
  final String label;
}

/// How the frames become one picture.
enum StackKind {
  /// Many very short frames; the sharpest few averaged ("lucky" shots
  /// through a shimmering atmosphere). For the Moon.
  sharpest,

  /// A short run averaged: less noise, stars stay points.
  average,

  /// Each pixel's brightest across all frames: star trails, meteors.
  lighten,

  /// Catch it's pass stacker: the sky from a few frames, the streak on top.
  streak,
}

/// What to photograph for an event, or null where the camera mustn't be
/// pointed (the Sun) or there's nothing to aim at.
ShotSubject? subjectForEvent(SkyEventType t) => switch (t) {
      SkyEventType.iss || SkyEventType.tiangong || SkyEventType.starlinkTrain || SkyEventType.satellitePass => ShotSubject.pass,
      SkyEventType.lunarEclipse || SkyEventType.fullMoonRise || SkyEventType.moonPhase || SkyEventType.occultation || SkyEventType.occultationNear =>
        ShotSubject.moon,
      SkyEventType.planetPairing || SkyEventType.planetHighlight => ShotSubject.planet,
      SkyEventType.meteorShower => ShotSubject.meteors,
      SkyEventType.auroraNow || SkyEventType.auroraOutlook => ShotSubject.aurora,
      SkyEventType.rocketLaunch => ShotSubject.trails,
      SkyEventType.comet || SkyEventType.nova || SkyEventType.skyObject => ShotSubject.stars,
      // Never: a phone pointed at the Sun without a solar filter can hurt
      // the eye at the screen and the sensor alike.
      SkyEventType.solarEclipse => null,
      SkyEventType.issTransit => null, // under a second: planned, not photographed here
    };

/// What to photograph for a thing in Explore, by its map id.
ShotSubject subjectForThing(String id) => id == 'moon'
    ? ShotSubject.moon
    : id.startsWith('planet:')
        ? ShotSubject.planet
        : ShotSubject.stars;

class ShotPlan {
  const ShotPlan({
    required this.subject,
    required this.lens,
    required this.exposure,
    required this.manual,
    required this.stack,
    required this.frames,
    required this.keep,
    required this.selfTimer,
    required this.whiteBalanceK,
    required this.tips,
    this.overridden = false,
  });

  final ShotSubject subject;
  final CameraLens lens;
  final Exposure exposure;

  /// Shutter and ISO set by LookUp; false when the phone won't allow it
  /// and exposes by itself.
  final bool manual;
  final StackKind stack;

  /// Frames taken, and how many of them go into the picture.
  final int frames, keep;

  /// A pause between the tap and the first frame, so the phone has stopped
  /// shaking from the tap.
  final Duration selfTimer;

  /// Colour temperature: daylight for the Moon (it's sunlit), cooler for the
  /// night sky to take the orange out of streetlight glow.
  final int whiteBalanceK;

  /// What to do, in words.
  final List<String> tips;
  final bool overridden;

  /// Focus is always at infinity: everything up there is.
  bool get focusAtInfinity => true;

  /// About how long the camera is busy.
  Duration get length => Duration(milliseconds: (frames * math.max(exposure.shutterS, 1 / 30) * 1000).round());

  /// The detail line behind "Pro": the only place numbers show.
  String get detail => manual
      ? '${shutterLabel(exposure.shutterS)} · ISO ${exposure.iso} · f/${_f(lens.fNumber)} · ${lens.kind.label} · '
          '$frames frame${frames == 1 ? '' : 's'}'
      : 'Auto exposure · f/${_f(lens.fNumber)} · ${lens.kind.label} · $frames frames';

  /// Why there's no aperture control.
  String get apertureWords => 'Phone lenses have a fixed aperture (this one is f/${_f(lens.fNumber)}), '
      'so LookUp chooses the lens instead.';

  static String _f(double f) => f.toStringAsFixed(f == f.roundToDouble() ? 0 : 1);
}

/// The longest frame before stars smear across a pixel or two: the "300
/// rule" (300 ÷ the lens's 35 mm-equivalent focal length, in seconds).
double trailLimitS(CameraLens lens) {
  final equivalentMm = 36 / (2 * math.tan(lens.longFovDeg / 2 * math.pi / 180));
  return 300 / equivalentMm;
}

/// How long an average stack can run before the turning sky blurs it by
/// two pixels (the sky turns 15″ a second at most).
double averageSpanS(CameraLens lens, {int longPx = captureLongPxForShots}) => 2 * lens.pixelScaleDeg(longPx) / (15 / 3600);

/// Frames are this many pixels along the long side, as for Catch it.
const captureLongPxForShots = 1920;

/// Plans a photograph of [subject] on a phone that can do [caps] under a
/// sky of [sqm] (mag/arcsec², Sun and Moon included). [moonIllumination]
/// (0–1) sets the Moon's exposure; [length] is how long trails, meteors run.
ShotPlan planShot({
  required ShotSubject subject,
  required CameraCaps caps,
  required double sqm,
  double moonIllumination = 1,
  Duration length = const Duration(minutes: 30),
  CaptureOverrides overrides = const CaptureOverrides(),
}) {
  assert(subject != ShotSubject.pass, 'Passes are planned by planCapture (Catch it).');
  final lens = _lensFor(subject, caps, overrides.lensId);
  final f = lens.fNumber;
  final minS = caps.manual ? caps.minShutterS : 1 / 30;
  final maxS = caps.manual ? caps.maxShutterS : 1 / 30;
  final isoCap = math.min(3200, caps.maxIso);
  int clampIso(num i) => i.round().clamp(caps.minIso, isoCap);

  late Exposure e;
  late StackKind stack;
  late int frames, keep;
  late List<String> tips;
  var wb = 3900;
  switch (subject) {
    case ShotSubject.moon:
      // The Moon is a sunlit landscape: the "Looney 11" rule (f/11 at 1/ISO
      // for a full Moon), a stop more for a half Moon, two for a crescent.
      final extra = math.log(1 / math.max(moonIllumination, 0.1)) / math.ln2;
      var iso = clampIso(caps.minIso < 50 ? 50 : caps.minIso);
      var shutter = (f / 11) * (f / 11) / iso * math.pow(2, extra);
      // Faster than 1/30 s, or the shimmer of the air smears it: buy speed with ISO.
      if (shutter > 1 / 30) {
        iso = clampIso(iso * shutter * 30);
        shutter = 1 / 30;
      }
      e = Exposure(shutterS: shutter.clamp(minS, maxS), iso: iso);
      stack = StackKind.sharpest;
      frames = 40;
      keep = 10;
      wb = 5000;
      tips = [
        'The Moon is bright: LookUp keeps each frame quick and the sensitivity low, so its craters stay sharp.',
        if (lens.kind == LensKind.tele) 'Using the zoom lens, so the Moon fills more of the picture.',
        'Forty quick frames, and only the sharpest ten are kept: the air shimmers, and some frames catch it still.',
      ];
    case ShotSubject.planet:
      // Long enough to show the faint moons beside Jupiter or Saturn, short
      // enough that the zoom lens doesn't smear them.
      final shutter = math.min(0.5, maxS).toDouble();
      var iso = clampIso(isoCap);
      for (final s in isoSteps) {
        if (s < caps.minIso || s > isoCap) continue;
        if (pointLimitMag(iso: s, fNumber: f, sqm: sqm) + 2.5 * math.log(shutter) / math.ln10 >= 6) {
          iso = s;
          break;
        }
      }
      e = Exposure(shutterS: math.max(shutter, minS), iso: iso);
      stack = StackKind.average;
      frames = 20;
      keep = 20;
      wb = 4500;
      tips = [
        'The planet will be a bright dot; its moons are the faint points in a line beside it.',
        'Twenty frames averaged, so the faint ones rise out of the noise.',
      ];
    case ShotSubject.stars || ShotSubject.trails || ShotSubject.meteors || ShotSubject.aurora:
      final longest = math.min(maxS, subject == ShotSubject.aurora ? 2.0 : trailLimitS(lens));
      // The sky sets the exposure (about a quarter of the way up the
      // histogram). Aurora is bright and moving: shorter, and a stop darker.
      final skyEi = skyExposureIndex(subject == ShotSubject.aurora ? sqm - 1.5 : sqm);
      var shutter = longest;
      var iso = clampIso(skyEi * f * f / shutter);
      if (skyEi * f * f / shutter < caps.minIso) {
        // A bright sky: shorten the frame instead of going under the lowest ISO.
        shutter = math.max(minS, skyEi * f * f / caps.minIso);
        iso = clampIso(caps.minIso);
      }
      if (subject == ShotSubject.trails) iso = clampIso(iso / 2); // a stop darker: hundreds of frames add up
      e = Exposure(shutterS: shutter, iso: iso);
      switch (subject) {
        case ShotSubject.stars:
          stack = StackKind.average;
          frames = (averageSpanS(lens) / shutter).floor().clamp(1, 32);
          keep = frames;
          tips = [
            'Get away from lights and let your eyes adjust: what you see is about what the picture will show.',
            'A short run of frames is averaged before the sky has time to turn, so the stars stay sharp points.',
          ];
        case ShotSubject.trails:
          stack = StackKind.lighten;
          frames = math.max(1, (length.inMilliseconds / 1000 / shutter).floor());
          keep = frames;
          tips = [
            'Point it north to circle the pole star, or anywhere for long arcs.',
            'Leave it running: the longer it runs, the longer the trails.',
          ];
        case ShotSubject.meteors:
          stack = StackKind.lighten;
          frames = math.max(1, (length.inMilliseconds / 1000 / shutter).floor());
          keep = frames;
          tips = [
            'Aim about halfway up, a little away from where the shower comes from: the trails are longer there.',
            'LookUp keeps every frame that caught a streak, and stacks them all into one picture.',
          ];
        default:
          stack = StackKind.average;
          frames = 3;
          keep = 3;
          tips = [
            'Aurora moves: short frames keep its curtains sharp.',
            'Face north, with a little ground in the picture.',
          ];
      }
    case ShotSubject.pass:
      throw ArgumentError('Passes are planned by planCapture.');
  }
  if (caps.manual && (overrides.shutterS != null || overrides.iso != null)) {
    e = Exposure(
      shutterS: (overrides.shutterS ?? e.shutterS).clamp(caps.minShutterS, caps.maxShutterS),
      iso: (overrides.iso ?? e.iso).clamp(caps.minIso, caps.maxIso),
    );
  }
  if (!caps.manual) e = Exposure(shutterS: 1 / 30, iso: e.iso);
  return ShotPlan(
    subject: subject,
    lens: lens,
    exposure: e,
    manual: caps.manual,
    stack: stack,
    frames: caps.manual ? frames : math.max(frames, 30),
    keep: caps.manual ? keep : math.max(keep, stack == StackKind.sharpest ? 10 : 30),
    selfTimer: Duration(seconds: caps.manual ? 3 : 2),
    whiteBalanceK: wb,
    tips: [
      ...tips,
      if (!caps.manual) 'This phone won\'t let apps set the shutter, so LookUp stacks its quick frames instead.',
    ],
    overridden: overrides.any,
  );
}

/// The lens for [subject]: the zoom for the Moon and planets, the widest
/// for meteors and aurora (they could be anywhere), otherwise the main one,
/// which gathers the most light.
CameraLens _lensFor(ShotSubject subject, CameraCaps caps, String? chosen) {
  if (chosen != null) {
    final c = caps.lenses.where((l) => l.id == chosen).firstOrNull;
    if (c != null) return c;
  }
  CameraLens? of(LensKind k) => caps.lenses.where((l) => l.kind == k).firstOrNull;
  return switch (subject) {
    ShotSubject.moon || ShotSubject.planet => of(LensKind.tele) ?? caps.main,
    ShotSubject.meteors || ShotSubject.aurora => of(LensKind.ultraWide) ?? caps.main,
    _ => caps.main,
  };
}

/// Moves [e] by [stops] (positive brighter): the shutter first where it has
/// room (but never past [maxShutterS]), then the ISO.
Exposure adjustExposure(Exposure e, double stops, CameraCaps caps, {double? maxShutterS}) {
  if (stops == 0) return e;
  final factor = math.pow(2, stops).toDouble();
  final cap = math.min(maxShutterS ?? caps.maxShutterS, caps.maxShutterS);
  var shutter = (e.shutterS * factor).clamp(caps.minShutterS, cap);
  final left = factor / (shutter / e.shutterS);
  final iso = (e.iso * left).round().clamp(caps.minIso, caps.maxIso);
  return Exposure(shutterS: shutter, iso: iso);
}
