import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/sky_event.dart';
import '../theme.dart';

/// Each kind of event has one icon and one tint, used everywhere it shows
/// up: list glyphs, the hero card's glow, the Week tab. A null icon means
/// the ringed [PlanetMark] (Material's only planet icon is the Earth).
({IconData? icon, Color color}) eventStyle(SkyEventType? t, {Map<String, Object?> details = const {}}) => switch (t) {
      SkyEventType.iss || SkyEventType.tiangong => (icon: Icons.satellite_alt_rounded, color: LookUpColors.blue),
      SkyEventType.satellitePass => (icon: Icons.satellite_alt_rounded, color: LookUpColors.cyan),
      SkyEventType.starlinkTrain => (icon: Icons.linear_scale_rounded, color: LookUpColors.violet),
      SkyEventType.auroraNow || SkyEventType.auroraOutlook => (icon: Icons.waves_rounded, color: LookUpColors.good),
      SkyEventType.meteorShower => (icon: Icons.auto_awesome_rounded, color: LookUpColors.orange),
      SkyEventType.lunarEclipse => (icon: Icons.dark_mode_rounded, color: LookUpColors.red),
      SkyEventType.planetPairing => (icon: Icons.workspaces_rounded, color: LookUpColors.gold),
      SkyEventType.planetHighlight => (icon: null, color: LookUpColors.gold),
      SkyEventType.skyObject => (icon: Icons.star_rounded, color: LookUpColors.gold),
      SkyEventType.favourite => (icon: Icons.favorite_rounded, color: LookUpColors.red),
      SkyEventType.milkyWayNight => (icon: Icons.blur_on_rounded, color: LookUpColors.violet),
      SkyEventType.rocketLaunch => (icon: Icons.rocket_launch_rounded, color: LookUpColors.red),
      SkyEventType.issTransit => (
          icon: details['body'] == 'Moon' ? Icons.nightlight_round : Icons.wb_sunny_rounded,
          color: LookUpColors.cyan,
        ),
      null => (icon: Icons.auto_awesome_rounded, color: LookUpColors.grey),
    };

/// A tinted rounded square with the event's icon, like an app's own glyph.
/// With no [icon] it draws a [PlanetMark].
class EventGlyph extends StatelessWidget {
  const EventGlyph({super.key, required this.icon, required this.color, this.size = 36, this.dim = false});

  factory EventGlyph.of(SkyEvent e, {Key? key, double size = 36, bool dim = false}) =>
      EventGlyph.forType(e.type, key: key, size: size, dim: dim, details: e.details);

  factory EventGlyph.forType(SkyEventType? t,
      {Key? key, double size = 36, bool dim = false, Map<String, Object?> details = const {}}) {
    final s = eventStyle(t, details: details);
    return EventGlyph(key: key, icon: s.icon, color: s.color, size: size, dim: dim);
  }

  final IconData? icon;
  final Color color;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final c = dim ? LookUpColors.greyDim : color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.3)),
      child: icon == null ? Center(child: PlanetMark(color: c, size: size * 0.62)) : Icon(icon, size: size * 0.52, color: c),
    );
  }
}

/// A planet with a tilted ring: reads as "planet", not "Earth".
class PlanetMark extends StatelessWidget {
  const PlanetMark({super.key, required this.color, this.size = 24});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _PlanetPainter(color)));
}

class _PlanetPainter extends CustomPainter {
  _PlanetPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final body = s.width * 0.27;
    final ring = Rect.fromCenter(center: Offset.zero, width: s.width * 0.98, height: s.width * 0.34);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.saveLayer(Offset.zero & s, Paint());
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.42);
    // Back half of the ring, the body over it, then the front half with a
    // thin gap cut around it so it reads as passing in front.
    canvas.drawArc(ring, math.pi, math.pi, false, stroke);
    canvas.drawCircle(Offset.zero, body, Paint()..color = color);
    final gap = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.strokeWidth * 2.6;
    canvas.drawArc(ring, 0, math.pi, false, gap);
    canvas.drawArc(ring, 0, math.pi, false, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlanetPainter o) => o.color != color;
}
