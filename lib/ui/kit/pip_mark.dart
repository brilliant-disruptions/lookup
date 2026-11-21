/// Pip off the finder: the same light [paintFirefly] draws in alerts and on
/// the sky, as a widget for every other screen. Here Pip is the character:
/// a soft orb with eyes that breathes, glances, blinks, jiggles and squishes
/// when touched (pip_motion.dart, pip_greeting.dart); [PipMark.asDot] is the
/// plain light, for Pip marking a spot in a picture of the sky. Kept out of
/// firefly_mark.dart, which must stay `dart:ui` only for the alert isolate.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import 'firefly_mark.dart';
import 'pip_greeting.dart';
import 'pip_motion.dart';

export 'pip_motion.dart' show PipMood, PipState;

class PipMark extends StatefulWidget {
  const PipMark({
    super.key,
    this.state = PipState.idle,
    this.size = 48,
    this.dim = false,
    this.blinking = false,
    this.flyFrom,
    this.replay = 0,
    this.asDot = false,
    this.poke = 0,
    this.mood = PipMood.calm,
    this.moodFor,
  });

  /// What Pip is doing. [PipState.hello], [PipState.found] and
  /// [PipState.greet] play once each time Pip changes to them, then Pip rests.
  final PipState state;

  /// The square Pip hovers in; Pip itself is drawn at a scale of size / 48.
  final double size;

  /// Can't see: as when you said no to location, or there's no sensor.
  /// Smaller and dimmer, and it looks one way, then the other.
  final bool dim;

  /// Blinking quickly, as it does before a tap.
  final bool blinking;

  /// When set, Pip flies in from this offset (relative to its own place)
  /// trailing sparks, stretched by the speed, and lands with a squash.
  final Offset? flyFrom;

  /// Change it to play [state] again from the start (another hello).
  final int replay;

  /// The plain dot of light, not the character: for Pip marking a spot in
  /// a picture of the sky, where it's showing you where to look.
  final bool asDot;

  /// Change it when Pip is touched: it squishes, wobbles and squints.
  final int poke;

  /// How Pip feels, in its eyes ([PipMood]). A change eases in.
  final PipMood mood;

  /// With a time, the feeling passes and Pip drifts back to calm.
  final Duration? moodFor;

  @override
  State<PipMark> createState() => _PipMarkState();
}

class _PipMarkState extends State<PipMark> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(
    (e) => setState(() => _t = e.inMicroseconds / 1e6),
  );
  double _t = 0;
  double _flewAt = 0;
  double _stateAt = 0;
  double _pokeAt = -1e9;
  double _moodAt = 0;
  PipMood _fromMood = PipMood.calm;
  bool _still = false;

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
  void didUpdateWidget(PipMark old) {
    super.didUpdateWidget(old);
    if (widget.flyFrom != old.flyFrom) _flewAt = _t;
    if (widget.state != old.state || widget.replay != old.replay) _stateAt = _t;
    if (widget.poke != old.poke) _pokeAt = _t;
    if (widget.mood != old.mood) {
      _fromMood = _moodNow(old).$1;
      _moodAt = _t;
    }
  }

  /// The feeling now (it passes after [PipMark.moodFor]), the one it's
  /// coming from, and how long since it changed.
  (PipMood, PipMood, double) _moodNow(PipMark w) {
    final since = _t - _moodAt;
    final d = w.moodFor;
    if (d != null && since > d.inMicroseconds / 1e6) return (PipMood.calm, w.mood, since - d.inMicroseconds / 1e6);
    return (w.mood, _fromMood, since);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: PipMarkPainter(
          state: widget.state,
          seconds: _t,
          sinceState: _t - _stateAt,
          still: _still,
          dim: widget.dim,
          blinking: widget.blinking,
          flyFrom: widget.flyFrom,
          sinceFlew: _still ? null : _t - _flewAt,
          asDot: widget.asDot,
          sincePoke: _t - _pokeAt,
          mood: _moodNow(widget).$1,
          fromMood: _moodNow(widget).$2,
          sinceMood: _moodNow(widget).$3,
        ),
      ),
    ),
  );
}

/// How long a [PipMark.flyFrom] flight takes.
const pipFlight = 0.9;

/// When the character's found-it ring has faded away (seconds).
const pipFoundRingFade = 1.1;

class PipMarkPainter extends CustomPainter {
  PipMarkPainter({
    required this.state,
    required this.seconds,
    this.sinceState = 1e9,
    this.still = false,
    this.dim = false,
    this.blinking = false,
    this.flyFrom,
    this.sinceFlew,
    this.asDot = false,
    this.sincePoke = 1e9,
    this.mood = PipMood.calm,
    this.fromMood = PipMood.calm,
    this.sinceMood = 1e9,
  });
  final PipState state;
  final double seconds, sinceState, sincePoke, sinceMood;
  final PipMood mood, fromMood;
  final bool still, dim, blinking, asDot;
  final Offset? flyFrom;
  final double? sinceFlew;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    final home = size.center(Offset.zero);
    var pose = pipPose(state, seconds, since: sinceState, dim: dim, blinking: blinking, still: still, character: !asDot);
    var at = home + pose.offset * scale;
    final from = flyFrom;
    final f = sinceFlew;
    if (from != null && f != null) {
      pose = pipFlightPose(pose, from, f, pipFlight);
      if (f < pipFlight) {
        final k = Curves.easeInOutCubic.transform(f / pipFlight);
        final start = home + from;
        at = Offset.lerp(start, at, k)!;
        paintSparkTrail(canvas, fireflyCurl(at, start), scale: scale, strength: 1 - k);
      }
    }
    // The lock ring and burst when it's found something. Marking a spot (the
    // dot) the ring stays; the character only flashes it, then it fades.
    if (state == PipState.found && !dim) {
      if (asDot) {
        paintFireflyLanding(canvas, home, still ? 1 : sinceState, scale: scale * 0.9);
      } else if (!still && sinceState < pipFoundRingFade) {
        final fade = (1 - (sinceState - 0.6) / (pipFoundRingFade - 0.6)).clamp(0.0, 1.0);
        canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, fade));
        paintFireflyLanding(canvas, home, sinceState, scale: scale * 0.9);
        canvas.restore();
      }
    }
    final s = scale * pose.size;
    final greeting = state == PipState.greet && sinceState < pipGreetLength;
    // The dot in a picture of the sky; everywhere else the character, at
    // rest or saying hi.
    final hi = asDot
        ? (greeting ? pipGreeting(sinceState, still: still, fromDot: true) : const PipGreeting())
        : (greeting
            ? pipGreeting(sinceState, still: still)
            // "Can't see" (dim) is sorry; otherwise the feeling it was given.
            : pipCharacter(seconds,
                sincePoke: sincePoke,
                still: still,
                mood: dim ? PipMood.sorry : mood,
                from: dim ? PipMood.sorry : fromMood,
                sinceMood: sinceMood));
    void draw(Canvas c, double blink) {
      if (hi.dot) {
        paintFirefly(c, at, blink: blink, scale: s, stretch: pose.stretch, squash: pose.squash, angle: pose.angle);
        return;
      }
      // Squash and stretch apply to the character too.
      c
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(pose.angle)
        ..scale(pose.stretch, pose.squash)
        ..rotate(-pose.angle);
      paintPipGreeting(c, Offset.zero, hi, blink: blink, scale: s);
      c.restore();
    }
    if (dim || pose.opacity < 1) {
      final a = (dim ? 0.35 : 1) * pose.opacity;
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
      draw(canvas, pose.blink);
      canvas.restore();
    } else {
      draw(canvas, pose.blink);
    }
  }

  @override
  bool shouldRepaint(PipMarkPainter o) => true;
}
