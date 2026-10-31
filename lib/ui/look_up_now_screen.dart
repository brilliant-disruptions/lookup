import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/finder/look_up_now.dart';
import '../domain/finder/pointing.dart';
import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../domain/sky/wmm.dart';
import '../services/orientation.dart';
import '../state/providers.dart';
import 'finder_screen.dart';
import 'format.dart';
import 'night_vision_button.dart';
import 'kit/kit.dart';
import 'theme.dart';

/// Ids already taken over this session, so closing it means closed.
final _shown = <String>{};

/// From Tonight: take over the screen if [e] is in its last two minutes and
/// hasn't been shown yet. Returns whether it opened.
bool maybeOpenLookUpNow(BuildContext context, SkyEvent e, DateTime now) {
  if (!LookUpNow.due(e, now) || _shown.contains(e.id)) return false;
  _shown.add(e.id);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => LookUpNowScreen(event: e),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  });
  return true;
}

/// The final stretch, full screen: a seconds countdown, an arrow that turns
/// with the phone toward where it'll appear, and the hand-off to the finder
/// the moment it does. Big type, few words: it's read outside, in the dark.
class LookUpNowScreen extends ConsumerStatefulWidget {
  const LookUpNowScreen({super.key, required this.event, this.orientationStream});
  final SkyEvent event;

  /// For tests; otherwise the phone's rotation sensor.
  final Stream<List<double>>? orientationStream;

  @override
  ConsumerState<LookUpNowScreen> createState() => _LookUpNowState();
}

class _LookUpNowState extends ConsumerState<LookUpNowScreen> {
  StreamSubscription<List<double>>? _sub;
  double? _facing;
  double _declination = 0;
  bool _handedOff = false;

  SkyEvent get e => widget.event;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider).value;
    if (s?.latitude != null) _declination = declinationDeg(s!.latitude!, s.longitude!, DateTime.now().toUtc());
    try {
      _sub = (widget.orientationStream ?? deviceRotation())?.listen((r) {
        final f = facingAzimuth(r, declinationDeg: _declination);
        // Smooth the needle: ease a quarter of the way each reading.
        final next = _facing == null ? f : (_facing! + azimuthDelta(_facing!, f) * 0.25) % 360;
        if (_facing == null || azimuthDelta(_facing!, next).abs() > 0.5) setState(() => _facing = next);
      }, onError: (_) {});
    } catch (_) {
      // No compass: the words and the static direction still do the job.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _toFinder() {
    if (_handedOff) return;
    _handedOff = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(fullscreenDialog: true, builder: (_) => FinderScreen(event: e)));
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final until = e.start.difference(now.toUtc());
    final tint = eventStyle(e.type, details: e.details).color;
    if (until <= Duration.zero && !_handedOff) {
      // It's up: buzz and follow it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        _toFinder();
      });
    }
    final delta = _facing == null ? null : azimuthDelta(_facing!, e.riseAzimuthDeg);
    final facingIt = delta != null && delta.abs() <= 15;
    final brightness = e.details['brightness'];
    return OutsideScreen(
      child: Scaffold(
        body: SkyBackdrop(
          glow: tint,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Kicker('Get ready', color: tint, live: true),
                      const Spacer(),
                      const NightVisionButton(),
                      const SizedBox(width: 8),
                      CircleButton(icon: Icons.close_rounded, tooltip: 'Close', onPressed: () => Navigator.of(context).maybePop()),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    eventTitle(e),
                    style: display(22, weight: FontWeight.w600, color: LookUpColors.grey),
                  ),
                  Semantics(
                    liveRegion: true,
                    label: '${LookUpNow.clock(until)} until it appears',
                    excludeSemantics: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(LookUpNow.clock(until), style: numeric(size: 112, weight: FontWeight.w700)),
                    ),
                  ),
                  const Text('until it appears', style: TextStyle(fontSize: 16, color: LookUpColors.grey)),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Semantics(
                          label: delta == null ? 'Face ${compassWord(e.riseAzimuthDeg)}' : LookUpNow.turn(delta),
                          excludeSemantics: true,
                          child: CustomPaint(
                            painter: _TurnDial(deltaDeg: delta, targetAz: e.riseAzimuthDeg, tint: tint),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    delta == null ? 'Face ${compassWord(e.riseAzimuthDeg)}' : LookUpNow.turn(delta),
                    textAlign: TextAlign.center,
                    style: display(30, weight: FontWeight.w700, color: facingIt ? tint : LookUpColors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'It appears in the ${compassWord(e.riseAzimuthDeg)} and climbs ${elevationWord(e.peakElevationDeg)}.'
                    '${brightness is String ? ' A steady moving light, $brightness.' : ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15.5, color: LookUpColors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _toFinder,
                    icon: const Icon(Icons.explore_rounded),
                    label: const Text('Open the sky finder'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring with an arrow: straight up is the way you're facing, the arrow
/// points to where it'll appear. Without a compass, a plain dial with the
/// direction marked. Facing it, the ring lights up in the event's colour.
class _TurnDial extends CustomPainter {
  _TurnDial({required this.deltaDeg, required this.targetAz, required this.tint});
  final double? deltaDeg;
  final double targetAz;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 10;
    final facing = deltaDeg != null && deltaDeg!.abs() <= 15;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = facing ? 5 : 2
        ..color = facing ? tint : LookUpColors.line,
    );
    if (facing) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [tint.withValues(alpha: 0.28), tint.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
    // Ticks every 30°, the one ahead brighter.
    for (var k = 0; k < 12; k++) {
      final a = k * math.pi / 6;
      final dir = Offset(math.sin(a), -math.cos(a));
      canvas.drawLine(
        c + dir * (r - 12),
        c + dir * (r - (k == 0 ? 26 : 18)),
        Paint()
          ..strokeWidth = k == 0 ? 3 : 1.5
          ..strokeCap = StrokeCap.round
          ..color = k == 0 ? LookUpColors.white : LookUpColors.greyDim,
      );
    }
    // The arrow: relative to where you face, or (no compass) as on a map, north up.
    final angle = (deltaDeg ?? targetAz) * math.pi / 180;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final len = r * 0.72;
    final shaft = Paint()
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [tint.withValues(alpha: 0.15), tint],
      ).createShader(Rect.fromLTRB(-6, -len, 6, len * 0.2));
    canvas.drawLine(Offset(0, len * 0.2), Offset(0, -len + 22), shaft);
    final head = Path()
      ..moveTo(0, -len - 6)
      ..lineTo(22, -len + 30)
      ..lineTo(-22, -len + 30)
      ..close();
    canvas.drawPath(head, Paint()..color = tint);
    canvas.restore();
    // Where it'll appear, at the arrow's tip: the firefly, with its sparks
    // trailing round the ring from where you face. Facing it, no trail.
    final tip = c + Offset(math.sin(angle), -math.cos(angle)) * r;
    if (!facing) {
      final a = math.atan2(math.sin(angle), math.cos(angle)); // -π…π
      final sweep = a.sign * math.min(a.abs(), 50 * math.pi / 180);
      const n = 12;
      paintSparkTrail(
        canvas,
        [
          for (var i = 0; i < n; i++)
            c + Offset(math.sin(a - sweep * (1 - i / n)), -math.cos(a - sweep * (1 - i / n))) * r,
        ],
        scale: 1.3,
      );
    }
    paintFirefly(canvas, tip, blink: 0.8, scale: 1.3);
    if (deltaDeg == null) {
      // Map mode: mark north so the arrow reads as a bearing.
      final tp = TextPainter(
        text: const TextSpan(
          text: 'N',
          style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w700, color: LookUpColors.grey),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + Offset(-tp.width / 2, -r + 30));
    }
  }

  @override
  bool shouldRepaint(_TurnDial old) => old.deltaDeg != deltaDeg || old.targetAz != targetAz || old.tint != tint;
}
