/// The sky as you'd see it standing outside: rooftops and trees along the
/// bottom, the horizon across, straight up at the top. Drag (or use the
/// arrows) to turn round. Tap a planet, the Moon or a showpiece to open it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/sky/astro.dart';
import '../../domain/sky/catalog.dart';
import '../../domain/sky/direction.dart';
import '../kit/kit.dart';
import '../theme.dart';
import 'sky_thing.dart';
import 'sky_track.dart';

/// How wide a slice of the horizon fits on screen, in degrees.
const panoramaFov = 140.0;

/// The way to face first: where the most worth seeing is up right now. The
/// Moon counts most, then planets, then showpieces you can actually see;
/// each counts for more the nearer the middle of the view it sits.
double bestFacing(List<SkyThing> things, DateTime utc) {
  var best = 180.0, bestScore = 0.0;
  for (var dir = 0.0; dir < 360; dir += 45) {
    var score = 0.0;
    for (final t in things) {
      final h = t.position(utc);
      final off = _wrap(h.azimuthDeg - dir).abs();
      if (h.altitudeDeg <= 0 || off > panoramaFov / 2) continue;
      final weight = t.id == 'moon' ? 3 : (t.kind == 'Planet' ? 2 : (t.seeable ? 1 : 0));
      score += weight * (1 - off / (panoramaFov / 2));
    }
    if (score > bestScore) {
      bestScore = score;
      best = dir;
    }
  }
  return best;
}

double _wrap(double d) => ((d + 540) % 360) - 180;

class SkyPanorama extends StatefulWidget {
  const SkyPanorama({
    super.key,
    required this.time,
    required this.lat,
    required this.lon,
    required this.catalog,
    required this.things,
    this.selectedId,
    this.onTap,
    this.tracks = const [],
    this.trackTime,
    this.onTrackTap,
    this.height = 440,
  });

  final DateTime time;
  final double lat, lon;
  final SkyCatalog catalog;
  final List<SkyThing> things;
  final String? selectedId;
  final ValueChanged<SkyThing>? onTap;

  /// Passes to draw across the sky, and the moment their live dots are at
  /// (defaults to [time]; pass a per-second clock while one is up).
  final List<SkyTrack> tracks;
  final DateTime? trackTime;
  final ValueChanged<SkyEvent>? onTrackTap;
  final double height;

  /// The sky itself, for tests that drag or tap it.
  static const canvasKey = ValueKey('sky-panorama');

  @override
  State<SkyPanorama> createState() => _SkyPanoramaState();
}

class _SkyPanoramaState extends State<SkyPanorama> with SingleTickerProviderStateMixin {
  // Something passing over right now beats everything else.
  late double _facing = widget.tracks
          .map((t) => t.at(widget.trackTime ?? widget.time)?.azimuthDeg)
          .nonNulls
          .firstOrNull ??
      bestFacing(widget.things, widget.time.toUtc());
  late final AnimationController _spin = AnimationController.unbounded(vsync: this)
    ..addListener(() => setState(() => _facing = _spin.value % 360));
  late _SkyCache _cache = _SkyCache(widget.catalog, widget.time.toUtc(), widget.lat, widget.lon);

  @override
  void didUpdateWidget(SkyPanorama old) {
    super.didUpdateWidget(old);
    if (old.time != widget.time || old.lat != widget.lat || old.lon != widget.lon || old.catalog != widget.catalog) {
      _cache = _SkyCache(widget.catalog, widget.time.toUtc(), widget.lat, widget.lon);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _turnBy(double deg) {
    _spin.value = _facing;
    _spin.animateTo(_facing + deg, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  void _drag(DragUpdateDetails d, double width) {
    _spin.stop();
    setState(() => _facing = (_facing - d.delta.dx / width * panoramaFov) % 360);
  }

  void _fling(DragEndDetails d, double width) {
    final degPerSec = -d.velocity.pixelsPerSecond.dx / width * panoramaFov;
    if (degPerSec.abs() < 20) return;
    _spin.value = _facing;
    _spin.animateWith(FrictionSimulation(0.08, _facing, degPerSec));
  }

  @override
  Widget build(BuildContext context) {
    final utc = widget.time.toUtc();
    final label = Theme.of(context).textTheme.labelSmall ?? const TextStyle();
    final ahead = [
      for (final t in widget.things)
        if (t.position(utc).altitudeDeg > 0 && _wrap(t.position(utc).azimuthDeg - _facing).abs() < panoramaFov / 2) t.name,
      for (final tr in widget.tracks)
        if (tr.points.any((p) => p.h.altitudeDeg > 0 && _wrap(p.h.azimuthDeg - _facing).abs() < panoramaFov / 2))
          '${tr.label}, passing ${compassWord(tr.event.riseAzimuthDeg)} to ${compassWord(tr.event.setAzimuthDeg)}',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(children: [
          Expanded(
            child: Text('Facing ${compassWord(_facing)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: LookUpColors.blue)),
          ),
          const Flexible(
            child: Text('Drag to turn round',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 13, color: LookUpColors.greyDim)),
          ),
        ]),
      ),
      SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, c) {
          final size = Size(c.maxWidth, widget.height);
          final painter = _PanoramaPainter(
            cache: _cache,
            facing: _facing,
            things: widget.things,
            utc: utc,
            selectedId: widget.selectedId,
            label: label,
            tracks: widget.tracks,
            trackTime: (widget.trackTime ?? widget.time).toUtc(),
          );
          return Semantics(
            label: 'Sky facing ${compassWord(_facing)}. '
                '${ahead.isEmpty ? 'Nothing bright that way.' : 'That way: ${ahead.join(', ')}.'}',
            child: Stack(children: [
              GestureDetector(
                onHorizontalDragUpdate: (d) => _drag(d, size.width),
                onHorizontalDragEnd: (d) => _fling(d, size.width),
                onTapUp: (d) {
                  final hit = painter.thingAt(size, d.localPosition);
                  if (hit != null) {
                    widget.onTap?.call(hit);
                    return;
                  }
                  final track = painter.trackAt(size, d.localPosition);
                  if (track != null) widget.onTrackTap?.call(track.event);
                },
                child: CustomPaint(key: SkyPanorama.canvasKey, size: size, painter: painter),
              ),
              for (final (left, deg) in const [(true, -45.0), (false, 45.0)])
                Positioned(
                  left: left ? 6 : null,
                  right: left ? null : 6,
                  bottom: 14, // in the ground strip, clear of the sky
                  child: CircleButton(
                    tooltip: left ? 'Turn left' : 'Turn right',
                    icon: left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    size: 36,
                    onPressed: () => _turnBy(deg),
                  ),
                ),
            ]),
          );
        }),
      ),
    ]);
  }
}

/// Where every star and constellation line is right now. Recomputed once a
/// minute, not on every frame of a drag.
class _SkyCache {
  _SkyCache(SkyCatalog catalog, DateTime utc, double lat, double lon)
      : stars = [
          for (final s in catalog.stars)
            if (s.mag < 4.6) (star: s, h: s.horizontal(utc, lat, lon)),
        ],
        lines = [
          for (final con in catalog.constellations)
            for (final seg in con.lines)
              [for (final (ra, dec) in seg) toHorizontal(Equatorial(ra, dec, 1), utc, lat, lon)],
        ],
        names = [
          for (final con in catalog.constellations.where((c) => c.rank == 1))
            (name: con.name, h: toHorizontal(Equatorial(con.centerRaDeg, con.centerDecDeg, 1), utc, lat, lon)),
        ];

  final List<({Star star, Horizontal h})> stars;
  final List<List<Horizontal>> lines;
  final List<({String name, Horizontal h})> names;
}

class _PanoramaPainter extends CustomPainter {
  _PanoramaPainter({
    required this.cache,
    required this.facing,
    required this.things,
    required this.utc,
    required this.selectedId,
    required this.label,
    required this.tracks,
    required this.trackTime,
  });

  final _SkyCache cache;
  final double facing;
  final List<SkyThing> things;
  final DateTime utc;
  final String? selectedId;
  final TextStyle label;
  final List<SkyTrack> tracks;
  final DateTime trackTime;

  static const _groundH = 64.0;
  static const _ground = Color(0xFF05080F);

  double _horizon(Size s) => s.height - _groundH;
  double _skyH(Size s) => _horizon(s) - 18;

  /// Cylindrical: across is compass direction, up is height above the horizon.
  Offset? _xy(Size s, Horizontal h) {
    final d = _wrap(h.azimuthDeg - facing);
    if (d.abs() > panoramaFov / 2 + 4 || h.altitudeDeg < -2) return null;
    return Offset(s.width / 2 + d / panoramaFov * s.width, _horizon(s) - h.altitudeDeg / 90 * _skyH(s));
  }

  /// A track projected into view; null where it's out of view or set.
  List<Offset?> _project(Size s, SkyTrack tr) => [
        for (final p in tr.points)
          if (_xy(s, p.h) case final o? when p.h.altitudeDeg >= 0) o else null,
      ];

  SkyTrack? trackAt(Size s, Offset p) {
    for (final tr in tracks) {
      if (nearTrack(_project(s, tr), p)) return tr;
    }
    return null;
  }

  SkyThing? thingAt(Size s, Offset p) {
    SkyThing? best;
    var bestD = 28.0;
    for (final t in things) {
      final o = _xy(s, t.position(utc));
      if (o == null || o.dy > _horizon(s)) continue;
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
    final horizon = _horizon(s), skyH = _skyH(s);
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(Radii.lg)));

    // Sky: dark overhead, a faint glow down at the horizon.
    final skyRect = Rect.fromLTWH(0, 0, s.width, horizon);
    canvas.drawRect(
        skyRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF03060E), Color(0xFF0A1530), Color(0xFF1C3566)],
            stops: [0, 0.7, 1],
          ).createShader(skyRect));

    // Height, in the same words as everywhere else (elevationWord's bands).
    // The lines go under the stars; their labels go on top, at the end.
    final guides = <(double, String)>[];
    final guide = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    for (final (alt, words) in const [(20.0, 'Halfway up'), (50.0, 'High'), (75.0, 'Overhead')]) {
      final y = horizon - alt / 90 * skyH;
      for (var x = 0.0; x < s.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), guide);
      }
      guides.add((y, words));
    }

    final line = Paint()
      ..color = LookUpColors.blue.withValues(alpha: 0.26)
      ..strokeWidth = 0.9;
    for (final seg in cache.lines) {
      Offset? prev;
      for (final h in seg) {
        final o = _xy(s, h);
        // Skip segments that wrap round the edge of the view.
        if (o != null && prev != null && (o - prev).distance < s.width / 3) canvas.drawLine(prev, o, line);
        prev = o;
      }
    }

    final dot = Paint();
    for (final (:star, :h) in cache.stars) {
      final o = _xy(s, h);
      if (o == null || o.dy > horizon) continue;
      dot.color = _starColor(star.bv).withValues(alpha: (1.15 - star.mag * 0.15).clamp(0.35, 1.0));
      canvas.drawCircle(o, (2.8 - 0.45 * star.mag).clamp(0.6, 3.6), dot);
      if (star.name != null && star.mag < 0.9) {
        _text(canvas, star.name!, o + const Offset(0, 12), label.copyWith(fontSize: 10, color: const Color(0xAAA0A8B8)));
      }
    }
    for (final (:name, :h) in cache.names) {
      final o = _xy(s, h);
      if (o != null && o.dy < horizon - 10) {
        _text(canvas, name, o, label.copyWith(fontSize: 10.5, fontWeight: FontWeight.w500, color: const Color(0x88A0A8B8)));
      }
    }

    for (final tr in tracks) {
      final live = tr.at(trackTime);
      paintTrack(canvas, tr, _project(s, tr), trackTime, label,
          maxJump: s.width / 3, bounds: Offset.zero & Size(s.width, _horizon(s)), liveAt: live == null || live.altitudeDeg < 0 ? null : _xy(s, live));
    }

    for (final t in things) {
      final o = _xy(s, t.position(utc));
      if (o == null || o.dy > horizon) continue;
      final moon = t.id == 'moon', planet = t.kind == 'Planet', selected = t.id == selectedId;
      if (moon || planet) {
        canvas.drawCircle(
            o,
            moon ? 22 : 9,
            Paint()
              ..color = moon ? const Color(0x55EDE7D9) : LookUpColors.gold.withValues(alpha: 0.4)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
        canvas.drawCircle(o, moon ? 12 : 4, Paint()..color = moon ? const Color(0xFFEDE7D9) : const Color(0xFFFFF2C8));
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
            moon ? 20 : 15,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = LookUpColors.blue);
      }
      if (moon || planet || selected) {
        _text(canvas, moon ? 'Moon' : t.name, o + Offset(0, moon ? 24 : 16),
            label.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: LookUpColors.white));
      }
    }

    for (final (y, words) in guides) {
      final tp = TextPainter(
          text: TextSpan(text: words, style: label.copyWith(fontSize: 10, fontWeight: FontWeight.w600, color: LookUpColors.grey)),
          textDirection: TextDirection.ltr)
        ..layout();
      final r = Rect.fromLTWH(s.width - tp.width - 22, y - tp.height - 4, tp.width + 12, tp.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = const Color(0xB304060B));
      tp.paint(canvas, r.topLeft + const Offset(6, 2));
    }

    // The ground: rooftops and trees, then the compass along the horizon.
    canvas.drawPath(_skyline(s.width, horizon), Paint()..color = _ground);
    canvas.drawRect(Rect.fromLTWH(0, horizon + 2, s.width, _groundH), Paint()..color = _ground);
    canvas.drawLine(Offset(0, horizon), Offset(s.width, horizon), Paint()..color = const Color(0x22FFFFFF));
    final tick = Paint()
      ..color = const Color(0x55FFFFFF)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 16; i++) {
      final d = _wrap(i * 22.5 - facing);
      if (d.abs() > panoramaFov / 2) continue;
      final x = s.width / 2 + d / panoramaFov * s.width;
      canvas.drawLine(Offset(x, horizon + 6), Offset(x, horizon + (i.isEven ? 14 : 10)), tick);
      if (i.isEven) {
        final ahead = d.abs() < 11.25;
        _text(canvas, compassAbbrev(i * 22.5), Offset(x, horizon + 30),
            label.copyWith(
                fontSize: ahead ? 15 : 12.5, fontWeight: FontWeight.w700, color: ahead ? LookUpColors.blue : LookUpColors.grey));
      }
    }

    // Soft edges: there's more sky either side.
    for (final left in [true, false]) {
      final r = Rect.fromLTWH(left ? 0 : s.width - 48, 0, 48, s.height);
      canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(
              begin: left ? Alignment.centerLeft : Alignment.centerRight,
              end: left ? Alignment.centerRight : Alignment.centerLeft,
              colors: const [Color(0xCC04060B), Color(0x0004060B)],
            ).createShader(r));
    }
  }

  /// Rooftops and trees that stay put as you turn: generated per compass
  /// degree, so the same house is always to the north-east.
  Path _skyline(double width, double base) {
    final p = Path()..moveTo(0, base + 2);
    final degPerPx = panoramaFov / width;
    final start = (facing - panoramaFov / 2 - 20).floor();
    var az = start;
    while (az < facing + panoramaFov / 2 + 20) {
      final seed = ((az % 360) + 360) % 360;
      final w = 6 + (seed * 7919 % 13); // degrees wide
      final h = 5.0 + (seed * 104729 % 17);
      final x0 = width / 2 + (az - facing) / degPerPx;
      final x1 = width / 2 + (az + w - facing) / degPerPx;
      switch (seed * 31 % 3) {
        case 0: // a tree
          p.lineTo(x0, base);
          p.quadraticBezierTo((x0 + x1) / 2, base - h * 1.6, x1, base);
        case 1: // a house
          p.lineTo(x0, base);
          p.lineTo(x0, base - h * 0.6);
          p.lineTo((x0 + x1) / 2, base - h * 1.1);
          p.lineTo(x1, base - h * 0.6);
          p.lineTo(x1, base);
        default: // open ground
          p.lineTo(x1, base);
      }
      az += w;
    }
    p.lineTo(width, base + 2);
    p.close();
    return p;
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
  bool shouldRepaint(_PanoramaPainter o) =>
      o.facing != facing ||
      o.cache != cache ||
      o.selectedId != selectedId ||
      o.things != things ||
      o.utc != utc ||
      o.tracks != tracks ||
      o.trackTime != trackTime;
}
