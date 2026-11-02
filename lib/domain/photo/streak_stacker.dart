/// Many short frames in, one long exposure out: the satellite's streak
/// unbroken across the sky, the stars still points, the noise of one frame
/// smoothed away. Pure Dart, so it runs in an isolate, in tests, and on the
/// practice run's made-up sky alike.
///
/// A plain "lighten" stack (keep each pixel's brightest value) makes the
/// streak, but over hundreds of frames it also keeps every pixel's
/// brightest *noise*, greying the sky, and it smears the stars into trails
/// as the Earth turns. So instead:
///
///  * the picture's base is the per-pixel median of the first few frames —
///    less noise, no satellite in it, and the stars barely move in that time;
///  * each frame is compared with a slowly updated background; only what is
///    clearly brighter than it (several times the frame's own noise) counts
///    as something moving, and the brightest of that is kept: the streak.
///    The stars drift too slowly to count, the noise is too small to count.
///
/// Works on luma (Y) at full size and chroma (U, V) at half size, the way
/// phone cameras deliver frames (YUV 4:2:0).
library;

import 'dart:math' as math;
import 'dart:typed_data';

class StreakStacker {
  StreakStacker(this.width, this.height, {this.baseFrames = 5, this.backgroundRate = 0.3, this.noiseSigmas = 4.0})
      : assert(width > 1 && height > 1),
        _base = Uint8List(width * height),
        _bg = Float32List(width * height),
        _streak = Uint8List(width * height),
        _u = Uint16List((width ~/ 2) * (height ~/ 2)),
        _v = Uint16List((width ~/ 2) * (height ~/ 2));

  final int width, height;

  /// How many frames the base picture is the median of: enough to drop the
  /// satellite out of it (it's in each spot for one frame), few enough that
  /// the stars haven't moved.
  final int baseFrames;

  /// How fast the background follows the frames (0–1 per frame).
  final double backgroundRate;

  /// How far above the background (in units of the frame's noise) a pixel
  /// must be to count as the moving thing.
  final double noiseSigmas;

  final Uint8List _base;
  final Float32List _bg;
  final Uint8List _streak;
  final Uint16List _u, _v;
  final _first = <Uint8List>[];
  bool _baseDone = false;
  int _frames = 0, _chromaCount = 0;
  double _lastNoise = 0;

  int get frameCount => _frames;

  /// The last frame's noise estimate, in luma levels.
  double get noise => _lastNoise;

  /// Adds one frame. [y] is width×height luma; [u] and [v], when given, are
  /// (width/2)×(height/2) chroma. Rows must be tightly packed.
  void add(Uint8List y, {Uint8List? u, Uint8List? v}) {
    final n = width * height;
    if (y.length < n) throw ArgumentError('Frame is ${y.length} bytes, expected $n');
    _frames++;
    if (!_baseDone) {
      _first.add(Uint8List.fromList(y.sublist(0, n)));
      if (u != null && v != null && u.length >= _u.length && v.length >= _v.length) {
        for (var i = 0; i < _u.length; i++) {
          _u[i] += u[i];
          _v[i] += v[i];
        }
        _chromaCount++;
      }
      if (_first.length >= baseFrames) _settleBase();
      return;
    }
    _accumulate(y);
  }

  /// Base = per-pixel median of the first frames; then those frames are
  /// searched for the moving thing like every later one.
  void _settleBase() {
    if (_baseDone || _first.isEmpty) return;
    final n = width * height;
    final k = _first.length;
    final vals = List<int>.filled(k, 0);
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < k; j++) {
        vals[j] = _first[j][i];
      }
      vals.sort();
      final m = k.isOdd ? vals[k ~/ 2] : (vals[k ~/ 2 - 1] + vals[k ~/ 2]) ~/ 2;
      _base[i] = m;
      _bg[i] = m.toDouble();
    }
    _baseDone = true;
    final frames = List.of(_first);
    _first.clear();
    for (final f in frames) {
      _accumulate(f, updateBackground: false);
    }
  }

  void _accumulate(Uint8List y, {bool updateBackground = true}) {
    final n = width * height;
    final sigma = _noise(y);
    _lastNoise = sigma;
    final threshold = noiseSigmas * sigma + 3;
    final a = backgroundRate;
    for (var i = 0; i < n; i++) {
      final bg = _bg[i];
      final r = y[i] - bg;
      if (r > threshold && r > _streak[i]) _streak[i] = r > 255 ? 255 : r.toInt();
      // Follows slow change and dimming; a bright thing passing barely
      // drags it up.
      if (updateBackground) _bg[i] = r > threshold ? bg + a * 0.1 * r : bg + a * r;
    }
  }

  /// Robust noise of a frame against the background: 1.48 × the median
  /// absolute difference, sampled across the picture.
  double _noise(Uint8List y) {
    final n = width * height;
    final step = math.max(1, n ~/ 4096) | 1;
    final diffs = <double>[];
    for (var i = step ~/ 2; i < n; i += step) {
      diffs.add((y[i] - _bg[i]).abs());
    }
    diffs.sort();
    return diffs.isEmpty ? 0 : 1.4826 * diffs[diffs.length ~/ 2];
  }

  /// The picture so far: base plus streak, luma.
  Uint8List luma() {
    _settleBase();
    final n = width * height;
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final v = _base[i] + _streak[i];
      out[i] = v > 255 ? 255 : v.round();
    }
    return out;
  }

  /// Just the streak layer (what moved), luma.
  Uint8List streak() {
    _settleBase();
    return Uint8List.fromList(_streak);
  }

  /// The picture as RGBA, rotated by [quarterTurns] clockwise and shrunk by
  /// [scale] (1 = full size, 4 = every fourth pixel).
  ({Uint8List rgba, int width, int height}) rgba({int quarterTurns = 0, int scale = 1}) {
    final yy = luma();
    final c = math.max(1, _chromaCount);
    final hw = width ~/ 2, hh = height ~/ 2;
    final sw = width ~/ scale, sh = height ~/ scale;
    final turns = quarterTurns % 4;
    final ow = turns.isOdd ? sh : sw, oh = turns.isOdd ? sw : sh;
    final out = Uint8List(ow * oh * 4);
    for (var sy = 0; sy < sh; sy++) {
      final py = sy * scale;
      for (var sx = 0; sx < sw; sx++) {
        final px = sx * scale;
        final l = yy[py * width + px].toDouble();
        double cb = 0, cr = 0;
        if (_chromaCount > 0) {
          final int cy = py ~/ 2 < hh ? py ~/ 2 : hh - 1, cx = px ~/ 2 < hw ? px ~/ 2 : hw - 1;
          final ci = cy * hw + cx;
          cb = _u[ci] / c - 128;
          cr = _v[ci] / c - 128;
        }
        // Full-range BT.601, as phone cameras deliver it.
        final r = l + 1.402 * cr, g = l - 0.344136 * cb - 0.714136 * cr, b = l + 1.772 * cb;
        final (ox, oy) = switch (turns) {
          0 => (sx, sy),
          1 => (sh - 1 - sy, sx),
          2 => (sw - 1 - sx, sh - 1 - sy),
          _ => (sy, sw - 1 - sx),
        };
        final o = (oy * ow + ox) * 4;
        out[o] = _byte(r);
        out[o + 1] = _byte(g);
        out[o + 2] = _byte(b);
        out[o + 3] = 255;
      }
    }
    return (rgba: out, width: ow, height: oh);
  }

  static int _byte(double v) => v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
}
