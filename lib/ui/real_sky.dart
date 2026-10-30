/// The real sky behind the app: the stars above you right now, the faint
/// figures of the constellations, and the Moon where it is, lit on the side
/// facing the Sun. Turns with the Earth, a little each minute. Before
/// there's a location (onboarding) it's the old random scatter.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sky/astro.dart';
import '../domain/sky/backdrop.dart';
import '../domain/sky/catalog.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';

import 'kit/starfield.dart';

class RealSky extends ConsumerWidget {
  const RealSky({super.key, this.maxOpacity = 0.6});
  final double maxOpacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final catalog = ref.watch(skyCatalogProvider).value;
    // The app's clock, but only rebuilt when the minute turns.
    final minute = ref.watch(clockProvider.select((c) => c.value == null ? null : c.value!.millisecondsSinceEpoch ~/ 60000));
    final now = minute == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(minute * 60000);
    final lat = s?.latitude, lon = s?.longitude;
    if (lat == null || lon == null || catalog == null || catalog.stars.isEmpty) {
      return Starfield(density: 0.00028, maxOpacity: maxOpacity);
    }
    final sky = _BackdropSky.at(catalog, now.toUtc(), lat, lon);
    return IgnorePointer(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.transparent],
          stops: [0.05, 0.62],
        ).createShader(r),
        child: CustomPaint(painter: _RealSkyPainter(sky, maxOpacity), child: const SizedBox.expand()),
      ),
    );
  }
}

/// Where everything is in projection units, worked out once a minute for
/// a place and shared by every tab that shows it.
class _BackdropSky {
  _BackdropSky(this.stars, this.lines, this.moon);
  final List<({double x, double y, double mag, double? bv})> stars;
  final List<(({double x, double y}), ({double x, double y}))> lines;
  final ({double x, double y, double lit, double towardSun})? moon;

  static _BackdropSky? _last;
  static (int, double, double)? _lastKey;

  factory _BackdropSky.at(SkyCatalog catalog, DateTime utc, double lat, double lon) {
    final key = (utc.millisecondsSinceEpoch ~/ 60000, lat, lon);
    final cached = _last;
    if (cached != null && _lastKey == key) return cached;
    final az0 = backdropFacingAz(lat);
    ({double x, double y})? at(Horizontal h) => backdropProject(h, centerAz: az0);
    final stars = [
      for (final st in catalog.stars)
        if (st.mag < 4.8)
          if (at(st.horizontal(utc, lat, lon)) case final p?) (x: p.x, y: p.y, mag: st.mag, bv: st.bv),
    ];
    final lines = <(({double x, double y}), ({double x, double y}))>[];
    for (final con in catalog.constellations) {
      for (final seg in con.lines) {
        ({double x, double y})? prev;
        for (final (ra, dec) in seg) {
          final p = at(catalog.place(ra, dec, utc, lat, lon));
          if (p != null && prev != null) lines.add((prev, p));
          prev = p;
        }
      }
    }
    final m = at(moonHorizontal(utc, lat, lon));
    ({double x, double y, double lit, double towardSun})? moon;
    if (m != null) {
      // Which way the lit limb faces: a step from the Moon toward the Sun,
      // projected the same way.
      final mh = moonHorizontal(utc, lat, lon), sh = sunHorizontal(utc, lat, lon);
      final step = at(stepToward(mh, sh, 2));
      final dir = step == null ? 0.0 : math.atan2(-(step.y - m.y), step.x - m.x);
      moon = (x: m.x, y: m.y, lit: moonIllumination(utc), towardSun: dir);
    }
    final sky = _BackdropSky(stars, lines, moon);
    _last = sky;
    _lastKey = key;
    return sky;
  }
}

class _RealSkyPainter extends CustomPainter {
  _RealSkyPainter(this.sky, this.maxOpacity);
  final _BackdropSky sky;
  final double maxOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    // ±55° across the width, the middle of the view a quarter of the way down.
    final scale = size.width / 2 / (2 * math.tan(55 * math.pi / 360));
    final origin = Offset(size.width / 2, size.height * 0.24);
    Offset o(({double x, double y}) p) => origin + Offset(p.x * scale, -p.y * scale);
    final bounds = (Offset.zero & size).inflate(8);

    final line = Paint()
      ..color = const Color(0xFF5AA2FF).withValues(alpha: 0.09 * maxOpacity / 0.6)
      ..strokeWidth = 0.8;
    for (final (a, b) in sky.lines) {
      final pa = o(a), pb = o(b);
      if (!bounds.contains(pa) && !bounds.contains(pb)) continue;
      canvas.drawLine(pa, pb, line);
    }

    final dot = Paint();
    for (final st in sky.stars) {
      final p = o((x: st.x, y: st.y));
      if (!bounds.contains(p)) continue;
      final bright = ((4.8 - st.mag) / 6).clamp(0.0, 1.0);
      final r = 0.45 + bright * bright * 2.0;
      final a = (0.18 + bright * 0.82) * maxOpacity;
      final tint = _tint(st.bv);
      dot.color = tint.withValues(alpha: a);
      canvas.drawCircle(p, r, dot);
      if (st.mag < 1.2) {
        dot.color = tint.withValues(alpha: 0.10 * maxOpacity / 0.6);
        canvas.drawCircle(p, r * 3.2, dot);
      }
    }

    final m = sky.moon;
    if (m != null) {
      final p = o((x: m.x, y: m.y));
      if (bounds.contains(p)) paintMoonPhase(canvas, p, m.lit, m.towardSun);
    }
  }


  static Color _tint(double? bv) {
    final b = bv ?? 0.6;
    if (b < 0) return const Color(0xFFC4DAFF);
    if (b < 0.5) return const Color(0xFFF2F5FF);
    if (b < 1.1) return const Color(0xFFFFF4E0);
    return const Color(0xFFFFD2A8);
  }

  @override
  bool shouldRepaint(_RealSkyPainter o) => o.sky != sky || o.maxOpacity != maxOpacity;
}

/// The Moon's real phase at [c]: the lit part turned toward the Sun
/// ([towardSun], a screen angle).
void paintMoonPhase(Canvas canvas, Offset c, double lit, double towardSun, {double r = 9}) {
  canvas.drawCircle(
      c,
      r * 2.6,
      Paint()
        ..color = const Color(0xFFEDE7D9).withValues(alpha: 0.10 + 0.14 * lit)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(towardSun);
  canvas.drawCircle(Offset.zero, r, Paint()..color = const Color(0x22EDE7D9));
  // Lit limb on +x; the terminator is an ellipse crossing at r·(1 − 2·lit).
  final xm = r * (1 - 2 * lit);
  final path = Path()
    ..moveTo(0, -r)
    ..arcToPoint(Offset(0, r), radius: Radius.circular(r))
    ..arcToPoint(Offset(0, -r), radius: Radius.elliptical(xm.abs(), r), clockwise: xm < 0);
  canvas.drawPath(path, Paint()..color = const Color(0xFFEDE7D9).withValues(alpha: 0.9));
  canvas.restore();
}

/// The point [deg] degrees from [a] along the great circle toward [b].
Horizontal stepToward(Horizontal a, Horizontal b, double deg) {
  const k = math.pi / 180;
  List<double> v(Horizontal h) => [
        math.cos(h.altitudeDeg * k) * math.sin(h.azimuthDeg * k),
        math.cos(h.altitudeDeg * k) * math.cos(h.azimuthDeg * k),
        math.sin(h.altitudeDeg * k),
      ];
  final va = v(a), vb = v(b);
  final f = deg * k;
  final p = [for (var i = 0; i < 3; i++) va[i] + f * (vb[i] - va[i])];
  final n = math.sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]);
  final az = math.atan2(p[0] / n, p[1] / n) / k;
  return Horizontal((az + 360) % 360, math.asin((p[2] / n).clamp(-1.0, 1.0)) / k);
}
