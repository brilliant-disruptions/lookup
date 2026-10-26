import 'package:flutter/material.dart';

import '../../domain/models/sky_event.dart';
import '../theme.dart';

/// Each kind of event has one icon and one tint, used everywhere it shows
/// up: list glyphs, the hero card's glow, the Week tab.
({IconData icon, Color color}) eventStyle(SkyEventType? t, {Map<String, Object?> details = const {}}) => switch (t) {
      SkyEventType.iss || SkyEventType.tiangong => (icon: Icons.satellite_alt_rounded, color: LookUpColors.blue),
      SkyEventType.satellitePass => (icon: Icons.satellite_alt_rounded, color: LookUpColors.cyan),
      SkyEventType.starlinkTrain => (icon: Icons.linear_scale_rounded, color: LookUpColors.violet),
      SkyEventType.auroraNow || SkyEventType.auroraOutlook => (icon: Icons.waves_rounded, color: LookUpColors.good),
      SkyEventType.meteorShower => (icon: Icons.auto_awesome_rounded, color: LookUpColors.orange),
      SkyEventType.lunarEclipse => (icon: Icons.dark_mode_rounded, color: LookUpColors.red),
      SkyEventType.planetPairing => (icon: Icons.workspaces_rounded, color: LookUpColors.gold),
      SkyEventType.planetHighlight => (icon: Icons.public_rounded, color: LookUpColors.gold),
      SkyEventType.skyObject => (icon: Icons.star_rounded, color: LookUpColors.gold),
      SkyEventType.rocketLaunch => (icon: Icons.rocket_launch_rounded, color: LookUpColors.red),
      SkyEventType.issTransit => (
          icon: details['body'] == 'Moon' ? Icons.nightlight_round : Icons.wb_sunny_rounded,
          color: LookUpColors.cyan,
        ),
      null => (icon: Icons.auto_awesome_rounded, color: LookUpColors.grey),
    };

/// A tinted rounded square with the event's icon, like an app's own glyph.
class EventGlyph extends StatelessWidget {
  const EventGlyph({super.key, required this.icon, required this.color, this.size = 36, this.dim = false});

  factory EventGlyph.of(SkyEvent e, {Key? key, double size = 36, bool dim = false}) =>
      EventGlyph.forType(e.type, key: key, size: size, dim: dim, details: e.details);

  factory EventGlyph.forType(SkyEventType? t,
      {Key? key, double size = 36, bool dim = false, Map<String, Object?> details = const {}}) {
    final s = eventStyle(t, details: details);
    return EventGlyph(key: key, icon: s.icon, color: s.color, size: size, dim: dim);
  }

  final IconData icon;
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
      child: Icon(icon, size: size * 0.52, color: c),
    );
  }
}
