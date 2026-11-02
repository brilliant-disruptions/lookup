/// Shutter speed and ISO for photographing a pass, from how bright the sky
/// is and how bright and fast the satellite is. Pure Dart.
///
/// The idea the whole plan rests on: a satellite crosses each pixel in a
/// few hundredths of a second, so a longer shutter does not make its streak
/// any brighter, only the sky behind it. So the *sky* sets the shutter and
/// the *streak* sets the ISO. Many back-to-back frames are then stacked
/// (see streak_stacker.dart) into one long exposure.
///
/// The photometry is a photographer's rule of thumb, not a sensor model:
/// at a natural dark site (21.5 mag/arcsec²) f/2.8, ISO 3200 and 20 s put
/// the sky at about a quarter of the histogram, and a phone's main camera
/// at f/1.8, ISO 800 and 1 s shows stars to about magnitude 4. Good to a
/// stop or so, which is all a plan needs: the picture is checked live.
library;

import 'dart:math' as math;

import '../sky/visibility.dart';

/// Typical zenith sky brightness (mag/arcsec²) for the darkness setting,
/// used when the sky glow map has nothing for the spot.
double typicalSqm(SkyDarkness d) => switch (d) {
      SkyDarkness.city => 18.0,
      SkyDarkness.suburbs => 19.8,
      SkyDarkness.dark => 21.4,
    };

/// The light twilight adds to the sky (mag/arcsec²): none once the Sun is
/// 18° down (infinity), bright blue at sunset. Rough.
double twilightSqm(double sunAltDeg) {
  if (sunAltDeg <= -18) return double.infinity;
  const pts = [(-18.0, 24.5), (-15.0, 21.5), (-12.0, 19.5), (-9.0, 17.0), (-6.0, 14.5), (-3.0, 12.0), (0.0, 9.5)];
  if (sunAltDeg <= pts.first.$1) return pts.first.$2;
  if (sunAltDeg >= pts.last.$1) return pts.last.$2;
  for (var i = 1; i < pts.length; i++) {
    final (a0, m0) = pts[i - 1];
    final (a1, m1) = pts[i];
    if (sunAltDeg <= a1) return m0 + (m1 - m0) * (sunAltDeg - a0) / (a1 - a0);
  }
  return pts.last.$2;
}

/// Moonlight on the sky (mag/arcsec²): a high full Moon brightens even a
/// dark site to about 18. Infinity (no light) when it's down.
double moonSqm({required double illumination, required double altDeg}) {
  if (altDeg <= 0 || illumination <= 0.02) return double.infinity;
  final f = illumination * math.sin(math.min(altDeg, 60) * math.pi / 180) / math.sin(60 * math.pi / 180);
  return 18.0 - 2.5 * math.log(f) / math.ln10;
}

/// The sky's brightness, all sources added as light.
double skySqm({required double siteSqm, required double sunAltDeg, double moonIllumination = 0, double moonAltDeg = -90}) {
  double flux(double m) => m.isInfinite ? 0 : math.pow(10, -0.4 * m).toDouble();
  final total = flux(siteSqm) + flux(twilightSqm(sunAltDeg)) + flux(moonSqm(illumination: moonIllumination, altDeg: moonAltDeg));
  return -2.5 * math.log(total) / math.ln10;
}

/// Shutter × ISO / f² that puts a [sqm] sky at about a quarter of the
/// histogram: bright enough to show the land and stars, dark enough that
/// the streak stands out.
double skyExposureIndex(double sqm) => 8000 * math.pow(10, 0.4 * (sqm - 21.5)).toDouble();

/// Faintest steady star a frame shows at [iso] and [fNumber] for 1 s, under
/// a [sqm] sky (bright skies drown faint points).
double pointLimitMag({required int iso, required double fNumber, required double sqm}) {
  final gain = (iso / (fNumber * fNumber)) / (800 / (1.8 * 1.8));
  final camera = 4.0 + 2.5 * math.log(gain) / math.ln10;
  return math.min(camera, sqm - 15.0);
}

/// A moving point of magnitude [mag] lights each pixel for only
/// [pixelScaleDeg] / [speedDegPerS] seconds: as faint, per pixel, as a
/// steady star this much fainter over 1 s.
double movingEquivalentMag({required double mag, required double speedDegPerS, required double pixelScaleDeg}) {
  final dwell = pixelScaleDeg / math.max(speedDegPerS, 0.01);
  return mag - 2.5 * math.log(math.min(dwell, 1.0)) / math.ln10;
}

enum StreakOutlook {
  /// A clear, bright line.
  strong,

  /// A thin, dim line: a darker sky or the main lens helps.
  faint,

  /// Probably nothing a phone can record.
  tooFaint,
}

class Exposure {
  const Exposure({required this.shutterS, required this.iso});
  final double shutterS;
  final int iso;

  @override
  String toString() => 'Exposure(${shutterLabel(shutterS)}, ISO $iso)';
}

/// Shutter as photographers write it: "1/4 s", "1 s", "2.5 s".
String shutterLabel(double s) {
  if (s >= 1) return '${s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1)} s';
  return '1/${(1 / s).round()} s';
}

/// Longest single frame worth taking: past this, stars start to trail
/// within a frame and a passing car's lights ruin more of the stack.
const maxUsefulShutterS = 2.0;

/// ISO steps tried for the streak, lowest (least noise) first.
const isoSteps = [400, 800, 1600, 3200];

/// Settings for a pass of magnitude [mag] moving up to [speedDegPerS],
/// under a [sqm] sky, at [fNumber] with [pixelScaleDeg] per pixel, within
/// what the camera allows.
({Exposure exposure, StreakOutlook outlook, double margin}) exposureFor({
  required double mag,
  required double speedDegPerS,
  required double sqm,
  required double fNumber,
  required double pixelScaleDeg,
  required double minShutterS,
  required double maxShutterS,
  required int minIso,
  required int maxIso,
}) {
  final eq = movingEquivalentMag(mag: mag, speedDegPerS: speedDegPerS, pixelScaleDeg: pixelScaleDeg);
  // Lowest ISO that makes a clear streak (1.5 mag of headroom), else the
  // highest the camera has.
  final steps = [for (final s in isoSteps) if (s >= minIso && s <= maxIso) s];
  if (steps.isEmpty) steps.add(maxIso.clamp(minIso, maxIso));
  var iso = steps.last;
  for (final s in steps) {
    if (pointLimitMag(iso: s, fNumber: fNumber, sqm: sqm) - eq >= 1.5) {
      iso = s;
      break;
    }
  }
  // The sky sets the shutter.
  final longest = math.min(maxShutterS, maxUsefulShutterS);
  var shutter = skyExposureIndex(sqm) * fNumber * fNumber / iso;
  if (shutter < minShutterS) {
    // Too bright even at the fastest shutter: drop the ISO instead.
    shutter = minShutterS;
    iso = (skyExposureIndex(sqm) * fNumber * fNumber / shutter).round().clamp(minIso, maxIso);
  }
  if (shutter > longest) {
    // A dark sky wants more than the longest frame: brighten with ISO (up
    // to 1600, where phone noise is still kind), never below the streak's.
    final skyIso = (skyExposureIndex(sqm) * fNumber * fNumber / longest).round();
    final cap = math.min(1600, maxIso);
    if (skyIso > iso) iso = math.max(iso, steps.lastWhere((s) => s <= math.min(skyIso, cap), orElse: () => iso));
    shutter = longest;
  }
  shutter = math.max(_niceShutter(shutter.clamp(minShutterS, longest)), minShutterS);
  final margin = pointLimitMag(iso: iso, fNumber: fNumber, sqm: sqm) - eq;
  final outlook = margin >= 1.0
      ? StreakOutlook.strong
      : margin >= -0.5
          ? StreakOutlook.faint
          : StreakOutlook.tooFaint;
  return (exposure: Exposure(shutterS: shutter, iso: iso), outlook: outlook, margin: margin);
}

/// Rounds down to a familiar stop (1/30, 1/15, 1/8, 1/4, 1/2, 1, 1.5, 2 s).
double _niceShutter(double s) {
  const stops = [1 / 30, 1 / 15, 1 / 8, 1 / 4, 1 / 2, 1.0, 1.5, 2.0];
  var best = s;
  for (final st in stops) {
    if (st <= s + 1e-9) best = st;
  }
  return s < stops.first ? s : best;
}
