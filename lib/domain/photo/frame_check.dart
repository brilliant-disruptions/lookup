/// Looking at what the camera actually sees, frame by frame, so the Pro
/// camera can help: is the picture too bright or too dark for this subject
/// (and by how much), and did that frame catch a meteor? Works on luma (Y),
/// the way phones deliver frames. Pure Dart.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'shot_plan.dart';

enum ExposureVerdict { good, tooBright, tooDark }

/// What a frame says about the exposure: a verdict, how many stops to
/// move (positive brighter), and the words for it.
class ExposureCheck {
  const ExposureCheck(this.verdict, this.stops, this.words);
  final ExposureVerdict verdict;
  final double stops;
  final String words;

  static const good = ExposureCheck(ExposureVerdict.good, 0, 'Exposure looks right');
}

/// Luma levels at the [ps] fractions (0–1) of a frame, sampling every
/// [step]th pixel.
List<int> lumaPercentiles(Uint8List y, List<double> ps, {int step = 4}) {
  final hist = List<int>.filled(256, 0);
  var n = 0;
  for (var i = 0; i < y.length; i += step) {
    hist[y[i]]++;
    n++;
  }
  return [
    for (final p in ps)
      () {
        final target = (p * n).clamp(0, n - 1);
        var seen = 0;
        for (var v = 0; v < 256; v++) {
          seen += hist[v];
          if (seen > target) return v;
        }
        return 255;
      }(),
  ];
}

/// Checks one frame of [subject]. For the Moon it's the bright part that
/// matters (its craters vanish once they clip); for everything else it's
/// the sky, which should sit low but off the floor so stars show over it.
ExposureCheck checkExposure(Uint8List y, ShotSubject subject) {
  if (y.isEmpty) return ExposureCheck.good;
  if (subject == ShotSubject.moon || subject == ShotSubject.planet) {
    final [p999, top] = lumaPercentiles(y, const [0.999, 0.9999]);
    if (top >= 254 && p999 >= 245) {
      return const ExposureCheck(ExposureVerdict.tooBright, -1, 'Too bright: the Moon is losing its detail. LookUp is darkening it.');
    }
    if (top < 120) {
      return ExposureCheck(ExposureVerdict.tooDark, math.min(2, math.log(200 / math.max(top, 8)) / math.ln2).toDouble(),
          'Too dark: bring the Moon into the picture, or LookUp brightens it.');
    }
    return ExposureCheck.good;
  }
  final [median] = lumaPercentiles(y, const [0.5]);
  if (median > 110) {
    return ExposureCheck(ExposureVerdict.tooBright, -math.min(2, math.log(median / 50) / math.ln2).toDouble(),
        'The sky is washing out: LookUp is shortening the frames. A darker spot helps more.');
  }
  if (median < 10) {
    return ExposureCheck(ExposureVerdict.tooDark, math.min(2, math.log(30 / math.max(median, 2)) / math.ln2).toDouble(),
        'Very dark: LookUp is brightening it. Check nothing covers the lens.');
  }
  return ExposureCheck.good;
}

/// Whether [cur] caught a meteor that [prev] didn't: a thin, bright line
/// that wasn't there a frame ago. Not a flash of the whole frame (a car's
/// lights, a cloud lit by a town), and not a lone hot pixel. [width] is the
/// frame's width; [threshold] how much brighter (luma levels) counts.
bool caughtStreak(Uint8List prev, Uint8List cur, int width, {int threshold = 40}) {
  if (prev.length != cur.length || width <= 0) return false;
  final height = cur.length ~/ width;
  var count = 0;
  var minX = width, maxX = -1, minY = height, maxY = -1;
  // Sum of x, y, xx, yy, xy for the line's shape.
  var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (var yy = 0; yy < height; yy += 2) {
    final row = yy * width;
    for (var xx = 0; xx < width; xx += 2) {
      final i = row + xx;
      if (cur[i] - prev[i] < threshold) continue;
      count++;
      if (xx < minX) minX = xx;
      if (xx > maxX) maxX = xx;
      if (yy < minY) minY = yy;
      if (yy > maxY) maxY = yy;
      sx += xx;
      sy += yy;
      sxx += xx * xx;
      syy += yy * yy;
      sxy += xx * yy;
    }
  }
  final sampled = (width / 2).ceil() * (height / 2).ceil();
  // A line, not most of the frame lighting up (a flash, a cloud lit by a town).
  if (count < 8 || count > math.max(200, sampled * 0.01)) return false;
  // Elongation from the spread along and across the line (the covariance's
  // two eigenvalues): a streak is long and thin.
  final mx = sx / count, my = sy / count;
  final cxx = sxx / count - mx * mx, cyy = syy / count - my * my, cxy = sxy / count - mx * my;
  final tr = cxx + cyy, det = cxx * cyy - cxy * cxy;
  final disc = math.sqrt(math.max(0, tr * tr / 4 - det));
  final along = tr / 2 + disc, across = math.max(tr / 2 - disc, 0.25);
  final length = math.max(maxX - minX, maxY - minY);
  return along / across >= 16 && length >= 20;
}
