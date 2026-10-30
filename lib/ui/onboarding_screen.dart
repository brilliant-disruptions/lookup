import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../domain/models/sky_event.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'places_screen.dart';
import 'theme.dart';

/// Value before the ask. Location first ("show me what's over me"), then
/// the user's own next sights, and only then the notification prompt, with
/// the tap it buys spelled out. A denied location offers a town instead of
/// a dead end.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

enum _Step { intro, noLocation, looking, sights }

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.intro;
  bool _busy = false;

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
      await ref.read(homeProvider.notifier).refresh();
    } catch (_) {
      // Offline: the sights screen says so and the shell retries.
    }
    if (mounted) setState(() => _step = _Step.sights);
  }

  Future<void> _finish({required bool alerts}) async {
    setState(() => _busy = true);
    if (alerts) {
      final granted = await ref.read(notificationServiceProvider).requestPermission();
      // Alerts were planned before permission; plan them again now they can land.
      if (granted) {
        try {
          await ref.read(homeProvider.notifier).refresh();
        } catch (_) {}
      }
    }
    ref.read(playIntroProvider.notifier).set(true);
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(onboarded: true));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_step == _Step.looking || _step == _Step.sights) {
      return _SightsPage(looking: _step == _Step.looking, busy: _busy, onFinish: _finish);
    }
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
                  const Spacer(flex: 3),
                  Rise(
                    index: 0,
                    child: Row(children: [
                      Text('LookUp', style: display(48, weight: FontWeight.w800)),
                      Text('.', style: display(48, weight: FontWeight.w800, color: LookUpColors.blue)),
                    ]),
                  ),
                  const Rise(
                    index: 1,
                    child: Text('Step outside right now', style: TextStyle(fontSize: 17, color: LookUpColors.grey)),
                  ),
                  const SizedBox(height: 36),
                  Rise(
                    index: 2,
                    child: Text('It taps you when something is about to fly over.',
                        style: display(30, weight: FontWeight.w700, height: 1.15)),
                  ),
                  const SizedBox(height: 26),
                  for (final (i, (glyph, line)) in [
                    (EventGlyph.forType(SkyEventType.iss), 'The space station, a fresh Starlink train, an aurora'),
                    (const EventGlyph(icon: Icons.explore_rounded, color: LookUpColors.violet), 'A few minutes before, with which way to face'),
                    (const EventGlyph(icon: Icons.cloud_off_rounded, color: LookUpColors.cyan), 'Quiet when it\'s cloudy. No account, no setup'),
                  ].indexed)
                    Rise(
                      index: 3 + i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(children: [
                          glyph,
                          const SizedBox(width: 14),
                          Expanded(child: Text(line, style: t.bodyLarge?.copyWith(height: 1.35))),
                        ]),
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

/// "Here's what's coming over you": the real next sights, then the one ask
/// that makes them worth anything, a tap before each.
class _SightsPage extends ConsumerWidget {
  const _SightsPage({required this.looking, required this.busy, required this.onFinish});
  final bool looking;
  final bool busy;
  final Future<void> Function({required bool alerts}) onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final place = (s?.placeName?.isNotEmpty ?? false) ? s!.placeName! : 'you';
    final now = DateTime.now().toUtc();
    // What free alerts are really for: pushed, not Plus-only, this week.
    final sights = [
      for (final e in ref.watch(homeProvider).value?.events ?? const <SkyEvent>[])
        if (e.type.pushes && !e.plusOnly && e.start.isAfter(now) && e.start.isBefore(now.add(const Duration(days: 14)))) e,
    ].take(3).toList();
    final lead = s?.leadMinutes ?? 10;
    return Scaffold(
      body: SkyBackdrop(
        child: SafeArea(
          child: _FillOrScroll(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Spacer(),
              if (looking) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 18),
                const Text('Looking at your sky…', textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey)),
                const Spacer(flex: 2),
              ] else ...[
                Rise(index: 0, child: Kicker('Coming over $place', color: LookUpColors.blue)),
                const SizedBox(height: 10),
                Rise(
                  index: 1,
                  child: Text(
                    sights.isEmpty
                        ? 'A quiet sky for now'
                        : sights.length == 1
                            ? 'Your next sight'
                            : 'Your next ${sights.length} sights',
                    style: display(32, weight: FontWeight.w700, height: 1.1),
                  ),
                ),
                const SizedBox(height: 18),
                if (sights.isEmpty)
                  const Text(
                    'Nothing bright is passing over in the next fortnight, or we couldn\'t load the sky just now. '
                    'LookUp keeps watching and taps you when that changes.',
                    style: TextStyle(color: LookUpColors.grey, height: 1.45),
                  )
                else
                  for (final (i, e) in sights.indexed)
                    Rise(
                      index: 2 + i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassCard(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Row(children: [
                            EventGlyph.of(e),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(eventTitle(e), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(eventSubtitle(e),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.3)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(fmtDay(e.start), style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
                              Text(fmtTime(e.start), style: numeric(size: 15, weight: FontWeight.w700)),
                            ]),
                          ]),
                        ),
                      ),
                    ),
                const Spacer(flex: 2),
                Text(
                  'Easy to miss: these last a few minutes. LookUp taps you $lead minutes before, '
                  'with which way to face, and stays quiet when it\'s cloudy.',
                  style: const TextStyle(color: LookUpColors.grey, height: 1.45),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : () => onFinish(alerts: true),
                  icon: const Icon(Icons.notifications_active_rounded),
                  label: Text('Tap me $lead minutes before'),
                ),
                TextButton(
                  onPressed: busy ? null : () => onFinish(alerts: false),
                  child: const Text('Not now'),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
