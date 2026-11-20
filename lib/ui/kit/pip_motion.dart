/// How Pip moves. Most of the time Pip is just the light: a green dot whose
/// character is all in how it moves, squashes and flashes. Now and then it
/// grows out of the dot into a little glowing figure (two eyes, a smile,
/// two soft hands), waves, and melts back into the dot ([PipState.wave],
/// [pipFigure]). This file is the whole vocabulary, as plain maths over
/// time, so it can be tested without a widget and stays `dart:ui` only.
///
/// Offsets are in the units of a 48-pixel Pip (the painter multiplies by
/// size / 48). [PipPose.stretch] is along [PipPose.angle]: 1.2 is 20% longer
/// that way, and [PipPose.squash] is across it.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'firefly_mark.dart';

/// What Pip is doing.
/// - [idle]: waiting. Hovers and flashes slowly, like a firefly.
/// - [searching]: looking for something. Circles, stretched along its path.
/// - [resting]: settled on something. Sits a little flattened, dimmer, and
///   glows now and then.
/// - [hello]: the first time you meet it. Drops in, lands with a squash and a
///   bounce, blinks twice, then rests.
/// - [found]: you lined up. A flare, a ring and a little hop, then it rests
///   inside the ring.
/// - [wave]: hi. Grows a face and hands out of the dot, waves, then goes
///   back to being a dot ([pipFigure]), and rests.
enum PipState { idle, searching, resting, hello, found, wave }

/// Where Pip is and what shape it has at one moment.
class PipPose {
  const PipPose({
    this.offset = Offset.zero,
    this.stretch = 1,
    this.squash = 1,
    this.angle = 0,
    this.blink = 1,
    this.size = 1,
    this.opacity = 1,
  });

  /// From its home spot, in 48-pixel Pip units.
  final Offset offset;

  /// Length along [angle] and width across it; 1 is round.
  final double stretch, squash;

  /// Radians; which way [stretch] points.
  final double angle;

  /// How bright the flash is right now, 0…1, as [paintFirefly] takes it.
  final double blink;

  /// Overall size; 1 is a normal Pip.
  final double size;

  /// Fades it in as it arrives.
  final double opacity;

  bool get round => stretch == 1 && squash == 1;
}

/// How long [PipState.hello] takes before Pip is resting.
const pipHelloLength = 2.0;

/// How long the [PipState.found] hop takes before Pip is resting.
const pipFoundLength = 0.8;

/// How far [PipState.searching] circles, in Pip units.
const pipSearchRadius = 14.4;

/// Pip's pose [seconds] into its life and [since] seconds into [state].
/// [dim] is "can't see": no location, no sensor, or cloud. [blinking] is the
/// quick flash before a tap. [still] is Reduce Motion: a steady, round light.
PipPose pipPose(
  PipState state,
  double seconds, {
  double since = 1e9,
  bool dim = false,
  bool blinking = false,
  bool still = false,
}) {
  if (still) return PipPose(size: dim ? 0.8 : 1, blink: dim ? 0.6 : 1);
  var p = switch (state) {
    PipState.idle => _idle(seconds),
    PipState.searching => _searching(seconds),
    PipState.resting => _resting(seconds),
    PipState.hello => since < pipHelloLength ? _hello(seconds, since) : _resting(seconds),
    PipState.found => since < pipFoundLength ? _found(seconds, since) : _resting(seconds),
    // The figure does the moving; the light only hovers gently under it.
    PipState.wave => since < pipWaveLength ? PipPose(offset: fireflyHover(seconds, landed: true)) : _resting(seconds),
  };
  if (blinking) p = _with(p, blink: 0.55 + 0.45 * math.cos(seconds * 2 * math.pi * 2.5));
  if (dim) p = _cantSee(p, seconds);
  return p;
}

/// The slow firefly flash: a quick rise and a long fade, every 1.6 s.
double _flash(double seconds) => 0.55 + 0.45 * math.cos(seconds * 2 * math.pi / 1.6);

PipPose _idle(double s) => PipPose(offset: fireflyHover(s), blink: _flash(s));

PipPose _searching(double s) {
  final a = s * 2.4;
  return PipPose(
    offset: Offset(math.cos(a), math.sin(a)) * pipSearchRadius,
    // Moving round the circle: along the tangent.
    angle: a + math.pi / 2,
    stretch: 1.25,
    squash: 0.82,
    blink: _flash(s),
  );
}

PipPose _resting(double s) {
  // A soft glow every 5 s, over a dimmer base.
  final ph = (s % 5) / 5;
  final glow = ph < 0.2 ? math.sin(ph / 0.2 * math.pi) : 0.0;
  return PipPose(
    offset: fireflyHover(s, landed: true),
    stretch: 1.1, // across: sits flatter
    squash: 0.9,
    blink: 0.7 + 0.3 * glow,
  );
}

PipPose _hello(double s, double t) {
  if (t < 0.55) {
    // Falling in, stretched by the speed of it.
    final k = t / 0.55;
    return PipPose(
      offset: Offset(0, -90 * (1 - k * k)),
      angle: math.pi / 2,
      stretch: 1.22,
      squash: 0.84,
      opacity: math.min(1, t / 0.2),
    );
  }
  // Landed: one bounce, squash and stretch settling to round.
  final b = t < 1.0 ? -20 * math.sin((t - 0.55) / 0.45 * math.pi) : 0.0;
  final (st, sq) = _keys(t, const [
    (0.55, 0.74, 1.28), // squashed flat on landing (along the fall: short)
    (0.70, 1.12, 0.90),
    (0.90, 0.93, 1.08),
    (1.05, 1.0, 1.0),
  ]);
  // Two quick blinks: hi.
  final blink = _blinks(t, const [1.45, 1.70]);
  // Eases into its hover as it settles.
  final hover = fireflyHover(s, landed: true) * ((t - 1.0) / 1.0).clamp(0.0, 1.0);
  return PipPose(offset: Offset(0, b) + hover, angle: math.pi / 2, stretch: st, squash: sq, blink: blink);
}

PipPose _found(double s, double t) {
  // A flare, then a hop.
  final (sz, _) = _keys(t, const [(0.0, 1.0, 0), (0.08, 1.32, 0), (0.25, 0.94, 0), (0.35, 1.0, 0)]);
  final hop = t > 0.3 && t < 0.62 ? -12 * math.sin((t - 0.3) / 0.32 * math.pi) : 0.0;
  final (st, sq) = _keys(t, const [(0.3, 1.0, 1.0), (0.46, 1.1, 0.92), (0.62, 0.9, 1.1), (0.75, 1.0, 1.0)]);
  return PipPose(
    offset: Offset(0, hop),
    angle: math.pi / 2,
    stretch: st,
    squash: sq,
    size: sz,
    blink: t < 0.25 ? 1 : 0.85,
  );
}

/// Can't see: smaller and dimmer, it looks one way, then the other.
PipPose _cantSee(PipPose p, double s) {
  final ph = (s % 4.4) / 4.4;
  final (x, _) = _keys(ph, const [(0.1, 0, 0), (0.24, -10, 0), (0.4, -10, 0), (0.56, 10, 0), (0.72, 10, 0), (0.88, 0, 0)]);
  return _with(p, offset: p.offset + Offset(x, 0), size: p.size * 0.8, blink: p.blink * 0.6);
}

PipPose _with(PipPose p, {Offset? offset, double? blink, double? size}) => PipPose(
      offset: offset ?? p.offset,
      stretch: p.stretch,
      squash: p.squash,
      angle: p.angle,
      blink: blink ?? p.blink,
      size: size ?? p.size,
      opacity: p.opacity,
    );

/// The flight in from [PipMark.flyFrom]: stretched along the way it's
/// going, then a squash as it lands [since] seconds after setting off.
PipPose pipFlightPose(PipPose p, Offset from, double since, double flight) {
  final angle = math.atan2(-from.dy, -from.dx);
  if (since < flight) {
    return PipPose(offset: p.offset, angle: angle, stretch: 1.25, squash: 0.82, blink: p.blink, size: p.size);
  }
  final t = since - flight;
  if (t > 0.45) return p;
  final (st, sq) = _keys(t, const [(0, 0.74, 1.3), (0.18, 1.12, 0.9), (0.32, 0.96, 1.04), (0.45, 1.0, 1.0)]);
  return PipPose(offset: p.offset, angle: angle, stretch: st, squash: sq, blink: p.blink, size: p.size);
}

/// Piecewise-linear keys (time, a, b) → (a, b) at [t]; held at either end.
(double, double) _keys(double t, List<(double, double, double)> k) {
  if (t <= k.first.$1) return (k.first.$2, k.first.$3);
  for (var i = 1; i < k.length; i++) {
    if (t <= k[i].$1) {
      final f = (t - k[i - 1].$1) / (k[i].$1 - k[i - 1].$1);
      return (lerpDouble(k[i - 1].$2, k[i].$2, f)!, lerpDouble(k[i - 1].$3, k[i].$3, f)!);
    }
  }
  return (k.last.$2, k.last.$3);
}

/// Full brightness with a quick dip to almost dark at each of [at].
double _blinks(double t, List<double> at) {
  var b = 1.0;
  for (final c in at) {
    final d = (t - c).abs();
    if (d < 0.1) b = math.min(b, 0.1 + 0.9 * d / 0.1);
  }
  return b;
}

/// How long a wave takes: growing out of the dot, waving, melting back.
const pipWaveLength = 3.2;

/// When, inside a wave, Pip is fully grown, and when it starts to melt.
const _grownBy = 0.7, _meltFrom = 2.5;

/// Pip as a figure for a moment. [grown] is how far it has come out of the
/// dot: 0 is the plain light, 1 is the whole figure (it overshoots a little
/// as it pops out, like a drop landing). [hand] is how far the waving hand
/// is tipped from upright, in radians; [eyes] is 1 open, 0 shut; [lean] is
/// how the body sways with the wave, in radians.
class PipFigure {
  const PipFigure({this.grown = 0, this.hand = 0, this.eyes = 1, this.lean = 0});
  final double grown, hand, eyes, lean;

  /// Just the dot: nothing to draw but the light.
  bool get dot => grown <= 0;
}

/// The figure [since] seconds into a [PipState.wave]. Past [pipWaveLength]
/// it's a dot again. [still] is Reduce Motion: the face is simply there for
/// the length of the wave, with no growing, waving or blinking.
PipFigure pipFigure(double since, {bool still = false}) {
  if (since < 0 || since >= pipWaveLength) return const PipFigure();
  if (still) return const PipFigure(grown: 1);
  final double grown;
  if (since < _grownBy) {
    grown = _backOut(since / _grownBy);
  } else if (since < _meltFrom) {
    grown = 1;
  } else {
    final k = (since - _meltFrom) / (pipWaveLength - _meltFrom);
    grown = 1 - k * k * (3 - 2 * k); // smoothstep down to the dot
  }
  // Waves twice a second while it's out, easing in and out with the growing.
  final out = since < _grownBy ? 0.0 : (since < _meltFrom ? 1.0 : grown);
  final swing = math.sin((since - _grownBy) * 2 * math.pi * 2) * out;
  return PipFigure(
    grown: grown,
    hand: 0.55 * swing,
    lean: 0.07 * swing,
    eyes: _blinks(since, const [1.75]).clamp(0.0, 1.0),
  );
}

/// Overshoots to about 1.1 before settling on 1: popping out of the dot.
double _backOut(double k) {
  const c = 1.7;
  final x = k.clamp(0.0, 1.0) - 1;
  return 1 + (c + 1) * x * x * x + c * x * x;
}
