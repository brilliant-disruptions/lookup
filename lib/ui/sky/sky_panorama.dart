/// The sky as you'd see it standing outside: rooftops and trees along the
/// bottom, the horizon across, straight up at the top. It follows the phone
/// by default; drag (or use the arrows) to look round, and a few seconds
/// after you let go it swings back to the phone. Tap a planet, the Moon or a
/// showpiece to open it. Each constellation's picture is drawn faintly
/// behind its lines, and the one in the middle of the view glows a little
/// brighter, so turning toward it shows what it was meant to be.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/finder/pointing.dart';
import '../../domain/models/sky_event.dart';
import '../../domain/sky/astro.dart';
import '../../domain/sky/catalog.dart';
import '../../domain/sky/direction.dart';
import '../../domain/sky/figures.dart';
import '../../domain/sky/wmm.dart';
import '../../services/orientation.dart';
import '../kit/kit.dart';
import '../theme.dart';
import 'figure_art.dart';
import 'sky_thing.dart';
import 'sky_track.dart';

/// How wide a slice of the horizon fits on screen, in degrees.
const panoramaFov = 140.0;

/// How long a drag holds the view after your finger lifts, before it swings
/// back to following the phone.
const panoramaHold = Duration(seconds: 3);

/// How long a constellation's picture takes to brighten or fade as you turn
/// onto it or away.
const figureFade = Duration(milliseconds: 450);

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
    this.height = 532,
    this.orientationStream,
    this.initialFacing,
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

  /// Injected in tests; defaults to the fused rotation sensor.
  final Stream<List<double>>? orientationStream;

  /// The way to face first; otherwise a pass going over, else [bestFacing].
  /// Given one, it doesn't follow the phone.
  final double? initialFacing;

  /// The sky itself, for tests that drag or tap it.
  static const canvasKey = ValueKey('sky-panorama');

  /// The firefly marking where the phone points (tests).
  static const youKey = ValueKey('sky-panorama-you');

  @override
  State<SkyPanorama> createState() => _SkyPanoramaState();
}

class _SkyPanoramaState extends State<SkyPanorama> with TickerProviderStateMixin {
  /// Seconds for the firefly's hover; only its own layer repaints.
  final _hoverClock = ValueNotifier<double>(0);
  late final Ticker _hoverTicker = createTicker((e) => _hoverClock.value = e.inMicroseconds / 1e6);

  // Something passing over right now beats everything else.
  late double _facing = widget.initialFacing ??
      widget.tracks
          .map((t) => t.at(widget.trackTime ?? widget.time)?.azimuthDeg)
          .nonNulls
          .firstOrNull ??
      bestFacing(widget.things, widget.time.toUtc());
  late final AnimationController _spin = AnimationController.unbounded(vsync: this)
    ..addListener(() => setState(() => _facing = _spin.value % 360));
  late _SkyCache _cache = _SkyCache(widget.catalog, widget.time.toUtc(), widget.lat, widget.lon, null);

  /// Constellation pictures: how far each is through brightening (0 to 1),
  /// easing toward 1 for the one in the middle and back to 0 for the rest.
  FigureArt? _art;
  String? _focusId;
  final _glow = ValueNotifier<Map<String, double>>(const {});
  late final Ticker _glowTicker = createTicker(_stepGlow);
  Duration _glowLast = Duration.zero;

  /// Following the phone, whenever it has a compass: the view turns as you
  /// do, and the firefly marks where the back of the phone points.
  StreamSubscription<List<double>>? _sensor;
  double? _pointingAlt;
  double? _phoneAz;

  /// A drag or arrow has the view while following: held while the finger is
  /// down, then for [panoramaHold], then it swings back to the phone.
  bool _peeking = false;
  Timer? _peekTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialFacing == null) _follow();
    FigureArt.load().then((art) {
      if (!mounted) return;
      setState(() {
        _art = art;
        _cache = _SkyCache(widget.catalog, widget.time.toUtc(), widget.lat, widget.lon, art);
      });
    }, onError: (_) {});
  }

  @override
  void didUpdateWidget(SkyPanorama old) {
    super.didUpdateWidget(old);
    if (old.time != widget.time || old.lat != widget.lat || old.lon != widget.lon || old.catalog != widget.catalog) {
      _cache = _SkyCache(widget.catalog, widget.time.toUtc(), widget.lat, widget.lon, _art);
    }
  }

  @override
  void dispose() {
    _peekTimer?.cancel();
    _sensor?.cancel();
    _spin.dispose();
    _hoverTicker.dispose();
    _hoverClock.dispose();
    _glowTicker.dispose();
    _glow.dispose();
    super.dispose();
  }

  /// A new constellation in the middle: brighten it, fade the last one.
  void _focus(String? id, {required bool animate}) {
    if (id == _focusId) return;
    _focusId = id;
    if (!animate) {
      _glowTicker.stop();
      _glow.value = {?id: 1.0};
    } else if (!_glowTicker.isActive) {
      _glowLast = Duration.zero;
      _glowTicker.start();
    }
  }

  void _stepGlow(Duration elapsed) {
    final step = (elapsed - _glowLast).inMicroseconds / figureFade.inMicroseconds;
    _glowLast = elapsed;
    final next = <String, double>{};
    var settled = true;
    for (final id in {..._glow.value.keys, ?_focusId}) {
      final target = id == _focusId ? 1.0 : 0.0;
      final v = (_glow.value[id] ?? 0.0) + (target > 0 ? step : -step);
      final n = v.clamp(0.0, 1.0);
      if (n > 0) next[id] = n;
      if (n != target) settled = false;
    }
    _glow.value = next;
    if (settled) _glowTicker.stop();
  }

  /// No compass is no news: it just turns by dragging.
  void _follow() {
    var stream = widget.orientationStream;
    try {
      stream ??= deviceRotation();
    } catch (_) {
      stream = null;
    }
    if (stream == null) return;
    final declination = declinationDeg(widget.lat, widget.lon, DateTime.now().toUtc());
    _spin.stop();
    final sub = stream.listen((r) {
      if (!mounted) return;
      final az = facingAzimuth(r, declinationDeg: declination);
      _phoneAz = az;
      if (_peeking || _spin.isAnimating) return;
      setState(() {
        // Ease toward the compass so its jitter doesn't shake the sky.
        _facing = (_facing + 0.25 * _wrap(az - _facing)) % 360;
        _pointingAlt = cameraDirection(r).elevationDeg;
      });
    }, onError: (_) => _unfollow());
    setState(() => _sensor = sub);
  }

  void _unfollow() {
    _sensor?.cancel();
    _peekTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _sensor = null;
      _pointingAlt = null;
      _phoneAz = null;
      _peeking = false;
    });
  }

  /// Take the view from the phone until [_letGo].
  void _hold() {
    _peekTimer?.cancel();
    if (_sensor != null && !_peeking) setState(() => _peeking = true);
  }

  /// Start the countdown back to the phone.
  void _letGo() {
    if (!_peeking) return;
    _peekTimer?.cancel();
    _peekTimer = Timer(panoramaHold, _swingBack);
  }

  /// Gently turn back to where the phone faces, then follow it again.
  void _swingBack() {
    if (!mounted) return;
    setState(() => _peeking = false);
    final az = _phoneAz;
    if (az == null) return;
    _spin.value = _facing;
    _spin.animateTo(_facing + _wrap(az - _facing), duration: const Duration(milliseconds: 900), curve: Curves.easeInOutCubic);
  }

  void _turnBy(double deg) {
    _hold();
    _spin.value = _facing;
    _spin.animateTo(_facing + deg, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    _letGo();
  }

  void _dragStart(DragStartDetails _) {
    _hold();
    _spin.stop();
  }

  void _drag(DragUpdateDetails d, double width) {
    setState(() => _facing = (_facing - d.delta.dx / width * panoramaFov) % 360);
  }

  void _fling(DragEndDetails d, double width) {
    _letGo();
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
    return SizedBox(
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
          art: _art,
          glow: _glow,
        );
        // Where the phone points: the firefly (you), on its own layer so its
        // hover doesn't repaint the sky. Mid-view, so only while following.
        final pointing = _peeking ? null : _pointingAlt;
        final hover = pointing != null && !MediaQuery.disableAnimationsOf(context);
        // The picture in the middle of the view (at the firefly, when there
        // is one) is the one that brightens.
        final figure = painter.figureNear(size, pointing);
        _focus(figure?.id, animate: !MediaQuery.disableAnimationsOf(context));
        final shown = figure == null ? null : widget.catalog.constellation(figure.id);
        if (hover && !_hoverTicker.isActive) {
          _hoverTicker.start();
        } else if (!hover && _hoverTicker.isActive) {
          _hoverTicker.stop();
        }
        return Semantics(
          label: 'Sky facing ${compassWord(_facing)}. '
              '${ahead.isEmpty ? 'Nothing bright that way.' : 'That way: ${ahead.join(', ')}.'}'
              '${shown == null ? '' : ' Pictured: ${shown.name}${shown.meaning == null ? '' : ', ${shown.meaning}'}.'}',
          child: Stack(children: [
            GestureDetector(
              onHorizontalDragStart: _dragStart,
              onHorizontalDragUpdate: (d) => _drag(d, size.width),
              onHorizontalDragEnd: (d) => _fling(d, size.width),
              onHorizontalDragCancel: _letGo,
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
            if (pointing != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(key: SkyPanorama.youKey, painter: _YouAreHere(altDeg: pointing, hover: hover ? _hoverClock : null)),
                ),
              ),
            Positioned(
              top: 10,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0xB304060B), borderRadius: BorderRadius.circular(13)),
                    child: Text('Facing ${compassWord(_facing)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: LookUpColors.blue)),
                  ),
                ),
              ),
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
    );
  }
}

/// Where every star and constellation line is right now. Recomputed once a
/// minute, not on every frame of a drag.
class _SkyCache {
  _SkyCache(SkyCatalog catalog, DateTime utc, double lat, double lon, FigureArt? art)
      : stars = [
          for (final s in catalog.stars)
            if (s.mag < 4.6) (star: s, h: s.horizontal(utc, lat, lon)),
        ],
        lines = [
          for (final con in catalog.constellations)
            for (final seg in con.lines)
              [for (final (ra, dec) in seg) catalog.place(ra, dec, utc, lat, lon)],
        ],
        names = [
          for (final con in catalog.constellations.where((c) => c.rank == 1))
            (name: con.name, h: catalogHorizontal(con.centerRaDeg, con.centerDecDeg, utc, lat, lon)),
        ],
        figures = [
          for (final f in art?.figures ?? const <ConstellationFigure>[])
            (figure: f, anchors: [for (final a in f.anchors) catalog.place(a.raDeg, a.decDeg, utc, lat, lon)]),
        ];

  final List<({Star star, Horizontal h})> stars;
  final List<List<Horizontal>> lines;
  final List<({String name, Horizontal h})> names;
  final List<({ConstellationFigure figure, List<Horizontal> anchors})> figures;
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
    this.art,
    required this.glow,
  }) : super(repaint: Listenable.merge([glow, art]));

  final _SkyCache cache;
  final double facing;
  final List<SkyThing> things;
  final DateTime utc;
  final String? selectedId;
  final TextStyle label;
  final List<SkyTrack> tracks;
  final DateTime trackTime;
  final FigureArt? art;
  final ValueListenable<Map<String, double>> glow;

  /// Every picture is this faint; the one in the middle rises to [_figureLit].
  static const _figureDim = 0.10, _figureLit = 0.5;
  static const _figureTint = Color(0xFFB8CCFF);

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

  /// Where a picture goes on screen: the map from its pixels that puts its
  /// three anchor stars where they are. Null when it's behind you, or so
  /// close overhead that the panorama would smear it.
  (Matrix4, Rect)? _figurePlace(Size s, ConstellationFigure f, List<Horizontal> anchors) {
    final to = [
      for (final h in anchors)
        (s.width / 2 + _wrap(h.azimuthDeg - facing) / panoramaFov * s.width, _horizon(s) - h.altitudeDeg / 90 * _skyH(s)),
    ];
    final xs = [for (final (x, _) in to) x];
    if (xs.reduce(max) - xs.reduce(min) > s.width / 2) return null;
    final m = affineFrom3([for (final a in f.anchors) (a.x, a.y)], to);
    if (m == null) return null;
    final (a, b, c, d, e, g) = m;
    Offset at(double x, double y) => Offset(a * x + c * y + e, b * x + d * y + g);
    final corners = [at(0, 0), at(f.width, 0), at(0, f.height), at(f.width, f.height)];
    final box = Rect.fromLTRB(corners.map((o) => o.dx).reduce(min), corners.map((o) => o.dy).reduce(min),
        corners.map((o) => o.dx).reduce(max), corners.map((o) => o.dy).reduce(max));
    if (!box.overlaps(Rect.fromLTWH(0, 0, s.width, _horizon(s)))) return null;
    return (Matrix4(a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, g, 0, 1), box);
  }

  /// The picture on the middle of the view: at the height the phone points,
  /// when it's following, else halfway up the sky. Judged by its anchor
  /// stars, not its image's centre: a tall rising Leo has its centre well
  /// below the middle, and little Leo Minor's would win instead.
  ConstellationFigure? figureNear(Size s, double? altDeg) {
    final mid = Offset(s.width / 2, _horizon(s) - (altDeg ?? 35).clamp(5.0, 85.0) / 90 * _skyH(s));
    ConstellationFigure? best;
    var bestD = s.width * 0.22, bestC = double.infinity;
    for (final (:figure, :anchors) in cache.figures) {
      final place = _figurePlace(s, figure, anchors);
      if (place == null) continue;
      final tri = [for (final a in figure.anchors) MatrixUtils.transformPoint(place.$1, Offset(a.x, a.y))];
      final d = distanceToTriangle((mid.dx, mid.dy), [for (final o in tri) (o.dx, o.dy)]);
      // Where triangles overlap, the one centred nearer wins.
      final c = ((tri[0] + tri[1] + tri[2]) / 3 - mid).distance;
      if (d < bestD || (d == bestD && c < bestC)) {
        bestD = d;
        bestC = c;
        best = figure;
      }
    }
    return best;
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

    // Constellation pictures, under their lines. Grey on black, so adding
    // them to the sky leaves only the drawing.
    if (art case final art?) {
      final lit = glow.value;
      final picture = Paint()
        ..blendMode = BlendMode.plus
        ..filterQuality = FilterQuality.medium;
      for (final (:figure, :anchors) in cache.figures) {
        final place = _figurePlace(s, figure, anchors);
        if (place == null) continue;
        final img = art.image(figure);
        if (img == null) continue;
        final t = Curves.easeInOut.transform(lit[figure.id] ?? 0);
        picture.colorFilter = ColorFilter.mode(
            _figureTint.withValues(alpha: _figureDim + (_figureLit - _figureDim) * t), BlendMode.modulate);
        canvas.save();
        canvas.transform(place.$1.storage);
        canvas.scale(figure.width / img.width, figure.height / img.height);
        canvas.drawImage(img, Offset.zero, picture);
        canvas.restore();
      }
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
      o.art != art ||
      o.selectedId != selectedId ||
      o.things != things ||
      o.utc != utc ||
      o.tracks != tracks ||
      o.trackTime != trackTime;
}

/// Where the phone points on the Sky tab: the firefly, hovering. Here
/// there's nothing to find, so the firefly is you; mid-view at the phone's
/// height, held to the horizon when it's aimed at the ground.
class _YouAreHere extends CustomPainter {
  _YouAreHere({required this.altDeg, this.hover}) : super(repaint: hover);
  final double altDeg;

  /// Seconds for the hover; null holds it still (reduced motion).
  final ValueListenable<double>? hover;

  @override
  void paint(Canvas canvas, Size s) {
    final horizon = s.height - _PanoramaPainter._groundH;
    final skyH = horizon - 18;
    final at = Offset(s.width / 2, horizon - altDeg.clamp(0.0, 90.0) / 90 * skyH);
    final h = hover;
    paintFirefly(canvas, h == null ? at : at + fireflyHover(h.value));
  }

  @override
  bool shouldRepaint(_YouAreHere o) => o.altDeg != altDeg || o.hover != hover;
}
