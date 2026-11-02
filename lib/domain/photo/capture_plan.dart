/// "Catch it": the whole plan for photographing one pass with a propped-up
/// phone — which lens, where to point, shutter, ISO, how many frames, when
/// to start and stop — and the words for it. Pure Dart.
library;

import 'dart:math' as math;

import 'package:satellite_observer/satellite_observer.dart';

import '../finder/pointing.dart';
import '../models/sky_event.dart';
import '../orbit/omm.dart';
import '../sky/direction.dart';
import 'camera.dart';
import 'exposure.dart';
import 'framing.dart';

/// The visible pass across the sky every [step], from the elements it
/// carries; without them (or if they disagree with the event), a smooth
/// arc through where it rises, peaks and sets.
List<PathPoint> passPath(SkyEvent e, double latDeg, double lonDeg, {Duration step = const Duration(seconds: 5)}) {
  final omm = e.details['omm'];
  if (omm is Map) {
    try {
      final sat = SatelliteObserver(
        elements: OmmRecord.fromJson(omm.cast<String, Object?>()).toElements(),
        observer: Observer(latitudeDeg: latDeg, longitudeDeg: lonDeg),
      );
      final out = <PathPoint>[];
      for (var t = e.start; !t.isAfter(e.end); t = t.add(step)) {
        final look = sat.lookAngleAt(t);
        out.add((t: t, d: SkyDir(look.azimuthDeg, look.elevationDeg)));
      }
      final peak = sat.lookAngleAt(e.peak);
      if (out.length >= 2 && (peak.elevationDeg - e.peakElevationDeg).abs() < 5) return out;
    } catch (_) {
      // Fall through to the arc.
    }
  }
  return arcPath(e, step: step);
}

/// A pass drawn from its rise, peak and set alone.
List<PathPoint> arcPath(SkyEvent e, {Duration step = const Duration(seconds: 5)}) {
  double turn(double from, double to) {
    var d = to - from;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  final out = <PathPoint>[];
  final total = e.end.difference(e.start).inMilliseconds;
  final toPeak = e.peak.difference(e.start).inMilliseconds;
  if (total <= 0) return out;
  for (var t = e.start; !t.isAfter(e.end); t = t.add(step)) {
    final ms = t.difference(e.start).inMilliseconds;
    final first = ms <= toPeak;
    final f = first ? (toPeak == 0 ? 1.0 : ms / toPeak) : (ms - toPeak) / math.max(1, total - toPeak);
    final az = first
        ? e.riseAzimuthDeg + turn(e.riseAzimuthDeg, e.peakAzimuthDeg) * f
        : e.peakAzimuthDeg + turn(e.peakAzimuthDeg, e.setAzimuthDeg) * f;
    final low = 10.0;
    final el = first
        ? low + (e.peakElevationDeg - low) * math.sin(f * math.pi / 2)
        : low + (e.peakElevationDeg - low) * math.cos(f * math.pi / 2);
    out.add((t: t, d: SkyDir((az + 360) % 360, el)));
  }
  return out;
}

/// Frames are this many pixels along the sensor's long side. Enough for a
/// sharp share and a phone screen; small enough to stack live.
const captureLongPx = 1920;

/// Kinds of event that cross the sky as a moving light.
bool canCatch(SkyEventType t) =>
    t == SkyEventType.iss || t == SkyEventType.tiangong || t == SkyEventType.starlinkTrain || t == SkyEventType.satellitePass;

/// Brightness to plan for when the event doesn't carry one.
double typicalMagnitude(SkyEvent e) {
  final m = e.details['magnitude'];
  if (m is num) return m.toDouble();
  return switch (e.type) {
    SkyEventType.iss => -2.0,
    SkyEventType.tiangong => -1.0,
    SkyEventType.starlinkTrain => 3.0,
    _ => 2.0,
  };
}

/// Choices from the Pro sheet. Null fields follow the plan.
class CaptureOverrides {
  const CaptureOverrides({this.shutterS, this.iso, this.lensId});
  final double? shutterS;
  final int? iso;
  final String? lensId;
  bool get any => shutterS != null || iso != null || lensId != null;
}

class CapturePlan {
  const CapturePlan({
    required this.framing,
    required this.exposure,
    required this.manual,
    required this.startAt,
    required this.stopAt,
    required this.outlook,
    required this.sqm,
    this.overridden = false,
  });

  final Framing framing;
  final Exposure exposure;

  /// Shutter and ISO are set by LookUp. False: the phone exposes by itself
  /// and LookUp stacks its quick frames.
  final bool manual;
  final DateTime startAt, stopAt;
  final StreakOutlook outlook;

  /// The sky's brightness the plan assumed (mag/arcsec²).
  final double sqm;
  final bool overridden;

  CameraLens get lens => framing.lens;
  Duration get length => stopAt.difference(startAt);

  /// About how many frames go into the picture.
  int get frames => manual ? (length.inMilliseconds / 1000 / exposure.shutterS).ceil() : (length.inSeconds * 10);

  /// "Point it west-southwest, low in the sky" — words, never degrees.
  String get aimWords => 'Point it ${compassWord(framing.center.azimuthDeg)}, ${elevationWord(framing.center.elevationDeg)}';

  String get holdWords => framing.landscape ? 'Turn your phone on its side and prop it up' : 'Prop your phone up, standing upright';

  String get outlookWords => switch (outlook) {
        StreakOutlook.strong => 'It should leave a bright streak.',
        StreakOutlook.faint => 'Expect a thin, faint line: it\'s dim for a phone camera.',
        StreakOutlook.tooFaint => 'Probably too faint for a phone camera. Worth a try, but watch it too.',
      };

  /// How much of the pass will be in the picture.
  String get coverageWords {
    final c = framing.coverage;
    if (c >= 0.9) return 'The whole pass fits';
    if (c >= 0.6) return 'Most of the pass fits';
    return 'The best part of the pass fits';
  }

  /// The detail line behind the Pro sheet: the only place numbers show.
  String get detail => manual
      ? '${shutterLabel(exposure.shutterS)} · ISO ${exposure.iso} · $frames frames · ${lens.kind.label}'
      : 'Auto exposure · ${lens.kind.label} · quick frames stacked';
}

/// Plans [path] (the visible pass, from rise to set) for a satellite of
/// magnitude [magnitude] on a phone that can do [caps], under a sky of
/// [siteSqm] with the Sun and Moon where they'll be. Null when nothing of
/// the pass can be framed.
CapturePlan? planCapture({
  required List<PathPoint> path,
  required double magnitude,
  required CameraCaps caps,
  required double siteSqm,
  required double sunAltDeg,
  double moonIllumination = 0,
  double moonAltDeg = -90,
  CaptureOverrides overrides = const CaptureOverrides(),
}) {
  final lenses = overrides.lensId == null
      ? caps.lenses
      : caps.lenses.where((l) => l.id == overrides.lensId).toList();
  final framing = frameFor(path, lenses.isEmpty ? caps.lenses : lenses);
  if (framing == null) return null;
  final sqm = skySqm(siteSqm: siteSqm, sunAltDeg: sunAltDeg, moonIllumination: moonIllumination, moonAltDeg: moonAltDeg);
  final speed = peakAngularSpeed(path);
  final planned = exposureFor(
    mag: magnitude,
    speedDegPerS: speed,
    sqm: sqm,
    fNumber: framing.lens.fNumber,
    pixelScaleDeg: framing.lens.pixelScaleDeg(captureLongPx),
    minShutterS: caps.manual ? caps.minShutterS : 1 / 30,
    maxShutterS: caps.manual ? caps.maxShutterS : 1 / 30,
    minIso: caps.minIso,
    maxIso: caps.maxIso,
  );
  var exposure = planned.exposure;
  var outlook = planned.outlook;
  if (caps.manual && (overrides.shutterS != null || overrides.iso != null)) {
    exposure = Exposure(
      shutterS: (overrides.shutterS ?? exposure.shutterS).clamp(caps.minShutterS, caps.maxShutterS),
      iso: (overrides.iso ?? exposure.iso).clamp(caps.minIso, caps.maxIso),
    );
    final eq = movingEquivalentMag(mag: magnitude, speedDegPerS: speed, pixelScaleDeg: framing.lens.pixelScaleDeg(captureLongPx));
    final margin = pointLimitMag(iso: exposure.iso, fNumber: framing.lens.fNumber, sqm: sqm) - eq;
    outlook = margin >= 1.0 ? StreakOutlook.strong : (margin >= -0.5 ? StreakOutlook.faint : StreakOutlook.tooFaint);
  }
  if (!caps.manual) {
    // Auto exposure on a phone runs short frames: a stop or two less reach.
    outlook = StreakOutlook.values[math.min(outlook.index + 1, StreakOutlook.values.length - 1)];
  }
  return CapturePlan(
    framing: framing,
    exposure: exposure,
    manual: caps.manual,
    // A little early (it rises out of haze) and a little late.
    startAt: framing.enters.subtract(const Duration(seconds: 15)),
    stopAt: framing.leaves.add(const Duration(seconds: 10)),
    outlook: outlook,
    sqm: sqm,
    overridden: overrides.any,
  );
}

/// Phone held still enough for long frames: the camera's direction over
/// the last moments moved less than [toleranceDeg].
bool isSteady(List<SkyDir> recent, {double toleranceDeg = 0.4}) {
  if (recent.length < 5) return false;
  final first = recent.first;
  return recent.every((d) => angularDistanceDeg(first, d) <= toleranceDeg);
}

/// How far the picture's right-hand edge rises above level, degrees, from
/// the phone's rotation matrix (row-major device→world, as in
/// pointing.dart). [quarterTurns] is how the phone is held: 0 upright, 1 on
/// its side with the top to the left, 3 with the top to the right. The
/// picture's right edge is then the phone's right side (device +x), its
/// bottom (device −y) or its top (device +y).
double tiltDeg(List<double> r, {int quarterTurns = 0}) {
  final z = switch (quarterTurns % 4) { 1 => -r[7], 3 => r[7], 2 => -r[6], _ => r[6] };
  return math.asin(z.clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// How the phone is held, from its rotation matrix: 0 upright, 1 on its
/// side top-left, 3 top-right, 2 upside down. Near flat, upright.
int heldQuarterTurns(List<double> r) {
  final xUp = r[6], yUp = r[7];
  if (xUp.abs() < 0.55 && yUp.abs() < 0.55) return 0;
  if (xUp.abs() > yUp.abs()) return xUp > 0 ? 1 : 3;
  return yUp > 0 ? 0 : 2;
}

/// Words for a tilt, null when level enough: a crooked horizon spoils the
/// picture.
String? levelWords(double tilt) {
  if (tilt.abs() <= 2) return null;
  final low = tilt > 0 ? 'left' : 'right';
  return tilt.abs() > 10 ? 'Level it: the $low side is low' : 'Nearly level: lift the $low side a touch';
}
