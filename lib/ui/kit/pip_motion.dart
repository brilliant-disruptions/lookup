/// How Pip moves. Pip is a character: a soft orb of green light with two
/// eyes ([pipCharacter]). At rest it breathes, glances about, blinks now and
/// then and gives the odd jiggle; touched, it squishes and wobbles. When it
/// says hi ([PipState.greet], [pipGreeting]) it behaves like a drop of
/// water: it sends out a ripple, glances aside, lifts a droplet off its top
/// and watches it fall back in with a splash, and blinks. Only when it leads
/// you across the sky does it become the plain dot of light (the finder and
/// cameras; pip_aim.dart). Eyes only: no mouth, no hands. This file is the
/// whole vocabulary, as plain maths over time, so it can be tested without a
/// widget and stays `dart:ui` only.
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
/// - [greet]: hi. The ripple and the eyes ([pipGreeting]), then back to the
///   dot, and rests.
enum PipState { idle, searching, resting, hello, found, greet }

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
    // The greeting does the moving; the light only hovers gently under it.
    PipState.greet => since < pipGreetLength ? PipPose(offset: fireflyHover(seconds, landed: true)) : _resting(seconds),
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

/// How long Pip's hello takes, from the dot back to the dot.
const pipGreetLength = 3.2;

/// Pip saying hi, at one moment. Lengths are in 48-pixel Pip units.
class PipGreeting {
  const PipGreeting({
    this.grown = 0,
    this.open = 0,
    this.lookX = 0,
    this.lookY = 0,
    this.wobble = 0,
    this.ripples = const [],
    this.drop,
    this.t = 0,
    this.size = 1,
  });

  /// 0 is the dot, 1 the soft orb the eyes sit in.
  final double grown;

  /// The eyes: 0 not there (or shut), 1 open.
  final double open;

  /// Where the eyes look: x −1 left … 1 right, y −1 up … 1 down.
  final double lookX, lookY;

  /// How much the surface wobbles, like water just touched.
  final double wobble;

  /// Rings spreading out: (how far out, 0…1; how strong).
  final List<(double, double)> ripples;

  /// The droplet lifted off the top: how high above the rim, and its size.
  final ({double height, double size})? drop;

  /// Seconds in, for the wobble's phase.
  final double t;

  /// Overall size: Pip breathing, or squished by a touch.
  final double size;

  /// Nothing but the plain light.
  bool get dot => grown <= 0 && wobble == 0 && ripples.isEmpty && drop == null;
}

/// Pip's hello [since] seconds in: the ripple, the glance, the droplet and
/// a blink, the character throughout. [fromDot] is the hello of Pip as the
/// plain light (in a picture of the sky): it grows out of the dot first and
/// closes back into it. Past [pipGreetLength] it returns the dot, and the
/// caller goes back to [pipCharacter]. [still] is Reduce Motion: the orb and
/// open eyes are simply there, with no ripples, wobble or droplet.
PipGreeting pipGreeting(double since, {bool still = false, bool fromDot = false}) {
  if (since < 0 || since >= pipGreetLength) return const PipGreeting();
  if (still) return const PipGreeting(grown: 1, open: 1);
  final t = since;
  final grown = !fromDot
      ? 1.0
      : t < 0.15
      ? 0.0
      : t < 0.6
          ? _smooth((t - 0.15) / 0.45)
          : t < 2.6
              ? 1.0
              : 1 - _smooth((t - 2.6) / 0.6);
  // The eyes come once it's an orb and go before it closes.
  final seen = !fromDot
      ? 1.0
      : t < 0.6
      ? 0.0
      : t < 0.85
          ? _smooth((t - 0.6) / 0.25)
          : t < 2.45
              ? 1.0
              : t < 2.65
                  ? 1 - _smooth((t - 2.45) / 0.2)
                  : 0.0;
  // A glance to one side, then up after the droplet and back down with it.
  final (lookX, _) = _keys(t, const [(0.9, 0, 0), (1.15, 1, 0), (1.35, 1, 0), (1.55, 0, 0)]);
  ({double height, double size})? drop;
  var lookY = 0.0;
  if (t > 1.45 && t < 2.15) {
    final k = (t - 1.45) / 0.7;
    final up = math.sin(k * math.pi);
    drop = (height: 22 * up, size: 2.2 * math.min(1.0, k / 0.15));
    lookY = -up;
  }
  // Touched like water: as it wakes, and again as the droplet lands back.
  double kick(double t0, double a) => t > t0 ? a * math.exp(-(t - t0) * 2.6) * math.sin((t - t0) * 15) : 0.0;
  final ripples = <(double, double)>[
    for (final (t0, a) in const [(0.1, 1.0), (0.45, 0.6), (2.15, 0.7)])
      if (t > t0 && t < t0 + 1.0) ((t - t0) / 1.0, a),
  ];
  return PipGreeting(
    grown: grown,
    open: seen * _blinks(t, const [2.3]).clamp(0.0, 1.0),
    lookX: lookX,
    lookY: lookY,
    wobble: kick(0.05, 1.6) + kick(2.15, 1.2),
    ripples: ripples,
    drop: drop,
    t: t,
  );
}

double _smooth(double k) {
  final x = k.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// Pip at rest, [t] seconds into its life: it breathes, its eyes wander
/// (a new place every couple of seconds, eased), it blinks every few
/// seconds (now and then twice), and it gives a small jiggle every seven.
/// [sincePoke] is seconds since it was touched: a squish, a wobble and a
/// happy squint. [still] is Reduce Motion: eyes open, looking ahead.
PipGreeting pipCharacter(double t, {double sincePoke = 1e9, bool still = false}) {
  if (still) return const PipGreeting(grown: 1, open: 1);
  // Where the eyes look: one of a few places, chosen by the moment.
  const spots = [(0.0, 0.0), (0.8, 0.0), (-0.8, 0.1), (0.5, -0.6), (-0.5, -0.5), (0.0, 0.4), (0.0, 0.0)];
  const glance = 2.6;
  final k = (t / glance).floor();
  (double, double) spot(int i) => spots[((i * 5 + 3) % spots.length + spots.length) % spots.length];
  final (fx, fy) = spot(k - 1);
  final (tx, ty) = spot(k);
  final e = _smooth((t - k * glance) / 0.3);
  var lookX = fx + (tx - fx) * e, lookY = fy + (ty - fy) * e;
  // Blinks: every 3.7 s, and a double blink every third time.
  final b = t % 3.7;
  var open = _blinks(b, (t ~/ 3.7) % 3 == 2 ? const [0.1, 0.35] : const [0.1]).clamp(0.0, 1.0);
  // A small jiggle every 7 s, like water nudged.
  final j = t % 7;
  var wobble = j < 1.2 ? 0.5 * math.exp(-j * 3) * math.sin(j * 14) : 0.0;
  var size = 1 + 0.025 * math.sin(t * 1.7);
  if (sincePoke >= 0 && sincePoke < 0.8) {
    final p = sincePoke;
    // Squished, then springs back with a wobble; eyes squint shut, then pop open looking up.
    size *= 1 - 0.14 * math.exp(-p * 7) * math.cos(p * 18);
    wobble += 1.4 * math.exp(-p * 4) * math.sin(p * 16);
    open = p < 0.25 ? 0.25 : open;
    lookX *= 0.3;
    lookY = p < 0.5 ? -0.5 : lookY;
  }
  return PipGreeting(grown: 1, open: open, lookX: lookX, lookY: lookY, wobble: wobble, t: t, size: size);
}

