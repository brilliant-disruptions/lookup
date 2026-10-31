import 'dart:math' as math;

import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/log/catch_moment.dart';
import '../domain/log/sky_log.dart';
import '../domain/models/sky_event.dart';
import '../services/widget_service.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'night_vision_button.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'share_card.dart';
import 'theme.dart';

/// The moment someone says "Yes, I saw it". It used to be one line on the
/// Look sheet; it's the best feeling the app gives, so it gets the screen:
/// a burst in the event's colour, which sighting this is, any badge it just
/// earned, what's next over them, and sharing it as the main button.
///
/// For someone on free with a Plus-only sight really coming (Tiangong, a
/// Starlink train), this is also where LookUp+ is offered: once, for that
/// dated thing, at the moment they've just felt what a tap is worth.
Future<void> showCaughtIt(BuildContext context, SkyEvent event, {bool demo = false, Future<void> Function()? onAddPhoto}) {
  HapticFeedback.heavyImpact();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => CaughtItScreen(event: event, demo: demo, onAddPhoto: onAddPhoto),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ),
  );
}

class CaughtItScreen extends ConsumerWidget {
  const CaughtItScreen({super.key, required this.event, this.demo = false, this.onAddPhoto, this.animate = true});
  final SkyEvent event;

  /// Preview pass: nothing was logged, so show what a first yes earns.
  final bool demo;
  final Future<void> Function()? onAddPhoto;

  /// Off in golden tests, so the burst is drawn settled.
  final bool animate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tint = eventStyle(event.type, details: event.details).color;
    final settings = ref.watch(settingsProvider).value;
    final isPlus = settings?.isPlus ?? false;
    final lead = settings?.leadMinutes ?? 10;
    final events = ref.watch(homeProvider).value?.events ?? const <SkyEvent>[];
    final alertsOn = ref.watch(alertsEnabledProvider).value != false;
    final CatchMoment? m;
    if (demo) {
      m = CatchMoment(nth: 1, nthOfType: 1, newBadges: [SkyLog.from(const []).badges.first], next: null, nextPlus: null);
    } else {
      final log = ref.watch(skyLogProvider).value;
      m = log == null ? null : CatchMoment.of(log: log, eventId: event.id, upcoming: events, now: DateTime.now(), isPlus: isPlus);
    }

    return OutsideScreen(
      child: Scaffold(
        backgroundColor: LookUpColors.black,
        body: SkyBackdrop(
          glow: tint,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Row(
                    children: [
                      if (demo) const Pill('Preview · nothing logged', icon: Icons.fast_forward_rounded, color: LookUpColors.blue),
                      const Spacer(),
                      const NightVisionButton(),
                      const SizedBox(width: 8),
                      CircleButton(icon: Icons.close_rounded, tooltip: 'Close', onPressed: () => Navigator.of(context).maybePop()),
                    ],
                  ),
                ),
                Expanded(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, 0.94, 1],
                    ).createShader(r),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 170,
                            child: _Burst(tint: tint, animate: animate, child: EventGlyph.of(event, size: 68)),
                          ),
                          Rise(
                            index: 0,
                            child: Text(
                              'You caught it.',
                              textAlign: TextAlign.center,
                              style: display(40, weight: FontWeight.w800, height: 1.05),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Rise(
                            index: 1,
                            child: Text(
                              '${eventTitle(event)} · ${fmtDay(event.start)}, ${fmtTime(event.start)}',
                              textAlign: TextAlign.center,
                              style: numeric(size: 15, color: LookUpColors.grey),
                            ),
                          ),
                          if (m != null) ...[
                            const SizedBox(height: 14),
                            Rise(
                              index: 2,
                              child: Center(
                                child: Pill(
                                  m.nthOfType > 1 && m.nthOfType != m.nth && _kindWord(event.type) != null
                                      ? '${m.countLine} · ${ordinal(m.nthOfType)} ${_kindWord(event.type)}'
                                      : m.countLine,
                                  icon: Icons.auto_awesome_rounded,
                                  color: tint,
                                ),
                              ),
                            ),
                            if (!demo) _UnderThePassCard(event: event, tint: tint, animate: animate),
                            // Their first sighting: the moment to keep the next one in view.
                            if (!demo && m.isFirst && (ref.watch(widgetPinnableProvider).value ?? false)) const _WidgetCard(),
                            if (m.completesStarter) ...[const SizedBox(height: 14), _StarterDone(animate: animate)],
                            for (final (i, b) in m.newBadges.indexed) ...[
                              const SizedBox(height: 14),
                              _BadgeUnlocked(badge: b, index: i, animate: animate),
                            ],
                            if (m.next != null) ...[
                              const SizedBox(height: 14),
                              Rise(
                                index: 4,
                                child: _NextCard(
                                  event: m.next!,
                                  line: alertsOn
                                      ? 'If it\'s clear, LookUp taps you $lead minutes before.'
                                      : 'Turn alerts on in Settings and LookUp will tap you before it.',
                                ),
                              ),
                            ],
                            if (m.nextPlus != null) ...[const SizedBox(height: 14), Rise(index: 5, child: _PlusCard(event: m.nextPlus!))],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                // Pinned, so sharing is one thumb away however long the moment runs.
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!demo)
                        Row(
                          children: [
                            if (onAddPhoto != null) ...[
                              Tooltip(
                                message: 'Add your photo',
                                child: OutlinedButton(
                                  onPressed: onAddPhoto,
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(58, 58), padding: EdgeInsets.zero),
                                  child: const Icon(Icons.add_a_photo_rounded, semanticLabel: 'Add your photo'),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => showShareCard(context, event),
                                icon: const Icon(Icons.ios_share_rounded),
                                label: const Text('Share it'),
                              ),
                            ),
                          ],
                        ),
                      TextButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(demo ? 'Got it' : 'Done')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _kindWord(SkyEventType t) => switch (t) {
    SkyEventType.iss => 'ISS pass',
    SkyEventType.tiangong => 'Tiangong pass',
    SkyEventType.starlinkTrain => 'Starlink train',
    SkyEventType.auroraNow || SkyEventType.auroraOutlook => 'aurora',
    SkyEventType.meteorShower => 'meteor shower',
    SkyEventType.rocketLaunch => 'launch',
    _ => null,
  };
}

/// "You weren't alone": who else had the same pass in a dark sky at the
/// same moments. Passes only; nothing at all when we can't tell.
class _UnderThePassCard extends ConsumerWidget {
  const _UnderThePassCard({required this.event, required this.tint, required this.animate});
  final SkyEvent event;
  final Color tint;
  final bool animate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(underThePassProvider(event)).value;
    if (u == null) return const SizedBox.shrink();
    final card = Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: tint.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(Icons.groups_rounded, color: tint, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You weren\'t alone',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: tint),
                  ),
                  const SizedBox(height: 2),
                  Text('${u.peopleWords} people', style: display(22, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'had it crossing a dark sky at the same moments as you, in ${u.placesWords}.',
                    style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Towns of 50,000+ where it was well up after dark. Clouds not counted.',
                    style: TextStyle(fontSize: 11.5, color: LookUpColors.greyDim, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return animate ? Rise(index: 3, child: card) : card;
  }
}

/// "Keep the next one in view": add the home-screen widget (Android).
class _WidgetCard extends StatelessWidget {
  const _WidgetCard();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              EventGlyph(icon: Icons.widgets_rounded, color: LookUpColors.violet),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Keep the next one in view', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(
                      'A home-screen widget with the next pass, where to look and a live countdown.',
                      style: TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: WidgetService.pin, icon: const Icon(Icons.add_rounded), label: const Text('Add to home screen')),
        ],
      ),
    ),
  );
}

/// The starter three are all seen: they know their sky now.
class _StarterDone extends StatelessWidget {
  const _StarterDone({required this.animate});
  final bool animate;
  @override
  Widget build(BuildContext context) {
    final card = GlassCard(
      tint: LookUpColors.gold,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: LookUpColors.gold, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your first three: done', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                const Text(
                  'A pass, a planet and a star pattern, all with your own eyes. You know your way round your sky now.',
                  style: TextStyle(fontSize: 13, color: LookUpColors.grey, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return animate ? Rise(index: 3, child: card) : card;
  }
}

/// "Badge unlocked": pops in after the headline with a little overshoot.
class _BadgeUnlocked extends StatelessWidget {
  const _BadgeUnlocked({required this.badge, required this.index, required this.animate});
  final Badge badge;
  final int index;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final card = GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0xFFFFE6A6), LookUpColors.gold]),
              boxShadow: [BoxShadow(color: LookUpColors.gold.withValues(alpha: 0.45), blurRadius: 18)],
            ),
            child: const Icon(Icons.military_tech_rounded, color: Color(0xFF5A3D00), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Badge unlocked',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: LookUpColors.gold),
                ),
                const SizedBox(height: 2),
                Text(badge.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                Text(badge.description, style: const TextStyle(fontSize: 13, color: LookUpColors.grey, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
    if (!animate) return card;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 700 + 160 * index),
      curve: Interval(0.35, 1, curve: Curves.elasticOut),
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
      ),
      child: card,
    );
  }
}

class _NextCard extends StatelessWidget {
  const _NextCard({required this.event, required this.line});
  final SkyEvent event;
  final String line;
  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Kicker('Next over you', color: LookUpColors.blue),
        const SizedBox(height: 8),
        Row(
          children: [
            EventGlyph.of(event),
            const SizedBox(width: 12),
            Expanded(
              child: Text(eventTitle(event), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmtDay(event.start), style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
                Text(fmtTime(event.start), style: numeric(size: 15, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(line, style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.35)),
      ],
    ),
  );
}

/// The one LookUp+ offer: a real, dated Plus-only sight free won't tap for.
class _PlusCard extends StatelessWidget {
  const _PlusCard({required this.event});
  final SkyEvent event;
  @override
  Widget build(BuildContext context) {
    final tint = eventStyle(event.type, details: event.details).color;
    return GlassCard(
      tint: tint,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              EventGlyph.of(event),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eventTitle(event), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('${fmtDay(event.start)}, ${fmtTime(event.start)}', style: numeric(size: 14)),
                    const SizedBox(height: 4),
                    const Text(
                      'Free won\'t tap you for this one.',
                      style: TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => showPaywall(context, reason: event),
            style: OutlinedButton.styleFrom(
              foregroundColor: LookUpColors.white,
              side: BorderSide(color: tint.withValues(alpha: 0.6)),
            ),
            child: const Text('Get the tap with LookUp+'),
          ),
        ],
      ),
    );
  }
}

/// A flash in the event's colour, a ring going out, and sparks flying from
/// the glyph that slow and twinkle in place. Drawn settled when [animate]
/// is off (goldens) or the platform asks for less motion.
class _Burst extends StatefulWidget {
  const _Burst({required this.tint, required this.child, this.animate = true});
  final Color tint;
  final Widget child;
  final bool animate;
  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with TickerProviderStateMixin {
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final AnimationController _twinkle = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  late final List<_Spark> _sparks = _Spark.scatter(72, math.Random(7));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !widget.animate || MediaQuery.of(context).disableAnimations;
    if (still) {
      _out.value = 1;
      _twinkle.stop();
    } else if (!_out.isAnimating && _out.value == 0) {
      _out.forward();
      _twinkle.repeat();
    }
  }

  @override
  void dispose() {
    _out.dispose();
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_out, _twinkle]),
    builder: (context, child) {
      final t = _out.value;
      final pop = Curves.elasticOut.transform(Interval(0.05, 0.7).transform(t));
      return CustomPaint(
        painter: _BurstPainter(sparks: _sparks, t: t, twinkle: _twinkle.value, tint: widget.tint),
        child: Center(
          child: Transform.scale(scale: 0.4 + 0.6 * pop, child: child),
        ),
      );
    },
    child: widget.child,
  );
}

class _Spark {
  const _Spark(this.angle, this.distance, this.size, this.phase, this.white);
  final double angle;
  final double distance; // 0..1 of the available radius
  final double size;
  final double phase;
  final bool white;

  static List<_Spark> scatter(int n, math.Random r) => [
    for (var i = 0; i < n; i++)
      _Spark(
        r.nextDouble() * math.pi * 2,
        0.25 + 0.75 * math.sqrt(r.nextDouble()),
        0.8 + r.nextDouble() * 2.2,
        r.nextDouble(),
        r.nextDouble() < 0.55,
      ),
  ];
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.sparks, required this.t, required this.twinkle, required this.tint});
  final List<_Spark> sparks;
  final double t;
  final double twinkle;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = math.min(size.width / 2, size.height * 0.62);

    // Soft halo that stays.
    final halo = Paint()
      ..shader = RadialGradient(colors: [tint.withValues(alpha: 0.32), tint.withValues(alpha: 0)])
          .createShader(Rect.fromCircle(center: c, radius: radius * 0.75));
    canvas.drawCircle(c, radius * 0.75, halo);

    // The flash: bright, then gone.
    final flash = (1 - Curves.easeOut.transform(math.min(1, t * 2.4))).clamp(0.0, 1.0);
    if (flash > 0) {
      canvas.drawCircle(
        c,
        radius * (0.2 + 0.5 * (1 - flash)),
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.7 * flash),
              tint.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: radius * 0.7)),
      );
    }

    // The ring going out.
    final ringT = Curves.easeOutCubic.transform(math.min(1, t * 1.3));
    final ringA = (1 - ringT) * 0.8;
    if (ringA > 0.01) {
      canvas.drawCircle(
        c,
        radius * (0.25 + 0.85 * ringT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - ringT) + 0.5
          ..color = tint.withValues(alpha: ringA),
      );
    }

    // Sparks: fly out fast, ease to a stop, then twinkle where they landed.
    final travel = Curves.easeOutQuart.transform(t);
    for (final s in sparks) {
      final d = radius * s.distance * travel;
      final p = c + Offset(math.cos(s.angle) * d * 1.45, math.sin(s.angle) * d);
      final tw = 0.55 + 0.45 * math.sin((twinkle + s.phase) * math.pi * 2);
      final a = (t < 1 ? math.min(1.0, t * 4) : 1.0) * tw * (1 - 0.35 * s.distance);
      final color = (s.white ? Colors.white : tint).withValues(alpha: a.clamp(0.0, 1.0));
      canvas.drawCircle(p, s.size, Paint()..color = color);
      // A short streak behind each spark while it's still moving.
      if (t < 0.6) {
        final back = c + Offset(math.cos(s.angle) * d * 1.45 * 0.82, math.sin(s.angle) * d * 0.82);
        canvas.drawLine(
          back,
          p,
          Paint()
            ..strokeWidth = s.size * 0.9
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: color.a * (1 - t / 0.6) * 0.6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.twinkle != twinkle || old.tint != tint;
}
