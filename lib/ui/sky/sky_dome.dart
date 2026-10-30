/// The sky above you as a round map: horizon at the rim, overhead in the
/// middle, north up and east on the left (as if lying on your back with
/// your head to the north). Stars, constellation figures, planets, the Moon
/// and showpieces; tap one to open it.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/sky/catalog.dart';
import '../theme.dart';
import 'sky_thing.dart';
import 'sky_track.dart';

class SkyDome extends StatelessWidget {
  const SkyDome({
    super.key,
    required this.time,
    required this.lat,
    required this.lon,
    required this.catalog,
    required this.things,
    this.selectedId,
    this.onTap,
    this.labelStyle,
    this.tracks = const [],
    this.trackTime,
    this.onTrackTap,
  });

  final DateTime time;
  final double lat, lon;
  final SkyCatalog catalog;
  final List<SkyThing> things;
  final String? selectedId;
  final ValueChanged<SkyThing>? onTap;
  final TextStyle? labelStyle;

  /// Passes to draw across the map; see [SkyPanorama.tracks].
  final List<SkyTrack> tracks;
  final DateTime? trackTime;
  final ValueChanged<SkyEvent>? onTrackTap;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(builder: (context, c) {
          final size = Size(c.maxWidth, c.maxWidth);
          final painter = _DomePainter(
            time: time.toUtc(),
            lat: lat,
            lon: lon,
            catalog: catalog,
            things: things,
            selectedId: selectedId,
            label: labelStyle ?? Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
            tracks: tracks,
            trackTime: (trackTime ?? time).toUtc(),
          );
          return Semantics(
            label: 'Sky map, with you in the middle looking up. ${things.where((t) => t.position(time).altitudeDeg > 0).map((t) => t.name).join(', ')} are up now.',
            child: GestureDetector(
              onTapUp: (d) {
                final hit = painter.thingAt(size, d.localPosition);
                if (hit != null) {
                  onTap?.call(hit);
                  return;
                }
                final track = painter.trackAt(size, d.localPosition);
                if (track != null) onTrackTap?.call(track.event);
              },
              child: CustomPaint(size: size, painter: painter),
            ),
          );
        }),
      );
}

class _DomePainter extends CustomPainter {
  _DomePainter({
    required this.time,
    required this.lat,
    required this.lon,
    required this.catalog,
    required this.things,
    required this.selectedId,
    required this.label,
    required this.tracks,
    required this.trackTime,
  });

  final DateTime time;
  final double lat, lon;
  final SkyCatalog catalog;
  final List<SkyThing> things;
  final String? selectedId;
  final TextStyle label;
  final List<SkyTrack> tracks;
  final DateTime trackTime;

  List<Offset?> _project(Size s, SkyTrack tr) => [for (final p in tr.points) _xy(s, p.h.azimuthDeg, p.h.altitudeDeg)];

  SkyTrack? trackAt(Size s, Offset p) {
    for (final tr in tracks) {
      if (nearTrack(_project(s, tr), p)) return tr;
    }
    return null;
  }

  /// Azimuthal equidistant: radius grows linearly from zenith to horizon.
  Offset? _xy(Size s, double az, double alt) {
    if (alt < 0) return null;
    final r = (90 - alt) / 90 * (s.width / 2 - 14);
    final a = az * math.pi / 180;
    return s.center(Offset(-math.sin(a) * r, -math.cos(a) * r));
  }

  Offset? _eq(Size s, double ra, double dec) {
    final h = catalog.place(ra, dec, time, lat, lon);
    return _xy(s, h.azimuthDeg, h.altitudeDeg);
  }

  SkyThing? thingAt(Size s, Offset p) {
    SkyThing? best;
    var bestD = 26.0;
    for (final t in things) {
      final h = t.position(time);
      final o = _xy(s, h.azimuthDeg, h.altitudeDeg);
      if (o == null) continue;
      final d = (o - p).distance;
      if (d < bestD) {
        bestD = d;
        best = t;
      }
    }
    return best;
  }

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final rim = s.width / 2 - 14;
    // Sky disc with a faint glow toward the horizon.
    canvas.drawCircle(
      c,
      rim,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFF03060E), Color(0xFF0A1530), Color(0xFF13234A)], stops: [0.35, 0.85, 1])
            .createShader(Rect.fromCircle(center: c, radius: rim)),
    );
    final hairline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x33FFFFFF);
    canvas.drawCircle(c, rim, hairline);
    hairline.color = const Color(0x12FFFFFF);
    canvas.drawCircle(c, rim * 2 / 3, hairline); // 30° up
    canvas.drawCircle(c, rim / 3, hairline); // 60° up

    // Constellation figures.
    final linePaint = Paint()
      ..color = LookUpColors.blue.withValues(alpha: 0.24)
      ..strokeWidth = 0.9;
    for (final con in catalog.constellations) {
      for (final seg in con.lines) {
        Offset? prev;
        for (final (ra, dec) in seg) {
          final o = _eq(s, ra, dec);
          if (o != null && prev != null) canvas.drawLine(prev, o, linePaint);
          prev = o;
        }
      }
    }

    // Stars, sized by brightness and tinted by colour.
    final dot = Paint();
    for (final st in catalog.stars) {
      final o = _eq(s, st.raDeg, st.decDeg);
      if (o == null) continue;
      final r = (2.6 - 0.42 * st.mag).clamp(0.5, 3.4);
      dot.color = _starColor(st.bv).withValues(alpha: (1.15 - st.mag * 0.15).clamp(0.35, 1.0));
      canvas.drawCircle(o, r, dot);
    }

    // Constellation names for the well-known ones.
    for (final con in catalog.constellations.where((c) => c.rank == 1)) {
      final o = _eq(s, con.centerRaDeg, con.centerDecDeg);
      if (o == null) continue;
      _text(canvas, con.name, o, label.copyWith(fontSize: 10, fontWeight: FontWeight.w500, color: const Color(0x99A0A8B8)));
    }

    // Passes, under the planets and the Moon.
    for (final tr in tracks) {
      final live = tr.at(trackTime);
      paintTrack(canvas, tr, _project(s, tr), trackTime, label,
          maxJump: s.width, bounds: Offset.zero & s, liveAt: live == null ? null : _xy(s, live.azimuthDeg, live.altitudeDeg));
    }

    // Planets, Moon, showpieces.
    for (final t in things) {
      final h = t.position(time);
      final o = _xy(s, h.azimuthDeg, h.altitudeDeg);
      if (o == null) continue;
      final selected = t.id == selectedId;
      if (t.id == 'moon') {
        canvas.drawCircle(
            o,
            14,
            Paint()
              ..color = const Color(0x55EDE7D9)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        canvas.drawCircle(o, 9, Paint()..color = const Color(0xFFEDE7D9));
      } else if (t.kind == 'Planet') {
        canvas.drawCircle(
            o,
            9,
            Paint()
              ..color = LookUpColors.gold.withValues(alpha: 0.35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
        canvas.drawCircle(o, 3.8, Paint()..color = const Color(0xFFFFF2C8));
      } else {
        canvas.drawCircle(
            o,
            5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2
              ..color = LookUpColors.grey.withValues(alpha: 0.8));
      }
      if (selected) {
        canvas.drawCircle(
            o,
            15,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = LookUpColors.blue);
      }
      if (t.kind == 'Planet' || t.id == 'moon' || selected) {
        _text(canvas, t.id == 'moon' ? 'Moon' : t.name, o + const Offset(0, 15),
            label.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600, color: LookUpColors.white));
      }
    }

    // You: standing under the middle of the map, looking straight up.
    canvas.drawCircle(c, 11, Paint()..color = LookUpColors.blue.withValues(alpha: 0.16));
    canvas.drawCircle(
        c,
        11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = LookUpColors.blue.withValues(alpha: 0.55));
    canvas.drawCircle(c, 3.5, Paint()..color = LookUpColors.blue);
    _text(canvas, 'You', c + const Offset(0, 21), label.copyWith(fontSize: 10.5, fontWeight: FontWeight.w700, color: LookUpColors.blue));

    // Compass letters at the rim (east on the left: we're looking up).
    for (final (az, l) in const [(0.0, 'N'), (90.0, 'E'), (180.0, 'S'), (270.0, 'W')]) {
      final a = az * math.pi / 180;
      final o = c + Offset(-math.sin(a) * (rim + 8), -math.cos(a) * (rim + 8));
      _text(canvas, l, o,
          label.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: l == 'N' ? LookUpColors.blue : LookUpColors.grey));
    }
  }

  static Color _starColor(double? bv) {
    final b = bv ?? 0.6;
    if (b < 0) return const Color(0xFFBFD4FF);
    if (b < 0.4) return const Color(0xFFF2F5FF);
    if (b < 0.9) return const Color(0xFFFFF4E0);
    if (b < 1.3) return const Color(0xFFFFDDB0);
    return const Color(0xFFFFC28A);
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_DomePainter o) =>
      o.time != time ||
      o.selectedId != selectedId ||
      o.things != things ||
      o.lat != lat ||
      o.lon != lon ||
      o.tracks != tracks ||
      o.trackTime != trackTime;
}
