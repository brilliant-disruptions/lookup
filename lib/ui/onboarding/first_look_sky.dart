/// Onboarding's sky: their real sky (tonight, or right now if it's dark),
/// drawn the way the sky camera draws it, but turned by dragging instead of
/// by pointing the phone. Pip leads the way exactly as in the camera
/// (PipAim): it sets off as itself, becomes the dot, waits at the edge on
/// the side to turn and lands on the thing once it's in the middle. A tap
/// on Pip there is a practice catch: it never reaches the Log.
///
/// With [lockedTo] the view holds still (the space station preview, sped
/// up): Pip rides the pass and can be caught whenever it's on screen.
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/finder/firefly.dart' show towardOnScreen;
import '../../domain/finder/guide_target.dart';
import '../../domain/finder/pointing.dart';
import '../../domain/photo/framing.dart' show levelPose;
import '../../domain/sky/catalog.dart';
import '../../domain/sky/direction.dart';
import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../finder_camera.dart';
import '../format.dart';
import '../pip/pip_aim.dart';
import '../sky/sky_thing.dart';
import '../sky/sky_track.dart';
import '../theme.dart';

/// What Pip can find in their sky (the Moon, planets, showpieces) and
/// tonight's dark hours; null without a place. Tests fill it directly.
final firstLookProvider = FutureProvider<({List<SkyThing> things, ({DateTime start, DateTime end})? window})?>((ref) async {
  final s = await ref.watch(settingsProvider.future);
  final p = await ref.watch(tonightSkyProvider.future);
  if (p == null || !s.hasLocation) return null;
  final lat = s.latitude!, lon = s.longitude!;
  return (
    things: [
      SkyThing.moon(p.moon, lat, lon),
      for (final x in p.planets) SkyThing.planet(x, lat, lon),
      for (final x in p.showpieces) SkyThing.showpiece(x, lat, lon),
    ],
    window: p.window,
  );
});

/// How close (degrees) counts as "in the middle": the sky camera's lock.
const firstLookLockDeg = 10.0;

class FirstLookSky extends StatefulWidget {
  const FirstLookSky({
    super.key,
    required this.things,
    required this.lat,
    required this.lon,
    required this.clock,
    required this.onCatch,
    this.tracks = const [],
    this.start = const SkyDir(180, 28),
    this.lockedTo,
    this.leadId,
    this.catalog,
    this.enabled = true,
    this.onStatus,
  });

  final List<SkyThing> things;
  final List<SkyTrack> tracks;
  final double lat, lon;

  /// The sky's moment: tonight, or a pass running sped up.
  final DateTime Function() clock;

  /// Where the view starts.
  final SkyDir start;

  /// A fixed view (the pass preview): no dragging.
  final SkyDir? lockedTo;

  /// What Pip leads to; null lets it choose as the camera does
  /// (domain/finder/guide_target.dart).
  final String? leadId;
  final SkyCatalog? catalog;

  /// False once caught: Pip stays put and taps do nothing.
  final bool enabled;

  /// A tap on Pip while it's on something: its id and name.
  final void Function(String id, String name) onCatch;

  /// What Pip is leading to, and whether it's on it, whenever that changes
  /// (for the page's words).
  final void Function(String? name, bool onTarget)? onStatus;

  @override
  State<FirstLookSky> createState() => _FirstLookSkyState();
}

class _FirstLookSkyState extends State<FirstLookSky> with SingleTickerProviderStateMixin {
  late SkyDir _look = widget.lockedTo ?? widget.start;
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  String? _name;
  bool _on = false;

  @override
  void initState() {
    super.initState();
    // The pass preview moves by itself; a still sky only redraws on a drag.
    if (widget.lockedTo != null) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails d, double pxPerDeg) {
    if (widget.lockedTo != null || !widget.enabled) return;
    setState(() {
      _look = SkyDir(
        (_look.azimuthDeg - d.delta.dx / pxPerDeg) % 360,
        (_look.elevationDeg + d.delta.dy / pxPerDeg).clamp(8.0, 75.0),
      );
    });
  }

  /// Arrow keys turn the sky too (keyboards, switch access).
  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (widget.lockedTo != null || e is KeyUpEvent) return KeyEventResult.ignored;
    final step = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowLeft => (-5.0, 0.0),
      LogicalKeyboardKey.arrowRight => (5.0, 0.0),
      LogicalKeyboardKey.arrowUp => (0.0, 5.0),
      LogicalKeyboardKey.arrowDown => (0.0, -5.0),
      _ => null,
    };
    if (step == null) return KeyEventResult.ignored;
    setState(() => _look = SkyDir((_look.azimuthDeg + step.$1) % 360, (_look.elevationDeg + step.$2).clamp(8.0, 75.0)));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final utc = widget.clock().toUtc();
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final r = levelPose(_look);
      // Pixels per degree at the middle of the view (the camera's 66° tall).
      final f = (size.height / 2) / math.tan(33 * math.pi / 180);
      final pxPerDeg = f * math.pi / 180;
      final mapped = [
        for (final t in widget.things)
          if (t.position(utc) case final h when h.altitudeDeg > -1)
            (thing: t, mark: (label: t.id == 'moon' ? 'Moon' : t.name, d: SkyDir(h.azimuthDeg, h.altitudeDeg), bright: t.id == 'moon' || t.kind == 'Planet')),
      ];
      final tracks = <OverlayTrack>[
        for (final tr in widget.tracks)
          (
            label: eventTitle(tr.event),
            path: [for (final p in tr.points) (t: p.t, d: SkyDir(p.h.azimuthDeg, p.h.altitudeDeg))],
            now: switch (tr.at(utc)) { final h? => SkyDir(h.azimuthDeg, h.altitudeDeg), null => null },
            color: tr.color,
          ),
      ];
      final guides = <String, ({String name, SkyDir d})>{
        for (final tr in widget.tracks)
          if (tr.at(utc) case final h?) tr.event.id: (name: 'the space station', d: SkyDir(h.azimuthDeg, h.altitudeDeg)),
        for (final m in mapped) m.thing.id: (name: m.mark.label == 'Moon' ? 'the Moon' : m.mark.label, d: m.mark.d),
      };
      final aimId = widget.leadId ??
          guideTarget([
            for (final m in mapped)
              GuideCandidate(
                id: m.thing.id,
                kind: m.thing.id == 'moon' ? 'moon' : (m.thing.kind == 'Planet' ? 'planet' : 'other'),
                mag: m.thing.mag,
                altitudeDeg: m.mark.d.elevationDeg,
              ),
          ])?.id;
      final target = aimId == null ? null : guides[aimId];
      final g = target == null ? null : guide(_look, target.d, toleranceDeg: firstLookLockDeg);
      final p = target == null ? null : projectToScreen(r, target.d, declinationDeg: 0, previewHeightPx: size.height);
      final visible = p != null && p.x.abs() < size.width / 2 - 24 && p.y.abs() < size.height / 2 - 24;
      // A still sky: in the middle. The pass preview: anywhere on screen.
      final on = g != null && (widget.lockedTo != null ? visible : g.onTarget);
      if (target?.name != _name || on != _on) {
        _name = target?.name;
        _on = on;
        final name = _name;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onStatus?.call(name, on);
        });
      }
      // The horizon, for the ground.
      final horizon = projectToScreen(r, SkyDir(_look.azimuthDeg, 0), declinationDeg: 0, previewHeightPx: size.height);
      return Focus(
        autofocus: widget.lockedTo == null,
        onKeyEvent: _key,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (d) => _drag(d, pxPerDeg),
          child: Stack(children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF03050C), Color(0xFF0B1328), Color(0xFF16213E)],
                    stops: [0, 0.65, 1],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                key: const Key('first-look-sky'),
                painter: SkyOverlayPainter(
                  r: r,
                  declinationDeg: 0,
                  now: utc,
                  previewHeightPx: size.height,
                  labelStyle: Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
                  catalog: widget.catalog,
                  latDeg: widget.lat,
                  lonDeg: widget.lon,
                  tracks: tracks,
                  marks: [for (final m in mapped) m.mark],
                ),
              ),
            ),
            if (horizon != null)
              Positioned.fill(child: CustomPaint(painter: _Ground(horizonY: size.height / 2 + horizon.y, look: _look, pxPerDeg: pxPerDeg))),
            if (g != null && target != null && widget.enabled)
              Positioned.fill(
                child: PipAim(
                  key: const Key('first-look-pip'),
                  mode: PipMode.find,
                  target: p,
                  toward: towardOnScreen(g),
                  distanceDeg: g.distanceDeg,
                  onTarget: on,
                  words: '${g.words} for ${target.name}',
                  ring: false,
                  // Sets off from where Pip said hello, above the middle.
                  launchFrom: (x: 0, y: -size.height * 0.12),
                ),
              ),
            if (on && widget.enabled && p != null)
              Positioned(
                left: size.width / 2 + p.x - 60,
                top: size.height / 2 + p.y - 60,
                child: Semantics(
                  button: true,
                  label: 'Catch ${target!.name}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    key: const Key('first-look-catch'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      widget.onCatch(aimId!, target.name);
                    },
                    child: const SizedBox.square(dimension: 120),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

/// The ground below the horizon, a soft line of hills, and the compass
/// words along it (no degrees).
class _Ground extends CustomPainter {
  _Ground({required this.horizonY, required this.look, required this.pxPerDeg});
  final double horizonY, pxPerDeg;
  final SkyDir look;

  @override
  void paint(Canvas canvas, Size size) {
    if (horizonY > size.height + 40) return;
    final shift = look.azimuthDeg * pxPerDeg;
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= size.width; x += 6) {
      final u = x + shift;
      path.lineTo(x, horizonY - math.max(0, math.sin(u * 0.013) * 9 + math.sin(u * 0.041) * 5 + math.sin(u * 0.11) * 2));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF04060B));
    for (var az = 0; az < 360; az += 45) {
      final d = ((az - look.azimuthDeg + 540) % 360) - 180;
      final x = size.width / 2 + d * pxPerDeg;
      if (x < 16 || x > size.width - 16) continue;
      final tp = TextPainter(
        text: TextSpan(text: compassWord(az.toDouble()), style: display(12, weight: FontWeight.w600, color: LookUpColors.grey)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, horizonY + 14));
    }
  }

  @override
  bool shouldRepaint(_Ground o) => o.horizonY != horizonY || o.look != look;
}
