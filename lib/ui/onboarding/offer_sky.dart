/// The onboarding offer's sky: their own sky tonight, dimmed, looking toward
/// the pole (north, or south below the equator). Each LookUp+ thing they
/// turn on shows in it: aurora curtains over the horizon, a Starlink train
/// sliding across, the city glow fading as fainter stars come out, the real
/// stars wheeling into trails over two hours, and a Pro camera Moon going
/// sharp. Pip flies to whichever came on last.
///
/// It's a picture of what LookUp+ does, not a forecast: nothing here says
/// aurora or a train is coming tonight. The real ones are listed under it.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/finder/pointing.dart';
import '../../domain/photo/framing.dart' show levelPose;
import '../../domain/sky/catalog.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// The LookUp+ things the offer's sky can show.
enum OfferLight { aurora, starlink, darker, timelapse, camera }

class OfferSky extends StatefulWidget {
  const OfferSky({
    super.key,
    required this.catalog,
    required this.lat,
    required this.lon,
    required this.at,
    required this.lit,
    this.last,
    this.place,
  });

  final SkyCatalog catalog;
  final double lat, lon;

  /// The moment shown: the same night as the sky page.
  final DateTime at;

  /// What's on.
  final Set<OfferLight> lit;

  /// What came on last: Pip goes there.
  final OfferLight? last;
  final String? place;

  @override
  State<OfferSky> createState() => _OfferSkyState();
}

class _OfferSkyState extends State<OfferSky> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero, _prev = Duration.zero;

  /// How far each light has come on, 0…1.
  final _k = {for (final l in OfferLight.values) l: 0.0};
  int _pokes = 0;
  _Stars? _stars;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      final dt = (e - _prev).inMicroseconds / 1e6;
      _prev = e;
      setState(() {
        _elapsed = e;
        for (final l in OfferLight.values) {
          final to = widget.lit.contains(l) ? 1.0 : 0.0;
          _k[l] = _k[l]! + (to - _k[l]!) * math.min(1, dt * 2.6);
        }
      });
    })
      ..start();
  }

  @override
  void didUpdateWidget(OfferSky old) {
    super.didUpdateWidget(old);
    if (widget.last != null && widget.last != old.last && widget.lit.contains(widget.last)) _pokes++;
    if (widget.lat != old.lat || widget.lon != old.lon || widget.at != old.at || widget.catalog != old.catalog) _stars = null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Toward the pole above them: that's where aurora is, and the stars
  /// wheel round it.
  double get _facing => widget.lat >= 0 ? 0 : 180;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      for (final l in OfferLight.values) {
        _k[l] = widget.lit.contains(l) ? 1 : 0;
      }
    }
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final stars = _stars != null && _stars!.size == size ? _stars! : _stars = _Stars.of(widget, size, _facing);
      final pip = _pipAt(widget.last, size, stars);
      return ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              key: const Key('offer-sky'),
              painter: _OfferPainter(
                stars: stars,
                k: Map.of(_k),
                t: still ? 0 : _elapsed.inMicroseconds / 1e6,
                still: still,
                place: widget.place,
              ),
            ),
          ),
          AnimatedPositioned(
            duration: still ? Duration.zero : const Duration(milliseconds: 750),
            curve: Curves.easeInOutCubic,
            left: pip.dx - 20,
            top: pip.dy - 20,
            child: IgnorePointer(child: PipMark(size: 40, poke: _pokes)),
          ),
        ]),
      );
    });
  }

  /// Where Pip goes to show each light.
  Offset _pipAt(OfferLight? l, Size size, _Stars s) => switch (l) {
        OfferLight.aurora => Offset(size.width * 0.5, s.horizonY - 58),
        OfferLight.starlink => Offset(size.width * 0.32, size.height * 0.36),
        OfferLight.darker => Offset(size.width * 0.72, size.height * 0.28),
        OfferLight.timelapse => s.pole ?? Offset(size.width * 0.5, size.height * 0.3),
        OfferLight.camera => Offset(size.width - 102, 44),
        null => Offset(size.width * 0.5, size.height * 0.42),
      };
}

/// Their real stars where they'll be, and two hours of their tracks.
class _Stars {
  _Stars(this.size, this.points, this.tracks, this.horizonY, this.pole, this.dust);
  final Size size;
  final List<({Offset at, double mag})> points;

  /// Each star's place every ten minutes for two hours (for its trail).
  final List<List<Offset>> tracks;
  final double horizonY;
  final Offset? pole;

  /// Starlight too faint to pick out, which a dark sky shows as a haze of
  /// tiny stars. Decorative: placed at random.
  final List<Offset> dust;

  static const fov = 64.0;

  static _Stars of(OfferSky w, Size size, double facing) {
    final r = levelPose(SkyDir(facing, 30));
    Offset? screen(double az, double alt) {
      final p = projectToScreen(r, SkyDir(az, alt), declinationDeg: 0, previewHeightPx: size.height, verticalFovDeg: fov);
      if (p == null) return null;
      return Offset(size.width / 2 + p.x, size.height / 2 + p.y);
    }

    final points = <({Offset at, double mag})>[];
    final tracks = <List<Offset>>[];
    for (final s in w.catalog.stars) {
      final h = w.catalog.place(s.raDeg, s.decDeg, w.at, w.lat, w.lon);
      if (h.altitudeDeg < 0) continue;
      final o = screen(h.azimuthDeg, h.altitudeDeg);
      if (o == null || o.dx < -20 || o.dx > size.width + 20 || o.dy < -20 || o.dy > size.height) continue;
      points.add((at: o, mag: s.mag));
      if (s.mag < 4.2) {
        final track = <Offset>[o];
        for (var i = 1; i <= 12; i++) {
          final q = w.catalog.place(s.raDeg, s.decDeg, w.at.add(Duration(minutes: 10 * i)), w.lat, w.lon);
          final p = screen(q.azimuthDeg, q.altitudeDeg);
          if (p == null) break;
          track.add(p);
        }
        tracks.add(track);
      }
    }
    final horizon = screen(facing, 0);
    final pole = w.lat.abs() < 5 ? null : screen(facing, w.lat.abs());
    final rnd = math.Random(7);
    final dust = [for (var i = 0; i < 700; i++) Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height)];
    return _Stars(size, points, tracks, horizon?.dy ?? size.height * 0.86, pole, dust);
  }
}

class _OfferPainter extends CustomPainter {
  _OfferPainter({required this.stars, required this.k, required this.t, required this.still, this.place});
  final _Stars stars;
  final Map<OfferLight, double> k;
  final double t;
  final bool still;
  final String? place;

  double get any => k.values.fold(0, math.max);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF03050C), Color(0xFF0B1328), Color(0xFF16213E)],
            stops: [0, 0.65, 1],
          ).createShader(rect));
    final dark = k[OfferLight.darker]!;
    // The town's glow, which a darker sky leaves behind.
    if (dark < 1) {
      canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0.5, 1.2),
              radius: 1.1,
              colors: [LookUpColors.orange.withValues(alpha: 0.38 * (1 - dark)), LookUpColors.orange.withValues(alpha: 0)],
            ).createShader(rect));
    }
    // Dim until something's on: this is their sky waiting to be lit.
    final lift = 0.5 + 0.5 * math.min(1, any * 1.5);
    final limit = 3.4 + 1.6 * dark;
    final dots = Paint();
    if (dark > 0) {
      for (final (i, d) in stars.dust.indexed) {
        final a = dark * (0.12 + 0.18 * ((i * 37) % 10) / 10);
        canvas.drawCircle(d, 0.55, dots..color = LookUpColors.white.withValues(alpha: a * lift));
      }
    }
    // Two hours of the real sky turning, drawn in as it comes on.
    final trail = k[OfferLight.timelapse]!;
    if (trail > 0.01) {
      final pen = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (final track in stars.tracks) {
        if (track.length < 2) continue;
        final upTo = trail * (track.length - 1);
        final path = Path()..moveTo(track.first.dx, track.first.dy);
        for (var i = 1; i < track.length && i - 1 < upTo; i++) {
          final f = (upTo - (i - 1)).clamp(0.0, 1.0);
          final to = Offset.lerp(track[i - 1], track[i], f)!;
          path.lineTo(to.dx, to.dy);
        }
        canvas.drawPath(
            path,
            pen
              ..strokeWidth = 1.1
              ..color = LookUpColors.cyan.withValues(alpha: 0.18 + 0.4 * trail));
      }
    }
    for (final s in stars.points) {
      if (s.mag > limit) continue;
      final fade = ((limit - s.mag) / 0.6).clamp(0.0, 1.0);
      final r = (2.6 - s.mag * 0.42).clamp(0.7, 3.0);
      final tw = still ? 1.0 : 0.88 + 0.12 * math.sin(t * 2 + s.at.dx);
      canvas.drawCircle(s.at, r, dots..color = LookUpColors.white.withValues(alpha: (0.45 + (5 - s.mag) * 0.11).clamp(0.3, 1.0) * fade * lift * tw));
    }
    _aurora(canvas, size, k[OfferLight.aurora]!);
    _train(canvas, size, k[OfferLight.starlink]!);
    _ground(canvas, size);
    _photo(canvas, size, k[OfferLight.camera]!);
  }

  void _aurora(Canvas canvas, Size size, double a) {
    if (a <= 0.01) return;
    final base = stars.horizonY;
    for (var band = 0; band < 3; band++) {
      final c = band == 2 ? LookUpColors.rose : LookUpColors.good;
      for (var x = 0.0; x <= size.width; x += 5) {
        final top = base - 46 - band * 22 - 22 * math.sin(x * 0.012 + t * (0.6 + band * 0.2) + band) - 10 * math.sin(x * 0.031 - t * 0.9);
        final h = 70.0 + band * 10;
        canvas.drawRect(
            Rect.fromLTWH(x, top, 5.5, h),
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.withValues(alpha: 0), c.withValues(alpha: 0.34 * a / (band + 1)), c.withValues(alpha: 0)],
                stops: const [0, 0.3, 1],
              ).createShader(Rect.fromLTWH(x, top, 5.5, h)));
      }
    }
  }

  void _train(Canvas canvas, Size size, double a) {
    if (a <= 0.01) return;
    final f = still ? 0.55 : (t * 0.07) % 1;
    final p = Paint()..color = LookUpColors.white.withValues(alpha: 0.9 * a);
    for (var i = 0; i < 20; i++) {
      final u = f * 1.5 - i * 0.024 - 0.2;
      if (u < 0 || u > 1) continue;
      canvas.drawCircle(Offset(u * size.width, size.height * 0.66 - u * size.height * 0.46), 1.5, p);
    }
  }

  void _ground(Canvas canvas, Size size) {
    final y = stars.horizonY;
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 5) {
      path.lineTo(x, y - math.max(0, math.sin(x * 0.013) * 9 + math.sin(x * 0.041) * 5 + math.sin(x * 0.11) * 2));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = LookUpColors.black);
    if (place case final name?) {
      final tp = TextPainter(
        text: TextSpan(text: name, style: display(12.5, weight: FontWeight.w600, color: LookUpColors.grey)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width - 32);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, math.min(size.height - tp.height - 6, y + 10)));
    }
  }

  /// The Pro camera's Moon: a photo that comes in soft and goes sharp.
  void _photo(Canvas canvas, Size size, double a) {
    if (a <= 0.01) return;
    final box = Rect.fromLTWH(size.width - 78, 12, 66, 66);
    canvas.save();
    canvas.translate(box.center.dx, box.center.dy);
    canvas.rotate(0.06 * (1 - a) + 0.04);
    canvas.scale(0.7 + 0.3 * Curves.easeOutBack.transform(a));
    canvas.translate(-box.center.dx, -box.center.dy);
    final frame = RRect.fromRectAndRadius(box, const Radius.circular(6));
    canvas.drawRRect(frame.inflate(3), Paint()..color = LookUpColors.white.withValues(alpha: 0.9 * a));
    canvas.drawRRect(frame, Paint()..color = const Color(0xFF05070D).withValues(alpha: a));
    canvas.clipRRect(frame);
    final sharp = ((a - 0.35) / 0.65).clamp(0.0, 1.0);
    final c = box.center;
    final moon = Paint()
      ..color = const Color(0xFFEDE7D2).withValues(alpha: a)
      ..maskFilter = sharp < 1 ? MaskFilter.blur(BlurStyle.normal, 5 * (1 - sharp) + 0.01) : null;
    canvas.drawCircle(c, 22, moon);
    final crater = Paint()..color = const Color(0xFF9A9480).withValues(alpha: (0.2 + 0.5 * sharp) * a);
    for (final (dx, dy, r) in const [(-7.0, -5.0, 5.0), (6.0, 3.0, 3.6), (-1.0, 8.0, 2.8), (8.0, -8.0, 2.2), (-9.0, 6.0, 1.8)]) {
      canvas.drawCircle(c + Offset(dx, dy), r, crater);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OfferPainter o) => true;
}
