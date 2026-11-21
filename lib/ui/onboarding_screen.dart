import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../domain/models/sky_event.dart';
import '../domain/plus/plus_preview.dart';
import 'format.dart';
import 'intro_scene.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'theme.dart';

/// Value before the ask. The intro shows the product working ([IntroScene]):
/// a pass over a horizon and the tap it brings. Then location first ("show me what's over me"), then
/// the user's own next sights, and only then the notification prompt, with
/// the tap it buys spelled out. A denied location offers a town instead of
/// a dead end.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

enum _Step { intro, noLocation, looking, sights, ask, offer }

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.intro;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The satellites and launches don't depend on where the user is: fetch
    // them while they read the intro and answer the location prompt, so
    // the first look only waits for the location.
    unawaited(ref.read(refreshServiceProvider).prefetch().catchError((_) {}));
  }

  Future<void> _showMe() async {
    setState(() => _busy = true);
    final ok = await ref.read(locationServiceProvider).requestPermission();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _look();
    } else {
      setState(() => _step = _Step.noLocation);
    }
  }

  Future<void> _pickTown() async {
    await openPlaces(context);
    if (!mounted) return;
    final s = await ref.read(settingsProvider.future);
    if (s.hasLocation) await _look();
  }

  /// The first refresh, here rather than after the shell mounts, so the
  /// next screen can show what's really coming.
  Future<void> _look() async {
    setState(() => _step = _Step.looking);
    try {
      // Let the stored (empty) data finish loading first, or it can land
      // after the refresh and hide what it found.
      await ref.read(homeProvider.future);
      // Quick first (location and the ISS only), so the sights show in
      // seconds; clouds, aurora and Starlink follow in the background and
      // the screen updates when they land.
      await ref.read(homeProvider.notifier).refresh(quick: true);
    } catch (_) {
      // Offline: the sights screen says so and the shell retries.
    }
    unawaited(ref.read(homeProvider.notifier).refresh().catchError((_) {}));
    if (mounted) setState(() => _step = _Step.sights);
  }

  Future<void> _finish({required bool alerts}) async {
    setState(() => _busy = true);
    if (alerts) {
      final granted = await ref.read(notificationServiceProvider).requestPermission();
      // Alerts were planned before permission; plan them again now they can land.
      // A refresh still running (onboarding's Starlink one) plans at its end,
      // so waiting for it here would only bring the download's wait back.
      if (granted) {
        final home = ref.read(homeProvider.notifier);
        if (!home.refreshing) {
          try {
            await home.refresh();
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    // Once, and never to someone who already has LookUp+: what LookUp+ would
    // tap them for. Most trials start on day one; this is that moment.
    final s = await ref.read(settingsProvider.future);
    if (!s.isPlus && !s.trialOfferShown) {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = _Step.offer;
        });
      }
      return;
    }
    await _done();
  }

  Future<void> _done() => ref
      .read(settingsProvider.notifier)
      .edit((s) => s.copyWith(onboarded: true, onboardedAt: DateTime.now().toUtc(), trialOfferShown: true));

  /// The offer's two ways out: a trial (through the paywall), or "Not now",
  /// which counts as a decline for the soft asks (domain/plus/nudges.dart).
  Future<void> _offer({required bool tryIt}) async {
    if (tryIt) {
      await showPaywall(context, headline: 'Every tap, for everything up there. Free for 7 days.');
      if (!mounted) return;
    }
    if (!(ref.read(settingsProvider).value?.isPlus ?? false)) {
      await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(plusDeclines: s.plusDeclines + 1));
    }
    await _done();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_step == _Step.looking || _step == _Step.sights) {
      return _SightsPage(
          looking: _step == _Step.looking, onContinue: () => setState(() => _step = _Step.ask));
    }
    if (_step == _Step.ask) return _AskPage(busy: _busy, onFinish: _finish);
    if (_step == _Step.offer) return _OfferPage(onTry: () => _offer(tryIt: true), onNotNow: () => _offer(tryIt: false));
    return Scaffold(
      body: SkyBackdrop(
        stars: false,
        child: Stack(children: [
          const Positioned.fill(child: Starfield(density: 0.0006, maxOpacity: 0.8)),
          // A dawn glow along the horizon.
          Positioned(
            left: -80,
            right: -80,
            bottom: -260,
            height: 420,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [LookUpColors.blue.withValues(alpha: 0.22), LookUpColors.blue.withValues(alpha: 0)]),
                ),
              ),
            ),
          ),
          SafeArea(
            child: _FillOrScroll(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The product working, before a word about it.
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height * 0.4).clamp(250.0, 380.0),
                    child: const Rise(index: 0, child: IntroScene()),
                  ),
                  const Spacer(),
                  Rise(
                    index: 1,
                    child: Row(children: [
                      Text('LookUp', style: display(30, weight: FontWeight.w800)),
                      Text('.', style: display(30, weight: FontWeight.w800, color: LookUpColors.blue)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Rise(
                    index: 2,
                    child: Text('It taps you when something is about to fly over.',
                        style: display(30, weight: FontWeight.w700, height: 1.15)),
                  ),
                  const SizedBox(height: 12),
                  Rise(
                    index: 3,
                    child: Text(
                      'The space station, Starlink trains, auroras. Only when it\'s dark and clear enough to see. No account, no setup.',
                      style: t.bodyLarge?.copyWith(color: LookUpColors.grey, height: 1.4),
                    ),
                  ),
                  const Spacer(flex: 2),
                  if (_step == _Step.noLocation) ...[
                    const Text(
                      'No problem. Tell us your town instead: a rough place is all LookUp needs.',
                      style: TextStyle(color: LookUpColors.grey, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _pickTown,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Choose your town'),
                    ),
                    TextButton(onPressed: _showMe, child: const Text('Try location again')),
                  ] else
                    FilledButton(
                      onPressed: _busy ? null : _showMe,
                      child: Text(_busy ? 'One moment…' : 'Show me what\'s over me'),
                    ),
                  const SizedBox(height: 14),
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.lock_rounded, size: 14, color: LookUpColors.greyDim),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text('A rough location only, and it never leaves your phone.',
                          style: TextStyle(fontSize: 12.5, color: LookUpColors.greyDim)),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// A full-height page whose spacers share out the room on a tall phone,
/// and which scrolls instead of overflowing on a short one.
class _FillOrScroll extends StatelessWidget {
  const _FillOrScroll({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight - 40),
            child: IntrinsicHeight(child: child),
          ),
        ),
      );
}

/// Moment 2: where you are, and the one thing coming over you next, with
/// Pip introduced as the guide who shows you where to look.
class _SightsPage extends ConsumerWidget {
  const _SightsPage({required this.looking, required this.onContinue});
  final bool looking;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final place = (s?.placeName?.isNotEmpty ?? false) ? s!.placeName! : 'you';
    final now = DateTime.now().toUtc();
    final home = ref.watch(homeProvider).value;
    // What free alerts are really for: pushed, not Plus-only, this fortnight.
    final first = [
      for (final e in home?.events ?? const <SkyEvent>[])
        if (e.type.pushes && !e.plusOnly && e.start.isAfter(now) && e.start.isBefore(now.add(const Duration(days: 14)))) e,
    ].firstOrNull;
    final approximate = home?.approximate ?? false;
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: _FillOrScroll(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Spacer(),
              if (looking) ...[
                const PipMark(key: Key('onboarding-pip'), size: 48, state: PipState.searching),
                const SizedBox(height: 8),
                Kicker('Over $place', color: LookUpColors.blue),
                const SizedBox(height: 10),
                Text('Looking at your sky…', style: display(32, weight: FontWeight.w700, height: 1.1)),
                const SizedBox(height: 18),
                const GlassCard(padding: EdgeInsets.zero, child: SizedBox(key: Key('sight-placeholder'), height: 96)),
                const Spacer(flex: 2),
              ] else ...[
                Rise(index: 0, child: Kicker('Over $place', color: LookUpColors.blue)),
                const SizedBox(height: 10),
                Rise(
                  index: 1,
                  child: Text(first == null ? 'A quiet sky for now' : 'Your next sight',
                      style: display(32, weight: FontWeight.w700, height: 1.1)),
                ),
                const SizedBox(height: 18),
                if (first == null)
                  const Text(
                    'Nothing bright is passing over in the next fortnight, or we couldn\'t load the sky just now. '
                    'LookUp keeps watching and taps you when that changes.',
                    style: TextStyle(color: LookUpColors.grey, height: 1.45),
                  )
                else
                  Rise(
                    index: 2,
                    child: Stack(clipBehavior: Clip.none, children: [
                      GlassCard(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Row(children: [
                          EventGlyph.of(first),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(eventTitle(first), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(eventSubtitle(first),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.3)),
                            ]),
                          ),
                          const SizedBox(width: 10),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(fmtDay(first.start), style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
                            Text(fmtTime(first.start), style: numeric(size: 16, weight: FontWeight.w700)),
                          ]),
                        ]),
                      ),
                      const Positioned(
                        right: -10,
                        top: -18,
                        child: PipMark(
                            key: Key('onboarding-pip'), size: 36, state: PipState.resting, flyFrom: Offset(-140, -120)),
                      ),
                    ]),
                  ),
                if (approximate && first != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Times may be off by a few minutes until we can reach the satellite tracker.',
                    style: TextStyle(fontSize: 13, color: LookUpColors.grey, height: 1.4),
                  ),
                ],
                const Spacer(flex: 2),
                const Text(
                  'That\'s Pip. Pip points you the right way when something\'s coming, so you never have to work out where to look.',
                  style: TextStyle(color: LookUpColors.grey, height: 1.45),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: onContinue, child: const Text('Continue')),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Moment 3: the one ask, with the tap it buys shown first.
class _AskPage extends ConsumerWidget {
  const _AskPage({required this.busy, required this.onFinish});
  final bool busy;
  final Future<void> Function({required bool alerts}) onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final lead = s?.leadMinutes ?? 10;
    final now = DateTime.now().toUtc();
    final first = [
      for (final e in ref.watch(homeProvider).value?.events ?? const <SkyEvent>[])
        if (e.type.pushes && !e.plusOnly && e.start.isAfter(now)) e,
    ].firstOrNull;
    final title = first == null ? 'Something bright is coming' : eventTitle(first);
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: _FillOrScroll(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Spacer(),
              Rise(index: 0, child: const Kicker('One tap', color: LookUpColors.blue)),
              const SizedBox(height: 10),
              Rise(
                index: 1,
                child: Text('Then we\'ll tap you $lead minutes before.',
                    style: display(32, weight: FontWeight.w700, height: 1.1)),
              ),
              const SizedBox(height: 20),
              // What the tap will look like.
              Rise(
                index: 2,
                child: GlassCard(
                  key: const Key('tap-preview'),
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const PipMark(key: Key('onboarding-pip-blink'), size: 34, blinking: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('LookUp · now', style: const TextStyle(fontSize: 12, color: LookUpColors.grey)),
                        const SizedBox(height: 2),
                        Text('$title in $lead min',
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        const Text('Face south-west and look up. Clear skies.',
                            style: TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.3)),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'These last a few minutes, so they\'re easy to miss. LookUp stays quiet when it\'s cloudy.',
                style: TextStyle(color: LookUpColors.grey, height: 1.45),
              ),
              const Spacer(flex: 2),
              FilledButton.icon(
                onPressed: busy ? null : () => onFinish(alerts: true),
                icon: const Icon(Icons.notifications_active_rounded),
                label: Text('Tap me $lead minutes before'),
              ),
              TextButton(
                onPressed: busy ? null : () => onFinish(alerts: false),
                child: const Text('Not now'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The one-time LookUp+ offer at the end of setting up: the real taps it
/// would send over them this month (or, before those are known, what it
/// adds), a 7-day trial, and a plain "Not now". Never again after this.
class _OfferPage extends ConsumerWidget {
  const _OfferPage({required this.onTry, required this.onNotNow});
  final VoidCallback onTry, onNotNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = PlusPreview.of(ref.watch(homeProvider).value?.events ?? const <SkyEvent>[], DateTime.now());
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: _FillOrScroll(
            child: Column(key: const Key('trial-offer'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Spacer(),
              const Center(child: PipMark(size: 72)),
              const SizedBox(height: 6),
              Rise(index: 0, child: const Kicker('LookUp+', color: LookUpColors.blue)),
              const SizedBox(height: 10),
              Rise(
                index: 1,
                child: Text(
                  p.count == 0 ? 'Want a tap for everything up there?' : 'There\'s more coming over you',
                  style: display(32, weight: FontWeight.w700, height: 1.1),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p.count == 0
                    ? 'Free taps you for the space station, meteor showers and eclipses. LookUp+ adds the rest.'
                    : 'Free taps you for the space station. ${p.count == 1 ? 'Here\'s one' : 'Here are ${p.count}'} it won\'t, this month:',
                style: const TextStyle(color: LookUpColors.grey, height: 1.45),
              ),
              const SizedBox(height: 16),
              Rise(
                index: 2,
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(children: [
                    if (p.count > 0)
                      for (final e in p.soonest)
                        _OfferRow(glyph: EventGlyph.of(e, size: 34), title: eventTitle(e), line: '${fmtDay(e.start)}, ${fmtTime(e.start)}')
                    else ...[
                      _OfferRow(
                          glyph: const EventGlyph(icon: Icons.waves_rounded, color: LookUpColors.good, size: 34),
                          title: 'Aurora, the moment it\'s visible',
                          line: 'Live alerts from here, not a forecast'),
                      _OfferRow(
                          glyph: const EventGlyph(icon: Icons.linear_scale_rounded, color: LookUpColors.violet, size: 34),
                          title: 'Starlink trains and Tiangong',
                          line: 'A tap before each one goes over'),
                      _OfferRow(
                          glyph: const EventGlyph(icon: Icons.near_me_rounded, color: LookUpColors.blue, size: 34),
                          title: 'Where to go tonight',
                          line: 'Clearer, darker skies near you'),
                    ],
                  ]),
                ),
              ),
              const Spacer(flex: 2),
              FilledButton(
                key: const Key('trial-offer-try'),
                onPressed: onTry,
                child: const Text('Try 7 days free'),
              ),
              TextButton(key: const Key('trial-offer-not-now'), onPressed: onNotNow, child: const Text('Not now')),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.glyph, required this.title, required this.line});
  final Widget glyph;
  final String title, line;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          glyph,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(line, style: const TextStyle(fontSize: 13, color: LookUpColors.grey)),
            ]),
          ),
          const Icon(Icons.notifications_active_outlined, size: 18, color: LookUpColors.blue),
        ]),
      );
}
