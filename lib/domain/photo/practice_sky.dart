/// A made-up camera for the practice run, the previews and the tests: the
/// frames a propped-up phone would record of a pass, with the real stars
/// for the place and time, the sky's glow, a treeline, sensor noise and the
/// satellite crossing where the prediction says. Pure Dart.
///
/// Brightness follows the same rules of thumb as exposure.dart, so a pass
/// the plan calls faint looks faint here too.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../finder/pointing.dart';
import '../sky/catalog.dart';
import 'exposure.dart';
import 'framing.dart';

class PracticeSky {
  PracticeSky({
    required this.framing,
    required this.path,
    required this.magnitude,
    required this.exposure,
    required this.sqm,
    required this.latDeg,
    required this.lonDeg,
    this.catalog,
    this.width = 720,
    int seed = 7,
  })  : height = (width * framing.heightFovDeg / framing.widthFovDeg).round() & ~1,
        _rng = math.Random(seed) {
    _buildScene();
  }

  final Framing framing;
  final List<PathPoint> path;
  final double magnitude;
  final Exposure exposure;
  final double sqm;
  final double latDeg, lonDeg;
  final SkyCatalog? catalog;
  final int width;
  final int height;
  final math.Random _rng;

  late final Float32List _sky; // background level per pixel
  late final Uint8List _ground; // 1 = land
  late final Uint8List _u, _v;
  late final Float32List _gauss;
  late final double _sigma, _pointUnit;
  int _gi = 0;

  double get _fNumber => framing.lens.fNumber;

  /// Light gathered relative to the plan's sky target.
  double get _gain => exposure.shutterS * exposure.iso / (_fNumber * _fNumber);

  void _buildScene() {
    final n = width * height;
    _sky = Float32List(n);
    _ground = Uint8List(n);
    _u = Uint8List((width ~/ 2) * (height ~/ 2));
    _v = Uint8List((width ~/ 2) * (height ~/ 2));
    // The sky at a quarter of the histogram when exposed as planned.
    final level = (64 * _gain / skyExposureIndex(sqm)).clamp(2.0, 230.0);
    final hx = math.tan(framing.widthFovDeg / 2 * math.pi / 180);
    final hy = math.tan(framing.heightFovDeg / 2 * math.pi / 180);
    final c = framing.center;
    const k = math.pi / 180;
    final az0 = c.azimuthDeg * k, el0 = c.elevationDeg * k;
    final f = (math.cos(el0) * math.sin(az0), math.cos(el0) * math.cos(az0), math.sin(el0));
    final r = (math.cos(az0), -math.sin(az0), 0.0);
    final u = (-math.sin(el0) * math.sin(az0), -math.sin(el0) * math.cos(az0), math.cos(el0));
    final glowWarm = sqm < 20.5; // towns glow orange; dark skies stay blue-black
    for (var py = 0; py < height; py++) {
      final ty = (0.5 - (py + 0.5) / height) * 2 * hy;
      for (var px = 0; px < width; px++) {
        final tx = ((px + 0.5) / width - 0.5) * 2 * hx;
        // Ray through the pixel → altitude and azimuth.
        final wx = f.$1 + tx * r.$1 + ty * u.$1, wy = f.$2 + tx * r.$2 + ty * u.$2, wz = f.$3 + tx * r.$3 + ty * u.$3;
        final len = math.sqrt(wx * wx + wy * wy + wz * wz);
        final el = math.asin(wz / len) / k;
        final az = (math.atan2(wx, wy) / k + 360) % 360;
        final i = py * width + px;
        final tree = _treeline(az);
        if (el < tree) {
          _ground[i] = 1;
          _sky[i] = level * 0.18;
        } else {
          _sky[i] = level * (1 + 1.6 * math.exp(-math.max(el, 0) / 9));
        }
        if (py.isEven && px.isEven) {
          final ci = (py ~/ 2) * (width ~/ 2) + px ~/ 2;
          final near = math.exp(-math.max(el, 0) / 14);
          _u[ci] = (glowWarm ? 128 - 14 * near : 131 + 4 * (1 - near)).round();
          _v[ci] = (glowWarm ? 128 + 16 * near : 127 + 3 * near).round();
        }
      }
    }
    _sigma = 1.6 + 0.35 * math.sqrt(level);
    // A steady 1 s star at the camera's limit sits 3σ above the sky.
    _pointUnit = 3 * _sigma;
    _gauss = Float32List(1 << 16);
    for (var i = 0; i < _gauss.length; i += 2) {
      final a = math.max(_rng.nextDouble(), 1e-9), b = _rng.nextDouble();
      final m = math.sqrt(-2 * math.log(a));
      _gauss[i] = m * math.cos(2 * math.pi * b);
      _gauss[i + 1] = m * math.sin(2 * math.pi * b);
    }
  }

  /// Rooftops and trees along the bottom, a few degrees high.
  double _treeline(double az) {
    final a = az * math.pi / 180;
    return 1.2 + 1.1 * math.sin(a * 7 + 1) + 0.8 * math.sin(a * 23 + 2).abs() + 0.9 * math.max(0, math.sin(a * 3.3));
  }

  double get limitMag => pointLimitMag(iso: exposure.iso, fNumber: _fNumber, sqm: sqm);

  /// One frame's luma and chroma, the shutter opening at [t].
  ({Uint8List y, Uint8List u, Uint8List v}) frameAt(DateTime t) {
    final n = width * height;
    final img = Float32List(n);
    for (var i = 0; i < n; i++) {
      img[i] = _sky[i];
    }
    final lim = limitMag;
    final shutter = exposure.shutterS;
    // Stars: as bright as the exposure makes them; scintillation a little.
    final cat = catalog;
    if (cat != null) {
      for (final s in cat.stars) {
        if (s.mag > lim + 0.8) break;
        final h = cat.place(s.raDeg, s.decDeg, t, latDeg, lonDeg);
        if (h.altitudeDeg < 0) continue;
        final p = framing.toPicture(SkyDir(h.azimuthDeg, h.altitudeDeg));
        if (p == null || p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) continue;
        final peak = _pointUnit * math.pow(10, -0.4 * (s.mag - lim)) * math.min(shutter, 2.0) * (0.85 + 0.3 * _rng.nextDouble());
        _splat(img, p.x * width, p.y * height, peak.toDouble());
      }
    }
    // The satellite, drawn along where it goes while the shutter is open.
    final a = _pathAt(t), b = _pathAt(t.add(Duration(microseconds: (shutter * 1e6).round())));
    if (a != null && b != null) {
      final pa = framing.toPicture(a), pb = framing.toPicture(b);
      if (pa != null && pb != null) {
        final x0 = pa.x * width, y0 = pa.y * height, x1 = pb.x * width, y1 = pb.y * height;
        final lenPx = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
        final speed = angularDistanceDeg(a, b) / shutter;
        final eq = movingEquivalentMag(mag: magnitude, speedDegPerS: speed, pixelScaleDeg: framing.widthFovDeg / width);
        final per = _pointUnit * math.pow(10, -0.4 * (eq - lim)).toDouble();
        final steps = math.max(1, (lenPx * 2).ceil());
        for (var s = 0; s <= steps; s++) {
          final f = s / steps;
          _splat(img, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, per / 2);
        }
      }
    }
    final y = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final g = _gauss[_gi = (_gi + 1) & 0xFFFF];
      final v = (_ground[i] == 1 && img[i] > _sky[i] ? _sky[i] : img[i]) + g * _sigma;
      y[i] = v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
    }
    _gi = (_gi + _rng.nextInt(4096)) & 0xFFFF;
    return (y: y, u: _u, v: _v);
  }

  SkyDir? _pathAt(DateTime t) {
    if (path.isEmpty || t.isBefore(path.first.t) || t.isAfter(path.last.t)) return null;
    for (var i = 1; i < path.length; i++) {
      final p0 = path[i - 1], p1 = path[i];
      if (t.isAfter(p1.t)) continue;
      final span = p1.t.difference(p0.t).inMicroseconds;
      final f = span == 0 ? 0.0 : t.difference(p0.t).inMicroseconds / span;
      if (p0.d.elevationDeg < 0 && p1.d.elevationDeg < 0) return null;
      var daz = p1.d.azimuthDeg - p0.d.azimuthDeg;
      if (daz > 180) daz -= 360;
      if (daz < -180) daz += 360;
      return SkyDir((p0.d.azimuthDeg + daz * f + 360) % 360, p0.d.elevationDeg + (p1.d.elevationDeg - p0.d.elevationDeg) * f);
    }
    return null;
  }

  /// A small soft point: most light in the middle pixel, some around it.
  void _splat(Float32List img, double x, double y, double peak) {
    final cx = x.floor(), cy = y.floor();
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final px = cx + dx, py = cy + dy;
        if (px < 0 || py < 0 || px >= width || py >= height) continue;
        final ddx = px + 0.5 - x, ddy = py + 0.5 - y;
        final w = math.exp(-(ddx * ddx + ddy * ddy) / 0.9);
        img[py * width + px] += peak * w;
      }
    }
  }
}
