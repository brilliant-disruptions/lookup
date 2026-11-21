/// The Pro camera's stacks, the other three ways frames become one
/// picture (the pass streak is streak_stacker.dart):
///
///  * average: a short run of frames averaged, so noise falls away and the
///    stars stay points;
///  * lighten: each pixel's brightest across every frame, for star trails
///    and meteors;
///  * sharpest: the steadiest few of many quick frames averaged (the air
///    shimmers, and some frames catch the Moon still).
///
/// Luma at full size, chroma at half, as phones deliver frames. Pure Dart.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'shot_plan.dart' show StackKind;

/// How sharp a frame is: the spread of its edges (the variance of a
/// Laplacian over every [step]th pixel). Higher is sharper. Only worth
/// comparing between frames of the same scene.
double sharpness(Uint8List y, int width, {int step = 2}) {
  final height = y.length ~/ width;
  var n = 0;
  var sum = 0.0, sumSq = 0.0;
  for (var yy = 1; yy < height - 1; yy += step) {
    final row = yy * width;
    for (var xx = 1; xx < width - 1; xx += step) {
      final i = row + xx;
      final l = (4 * y[i] - y[i - 1] - y[i + 1] - y[i - width] - y[i + width]).toDouble();
      sum += l;
      sumSq += l * l;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

class FrameStack {
  FrameStack(this.kind, this.width, this.height, {this.keep = 10})
      : assert(kind != StackKind.streak, 'The streak has its own stacker.'),
        _y = Float32List(width * height),
        _u = Float32List((width ~/ 2) * (height ~/ 2)),
        _v = Float32List((width ~/ 2) * (height ~/ 2));

  final StackKind kind;
  final int width, height;

  /// For [StackKind.sharpest]: how many of the sharpest frames are kept.
  final int keep;

  final Float32List _y, _u, _v;
  int _frames = 0, _chroma = 0;

  /// The sharpest so far, sharpest first.
  final _best = <({double score, Uint8List y, Uint8List? u, Uint8List? v})>[];

  int get frames => _frames;

  void add(Uint8List y, {Uint8List? u, Uint8List? v}) {
    if (y.length != width * height) return;
    _frames++;
    switch (kind) {
      case StackKind.sharpest:
        final s = sharpness(y, width);
        if (_best.length < keep || s > _best.last.score) {
          _best
            ..add((score: s, y: y, u: u, v: v))
            ..sort((a, b) => b.score.compareTo(a.score));
          if (_best.length > keep) _best.removeLast();
        }
      case StackKind.lighten:
        for (var i = 0; i < _y.length; i++) {
          if (y[i] > _y[i]) _y[i] = y[i].toDouble();
        }
        // The colour goes with the brightest: keep a running mean, enough
        // for trails that are mostly white.
        _addChroma(u, v);
      case StackKind.average || StackKind.streak:
        for (var i = 0; i < _y.length; i++) {
          _y[i] += y[i];
        }
        _addChroma(u, v);
    }
  }

  void _addChroma(Uint8List? u, Uint8List? v) {
    if (u == null || v == null || u.length != _u.length || v.length != _v.length) return;
    for (var i = 0; i < _u.length; i++) {
      _u[i] += u[i];
      _v[i] += v[i];
    }
    _chroma++;
  }

  /// The picture's luma and chroma (chroma null when no frame had any).
  ({Uint8List y, Uint8List? u, Uint8List? v}) planes() {
    Uint8List bytes(Float32List f, double div) {
      final out = Uint8List(f.length);
      for (var i = 0; i < f.length; i++) {
        final x = f[i] / div;
        out[i] = x <= 0 ? 0 : (x >= 255 ? 255 : x.round());
      }
      return out;
    }

    if (kind == StackKind.sharpest) {
      if (_best.isEmpty) return (y: Uint8List(width * height), u: null, v: null);
      final y = Float32List(width * height), u = Float32List(_u.length), v = Float32List(_v.length);
      var c = 0;
      for (final f in _best) {
        for (var i = 0; i < y.length; i++) {
          y[i] += f.y[i];
        }
        if (f.u != null && f.v != null && f.u!.length == u.length) {
          for (var i = 0; i < u.length; i++) {
            u[i] += f.u![i];
            v[i] += f.v![i];
          }
          c++;
        }
      }
      return (y: bytes(y, _best.length.toDouble()), u: c == 0 ? null : bytes(u, c.toDouble()), v: c == 0 ? null : bytes(v, c.toDouble()));
    }
    final ly = kind == StackKind.lighten ? bytes(_y, 1) : bytes(_y, math.max(1, _frames).toDouble());
    if (_chroma == 0) return (y: ly, u: null, v: null);
    return (y: ly, u: bytes(_u, _chroma.toDouble()), v: bytes(_v, _chroma.toDouble()));
  }

  /// The picture as RGBA, turned [quarterTurns] clockwise.
  ({Uint8List rgba, int width, int height}) rgba({int quarterTurns = 0, int scale = 1}) {
    final p = planes();
    return yuvToRgba(p.y, p.u, p.v, width, height, quarterTurns: quarterTurns, scale: scale);
  }
}

/// Full-range BT.601 YUV 4:2:0 to RGBA (as phone cameras deliver it),
/// turned [quarterTurns] clockwise and shrunk by [scale].
({Uint8List rgba, int width, int height}) yuvToRgba(Uint8List y, Uint8List? u, Uint8List? v, int width, int height,
    {int quarterTurns = 0, int scale = 1}) {
  final hw = width ~/ 2, hh = height ~/ 2;
  final sw = width ~/ scale, sh = height ~/ scale;
  final turns = quarterTurns % 4;
  final ow = turns.isOdd ? sh : sw, oh = turns.isOdd ? sw : sh;
  final out = Uint8List(ow * oh * 4);
  int byte(double x) => x <= 0 ? 0 : (x >= 255 ? 255 : x.round());
  for (var sy = 0; sy < sh; sy++) {
    final int py = sy * scale;
    for (var sx = 0; sx < sw; sx++) {
      final int px = sx * scale;
      final l = y[py * width + px].toDouble();
      double cb = 0, cr = 0;
      if (u != null && v != null) {
        final int ci = math.min(py ~/ 2, hh - 1) * hw + math.min(px ~/ 2, hw - 1);
        cb = u[ci] - 128.0;
        cr = v[ci] - 128.0;
      }
      final (ox, oy) = switch (turns) {
        0 => (sx, sy),
        1 => (sh - 1 - sy, sx),
        2 => (sw - 1 - sx, sh - 1 - sy),
        _ => (sy, sw - 1 - sx),
      };
      final o = (oy * ow + ox) * 4;
      out[o] = byte(l + 1.402 * cr);
      out[o + 1] = byte(l - 0.344136 * cb - 0.714136 * cr);
      out[o + 2] = byte(l + 1.772 * cb);
      out[o + 3] = 255;
    }
  }
  return (rgba: out, width: ow, height: oh);
}
