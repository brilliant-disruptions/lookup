/// Pip over the sky: the one way LookUp points you at something. Pip is the
/// thing, the ring is you. Pip flies to the target on a spring, waits at the
/// edge on the side to turn, trails sparks, and blinks (ticking the phone)
/// faster as you close in. When you're on it Pip pulls its trail in, bursts
/// once, the ring locks on and the phone taps once, hard.
///
/// The same in every mode, so a blink and a tap always mean the same thing:
/// the countdown before something comes up, the sky finder, and catching it
/// with the camera.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../domain/finder/firefly.dart';
import '../kit/firefly_mark.dart';
import '../kit/pip_greeting.dart';
import '../kit/pip_motion.dart' show PipGreeting;
import '../kit/reticle.dart';

export '../kit/firefly_mark.dart' show fireflyGlow, fireflyCore;

/// Where Pip is being used. Only changes the look around Pip, never how Pip
/// moves, blinks or buzzes.
enum PipMode { countdown, find, catchIt }

/// The phone's side of [PipBuzz]: a light tick per blink, one heavy tap on
/// lock, two when it appears.
class PipHaptics {
  Timer? _second;

  void play(PipBuzz b) {
    switch (b) {
      case PipBuzz.tick:
        HapticFeedback.selectionClick();
      case PipBuzz.lock:
        HapticFeedback.heavyImpact();
      case PipBuzz.appear:
        HapticFeedback.heavyImpact();
        _second?.cancel();
        _second = Timer(const Duration(milliseconds: 140), HapticFeedback.heavyImpact);
    }
  }

  void dispose() => _second?.cancel();
}

class PipAim extends StatefulWidget {
  const PipAim({
    super.key,
    required this.mode,
    required this.target,
    required this.toward,
    required this.distanceDeg,
    required this.onTarget,
    required this.words,
    this.label,
    this.appeared = true,
    this.canLock = true,
    this.ring = true,
    this.ringRadius = 44,
    this.launchFrom,
    this.homeward = false,
    this.homeScale = 52 / 48,
  });

  final PipMode mode;

  /// Where the target is on this layer, from its centre (x right, y down);
  /// null when it's behind you.
  final ({double x, double y})? target;

  /// Which way to turn when it isn't on screen.
  final ({double x, double y}) toward;
  final double distanceDeg;
  final bool onTarget;

  /// The guidance in words, for VoiceOver only ([Guidance.words]).
  final String words;

  /// Shown beside Pip once it's on the target: a landmark's name, a time.
  final String? label;

  /// Whether the thing is up yet; the moment it comes up, two taps.
  final bool appeared;

  /// False while Pip is only showing the way (flying the route): no lock.
  final bool canLock;

  /// Draw the ring in the middle. Off where the camera overlay has its own.
  final bool ring;
  final double ringRadius;

  /// Where Pip sets off from, from the centre (the sky camera's shutter, so
  /// it visibly leaves home to lead you); null starts it on its goal.
  final ({double x, double y})? launchFrom;

  /// Flying back to where it set off from (Close): it grows back into the
  /// character as it nears home.
  final bool homeward;

  /// How big the character is at home, in 48-pixel Pips (the button's).
  final double homeScale;

  @override
  State<PipAim> createState() => _PipAimState();
}

class _PipAimState extends State<PipAim> with SingleTickerProviderStateMixin {
  final _motion = FireflyMotion();
  final _trail = <Offset>[];
  final _cues = PipCues();
  final _haptics = PipHaptics();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  Duration _clock = Duration.zero;
  double _phase = 0; // 0…1 through the current blink
  Size _size = Size.zero;
  bool _placed = false;

  /// When it set off from [PipAim.launchFrom], on [_clock].
  double? _launchedAt;
  bool _still = false;
  int _ticks = 0;

  /// When it lined up, on [_clock], for the landing; null while searching.
  double? _landedAt;

  bool get _locked => widget.onTarget && widget.canLock;

  void _cue({bool blinked = false}) {
    for (final b in _cues.update(
        onTarget: widget.onTarget, appeared: widget.appeared, blinked: blinked, canLock: widget.canLock)) {
      _haptics.play(b);
    }
  }

  @override
  void initState() {
    super.initState();
    _cue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.of(context).disableAnimations;
    if (_still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(PipAim old) {
    super.didUpdateWidget(old);
    final wasLocked = old.onTarget && old.canLock;
    if (_locked && !wasLocked) _landedAt = _seconds;
    if (!_locked) _landedAt = null;
    _cue();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _haptics.dispose();
    super.dispose();
  }

  ({double x, double y, bool waiting}) _goal() => fireflyGoal(
        width: _size.width,
        height: _size.height,
        target: widget.target,
        toward: widget.toward,
      );

  /// A lazy blink while Pip only shows the way.
  Duration? get _blink => fireflyBlink(widget.canLock ? widget.distanceDeg : 40);

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _clock = elapsed;
    if (_size.isEmpty) return;
    final g = _goal();
    if (!_placed) {
      _motion.jumpTo(widget.launchFrom ?? (x: g.x, y: g.y));
      _placed = true;
      _launchedAt = _seconds;
    }
    _motion.step((x: g.x, y: g.y), dt);
    // A spark every other frame: about half a second of trail.
    if ((_ticks++).isEven) {
      _trail.add(Offset(_motion.x, _motion.y));
      if (_trail.length > 14) _trail.removeAt(0);
    }
    // Blink, and tick the phone at the top of each blink.
    final period = _blink;
    var blinked = false;
    if (period == null) {
      _phase = 0;
    } else {
      _phase += dt / (period.inMicroseconds / 1e6);
      if (_phase >= 1) {
        _phase %= 1;
        blinked = true;
      }
    }
    _cue(blinked: blinked);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: widget.words,
        excludeSemantics: true,
        child: LayoutBuilder(builder: (context, c) {
          _size = c.biggest;
          if (_still) {
            final g = _goal();
            _motion.jumpTo((x: g.x, y: g.y));
          } else if (!_placed) {
            final g = _goal();
            _motion.jumpTo(widget.launchFrom ?? (x: g.x, y: g.y));
          }
          final at = _size.center(Offset(_motion.x, _motion.y));
          final label = _locked || (widget.target != null && !_goal().waiting) ? widget.label : null;
          return Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _PipPainter(
                    at: at,
                    ring: widget.ring ? (radius: widget.ringRadius, on: _locked) : null,
                    trail: [for (final p in _trail) _size.center(p)],
                    blink: _blink == null ? 1 : 0.55 + 0.45 * math.cos(_phase * 2 * math.pi),
                    // Never still over the sky: a gentler hover once lined up.
                    wobble: _still ? Offset.zero : fireflyHover(_seconds, landed: _locked),
                    // Still (reduced motion): the ring is simply there.
                    sinceLanded: !_locked ? null : (_still || _landedAt == null ? 1.0 : _seconds - _landedAt!),
                    character: _character(),
                    seconds: _seconds,
                    homeScale: widget.homeScale,
                    look: _look(),
                  ),
                ),
              ),
            ),
            if (label != null)
              Positioned(
                // Beside Pip, but kept on screen near the edges.
                left: (at.dx - 90).clamp(8.0, math.max(8.0, _size.width - 188)),
                width: 180,
                top: at.dy + 24,
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: fireflyCore,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
              ),
          ]);
        }),
      );

  double get _seconds => _clock.inMicroseconds / 1e6;

  /// How much of the character is showing, 0 (the guiding dot) to 1: all of
  /// it as it leaves home, shrinking to the dot over half a second; and
  /// growing back as it nears home on the way back. Only when it came from
  /// somewhere ([PipAim.launchFrom]).
  double _character() {
    if (widget.launchFrom == null || _still) return 0;
    final out = _launchedAt == null ? 1.0 : (1 - (_seconds - _launchedAt!) / 0.45).clamp(0.0, 1.0);
    var back = 0.0;
    if (widget.homeward && widget.target != null) {
      final d = math.sqrt(math.pow(_motion.x - widget.target!.x, 2) + math.pow(_motion.y - widget.target!.y, 2));
      back = (1 - d / 140).clamp(0.0, 1.0);
    }
    return math.max(out, back);
  }

  /// Which way the character's eyes look: where it's flying.
  ({double x, double y}) _look() {
    final v = math.sqrt(_motion.vx * _motion.vx + _motion.vy * _motion.vy);
    if (v < 20) return (x: 0, y: 0);
    return (x: _motion.vx / v, y: _motion.vy / v);
  }
}

class _PipPainter extends CustomPainter {
  _PipPainter(
      {required this.at,
      required this.ring,
      required this.trail,
      required this.blink,
      required this.wobble,
      required this.sinceLanded,
      this.character = 0,
      this.seconds = 0,
      this.homeScale = 52 / 48,
      this.look = (x: 0, y: 0)});
  final Offset at;
  final ({double radius, bool on})? ring;
  final List<Offset> trail;
  final double blink; // 0…1
  final Offset wobble;

  /// Seconds since it lined up; null while searching.
  final double? sinceLanded;

  /// 0 the guiding dot, 1 the character (leaving home or coming back).
  final double character;
  final double seconds, homeScale;
  final ({double x, double y}) look;

  @override
  void paint(Canvas canvas, Size size) {
    if (ring case final r?) {
      paintReticle(canvas, size.center(Offset.zero), radius: r.radius, onTarget: r.on, strength: r.on ? 1 : 0.65);
    }
    // The trail pulls in over the first 0.3 s of lining up.
    final landed = sinceLanded;
    paintSparkTrail(canvas, trail, strength: landed == null ? 1 : (1 - landed / 0.3).clamp(0.0, 1.0));
    final p = at + wobble;
    if (character > 0) {
      paintPipGreeting(
        canvas,
        p,
        PipGreeting(grown: character, open: character, lookX: look.x, lookY: look.y, t: seconds),
        blink: blink,
        scale: 1 + (homeScale - 1) * character,
      );
    } else {
      paintFirefly(canvas, p, blink: blink);
    }
    if (landed != null) paintFireflyLanding(canvas, p, landed);
  }

  @override
  bool shouldRepaint(_PipPainter o) => true;
}
