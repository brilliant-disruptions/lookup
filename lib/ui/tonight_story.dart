/// Tonight as a story: a few full-screen frames over the real sky, each a
/// few seconds long. Tap to skip ahead or back, hold to pause, swipe down
/// to close. Built from the same plan and events as the rest of the app.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/plan/night_plan.dart';
import '../domain/plan/tonight_story.dart';
import '../domain/sky/astro.dart';
import '../domain/sky/backdrop.dart';
import '../domain/sky/catalog.dart';
import '../domain/sky/direction.dart';
import '../domain/sky/landmarks.dart';
import '../domain/sky/tonight.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'real_sky.dart';
import 'sky/night_strip.dart';
import 'sky/sky_thing.dart';
import 'sky/sky_track.dart';
import 'sky_snapshot.dart';
import 'theme.dart';

Future<void> showTonightStory(BuildContext context) => Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => const TonightStoryScreen(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).chain(CurveTween(curve: Curves.easeOutCubic)).animate(a), child: child),
      ),
    ));

class TonightStoryScreen extends ConsumerWidget {
  const TonightStoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final plan = ref.watch(tonightSkyProvider).value;
    final events = ref.watch(homeProvider).value?.events ?? const <SkyEvent>[];
    final frames = tonightStory(plan: plan, events: events, now: DateTime.now(), isPlus: s?.isPlus ?? false);
    final place = (s?.placeName?.isNotEmpty ?? false) ? s!.placeName! : null;
    return StoryViewer(
      pages: [for (final f in frames) _FramePage(frame: f, plan: plan, place: place)],
      onClose: () => Navigator.of(context).maybePop(),
    );
  }
}

/// Full-screen pages that play one after another, with a progress bar for
/// each along the top. Stops on the last page.
class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.pages, required this.onClose, this.pageDuration = const Duration(seconds: 6)});
  final List<Widget> pages;
  final VoidCallback onClose;
  final Duration pageDuration;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: widget.pageDuration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _go(1);
    });
  int _index = 0;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // With reduced motion, nothing moves on its own: tap through instead.
    _still = MediaQuery.of(context).disableAnimations;
    if (_still) {
      _clock.stop();
    } else if (!_clock.isAnimating && _clock.value == 0) {
      _clock.forward();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _go(int step) {
    final next = (_index + step).clamp(0, widget.pages.length - 1);
    if (next == _index) {
      if (step < 0) _clock.forward(from: 0);
      return; // the last page stays
    }
    setState(() => _index = next);
    if (_still) {
      _clock.value = 0;
    } else {
      _clock.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: LookUpColors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _go(d.localPosition.dx < MediaQuery.sizeOf(context).width / 3 ? -1 : 1),
        onLongPressStart: (_) => _clock.stop(),
        onLongPressEnd: (_) {
          if (!_still) _clock.forward();
        },
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) widget.onClose();
        },
        child: Stack(fit: StackFit.expand, children: [
          AnimatedSwitcher(
            duration: _still ? Duration.zero : const Duration(milliseconds: 380),
            child: KeyedSubtree(key: ValueKey(_index), child: widget.pages[_index]),
          ),
          Positioned(
            top: top + 8,
            left: 12,
            right: 12,
            child: Row(children: [
              Expanded(
                child: AnimatedBuilder(
                  animation: _clock,
                  builder: (context, _) => Row(children: [
                    for (var i = 0; i < widget.pages.length; i++) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(child: _Bar(i < _index ? 1 : (i == _index ? _clock.value : 0))),
                    ],
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Close',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, color: LookUpColors.white),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.value);
  final double value;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 3,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0x40FFFFFF)),
            FractionallySizedBox(
                alignment: Alignment.centerLeft, widthFactor: value.clamp(0.0, 1.0), child: const ColoredBox(color: LookUpColors.white)),
          ]),
        ),
      );
}

/// One frame: the real sky behind (or the Moon), the words at the bottom.
class _FramePage extends ConsumerWidget {
  const _FramePage({required this.frame, required this.plan, required this.place});
  final StoryFrame frame;
  final NightPlan? plan;
  final String? place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final catalog = ref.watch(skyCatalogProvider).value;
    final lat = s?.latitude, lon = s?.longitude;
    final sky = lat == null || lon == null || catalog == null || catalog.stars.isEmpty ? null : (catalog, lat, lon);
    final f = frame;
    final (Widget behind, Widget words) = switch (f) {
      OpeningFrame() => (_openingSky(sky), _OpeningWords(plan: plan, place: place)),
      EventFrame(:final event, :final locked) => (_eventSky(sky, event), _EventWords(event: event, locked: locked)),
      PlanetFrame(:final planet) => (_planetSky(sky, planet), _PlanetWords(planet)),
      MoonFrame(:final moon) => (_MoonFace(moon), _MoonWords(moon)),
      EndFrame(:final upsell) => (_openingSky(sky), _EndWords(upsell: upsell)),
    };
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [LookUpColors.night, LookUpColors.black],
          ),
        ),
      ),
      behind,
      // A scrim so the words read over any sky.
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x00000000), Color(0xE604060B)],
              stops: [0, 0.45, 0.8],
            ),
          ),
        ),
      ),
      Positioned(
        left: 24,
        right: 24,
        bottom: bottom + 28,
        child: Rise(index: 0, child: words),
      ),
    ]);
  }

  Widget _openingSky((SkyCatalog, double, double)? sky) {
    if (sky == null) return const Starfield(density: 0.0006, maxOpacity: 0.7);
    final (catalog, lat, lon) = sky;
    final now = DateTime.now().toUtc();
    final start = plan?.window?.start;
    final at = start != null && start.isAfter(now) ? start.add(const Duration(hours: 1)) : now;
    return _Framed(SkySnapshot(catalog: catalog, utc: at, lat: lat, lon: lon, centerAz: backdropFacingAz(lat), centerAlt: 45));
  }

  Widget _eventSky((SkyCatalog, double, double)? sky, SkyEvent e) {
    if (sky == null) return const Starfield(density: 0.0006, maxOpacity: 0.7);
    final (catalog, lat, lon) = sky;
    final moves = trackedTypes.contains(e.type);
    final tint = eventStyle(e.type, details: e.details).color;
    return _Framed(SkySnapshot(
      catalog: catalog,
      utc: e.peak.toUtc(),
      lat: lat,
      lon: lon,
      centerAz: e.peakAzimuthDeg,
      centerAlt: (e.peakElevationDeg * 0.55).clamp(12.0, 50.0),
      track: moves ? [for (final p in passTrack(e, lat, lon).points) p.h] : const [],
      mark: !moves && e.peakElevationDeg > 0 ? Horizontal(e.peakAzimuthDeg, e.peakElevationDeg) : null,
      tint: tint,
      labels: [
        for (final m in landmarkPoints(e))
          if (_whereIs(m.name, catalog, e.peak.toUtc(), lat, lon) case final h?) (m.name, h),
      ],
    ));
  }

  Widget _planetSky((SkyCatalog, double, double)? sky, PlanetTonight p) {
    final at = p.sighting;
    if (sky == null || at == null) return const Starfield(density: 0.0006, maxOpacity: 0.7);
    final (catalog, lat, lon) = sky;
    final h = Horizontal(at.azDeg, at.altDeg);
    return _Framed(SkySnapshot(
      catalog: catalog,
      utc: at.best.toUtc(),
      lat: lat,
      lon: lon,
      centerAz: at.azDeg,
      centerAlt: at.altDeg.clamp(15.0, 55.0),
      mark: h,
      tint: LookUpColors.gold,
      labels: [(p.planet.label, h)],
    ));
  }
}

/// Where a landmark named on a pass is at [utc]: a planet, the Moon or a
/// named star.
Horizontal? _whereIs(String name, SkyCatalog catalog, DateTime utc, double lat, double lon) {
  if (name == 'the Moon') return moonHorizontal(utc, lat, lon);
  for (final p in Planet.values) {
    if (p.label == name) return planetHorizontal(p, utc, lat, lon);
  }
  return catalog.stars.where((s) => s.name == name).firstOrNull?.horizontal(utc, lat, lon);
}

/// The snapshot fills the top two-thirds, so the words below sit on sky
/// that's already dark.
class _Framed extends StatelessWidget {
  const _Framed(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(heightFactor: 0.72, widthFactor: 1, child: child),
      );
}

TextStyle get _body => const TextStyle(color: LookUpColors.grey, fontSize: 16, height: 1.45);

class _OpeningWords extends StatelessWidget {
  const _OpeningWords({required this.plan, required this.place});
  final NightPlan? plan;
  final String? place;

  @override
  Widget build(BuildContext context) {
    final o = plan?.outlook;
    final w = plan?.window;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Kicker(place == null ? 'Tonight' : 'Tonight over $place', color: LookUpColors.blue),
      const SizedBox(height: 10),
      Text(o == null ? 'Your sky tonight' : outlookWords(o), style: display(36, weight: FontWeight.w700)),
      if (w != null) ...[
        const SizedBox(height: 8),
        Text('Dark from ${fmtTime(w.start)} until ${fmtTime(w.end)}', style: _body),
      ],
      if (o != null && o.hasForecast) ...[
        const SizedBox(height: 18),
        NightStrip(outlook: o, compact: true),
      ],
    ]);
  }
}

class _EventWords extends StatelessWidget {
  const _EventWords({required this.event, required this.locked});
  final SkyEvent event;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final tint = eventStyle(e.type, details: e.details).color;
    final live = !DateTime.now().toUtc().isBefore(e.start);
    final near = e.details['landmarks'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        EventGlyph.of(e, size: 34),
        const SizedBox(width: 10),
        Expanded(child: Kicker(live ? 'Happening now' : '${fmtDay(e.start)} · ${fmtTime(e.start)}', color: tint, live: live)),
        CloudPill(e.cloudCoverPercent),
      ]),
      const SizedBox(height: 12),
      Text(eventTitle(e), style: display(34, weight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(eventSubtitle(e), style: _body),
      if (near is String) ...[
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.auto_awesome_rounded, size: 16, color: LookUpColors.gold),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('Look for it $near', style: _body.copyWith(color: LookUpColors.white))),
        ]),
      ],
      if (locked) ...[
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            const Pill('LookUp+', color: LookUpColors.blue),
            const SizedBox(width: 10),
            Expanded(
              child: Text('LookUp+ would tap you at ${fmtTime(e.start.subtract(const Duration(minutes: 10)))}',
                  style: const TextStyle(fontSize: 14, height: 1.3)),
            ),
          ]),
        ),
      ],
    ]);
  }
}

class _PlanetWords extends StatelessWidget {
  const _PlanetWords(this.p);
  final PlanetTonight p;

  @override
  Widget build(BuildContext context) {
    final s = p.sighting!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const Kicker('Planet', color: LookUpColors.gold),
      const SizedBox(height: 10),
      Text(p.planet.label, style: display(40, weight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text(
          'Best at ${fmtTime(s.best)}, '
          '${s.altDeg >= 75 ? elevationWord(s.altDeg) : '${elevationWord(s.altDeg)} in the ${compassWord(s.azDeg)}'}',
          style: _body),
      const SizedBox(height: 4),
      Text(s.verdict.words, style: _body.copyWith(color: LookUpColors.white)),
    ]);
  }
}

/// The Moon, big, lit on the side it really is tonight.
class _MoonFace extends StatelessWidget {
  const _MoonFace(this.moon);
  final MoonTonight moon;
  @override
  Widget build(BuildContext context) => Align(
        alignment: const Alignment(0, -0.35),
        child: SizedBox.square(
          dimension: 260,
          child: CustomPaint(painter: _MoonPainter(moon.illumination, moon.waxing)),
        ),
      );
}

class _MoonPainter extends CustomPainter {
  _MoonPainter(this.lit, this.waxing);
  final double lit;
  final bool waxing;
  @override
  void paint(Canvas canvas, Size size) =>
      // Seen from the north, a waxing Moon is lit on the right.
      paintMoonPhase(canvas, size.center(Offset.zero), lit, waxing ? 0 : math.pi, r: size.shortestSide * 0.3);
  @override
  bool shouldRepaint(_MoonPainter o) => o.lit != lit || o.waxing != waxing;
}

class _MoonWords extends StatelessWidget {
  const _MoonWords(this.moon);
  final MoonTonight moon;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final rise = moon.rise, set = moon.set;
    final when = rise != null && rise.isAfter(now)
        ? 'Rises at ${fmtTime(rise)}'
        : set != null && set.isAfter(now)
            ? 'Up until ${fmtTime(set)}'
            : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const Kicker('The Moon', color: LookUpColors.white),
      const SizedBox(height: 10),
      Text(moon.phase.label, style: display(36, weight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('${(moon.illumination * 100).round()}% lit${when == null ? '' : ' · $when'}', style: _body),
    ]);
  }
}

class _EndWords extends ConsumerWidget {
  const _EndWords({required this.upsell});
  final SkyEvent? upsell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = upsell;
    void openSky() {
      ref.read(homeTabProvider.notifier).set(1);
      Navigator.of(context).maybePop();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (u != null) ...[
        const Align(alignment: Alignment.centerLeft, child: Kicker('LookUp+', color: LookUpColors.blue)),
        const SizedBox(height: 10),
        Text('Don\'t miss the next one', style: display(34, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('${eventTitle(u)} · ${fmtDay(u.start)}, ${fmtTime(u.start)}. LookUp+ taps you 10 minutes before.',
            style: _body),
        const SizedBox(height: 22),
        FilledButton(onPressed: () => showPaywall(context, reason: u), child: const Text('See LookUp+')),
        const SizedBox(height: 8),
        TextButton(onPressed: openSky, child: const Text('Open the sky')),
      ] else ...[
        Text('That\'s tonight', style: display(34, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Everything else up there is in the Sky tab, live, wherever you point your phone.', style: _body),
        const SizedBox(height: 22),
        FilledButton(onPressed: openSky, child: const Text('Open the sky')),
      ],
    ]);
  }
}
