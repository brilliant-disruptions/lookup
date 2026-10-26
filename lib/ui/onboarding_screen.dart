import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../domain/models/sky_event.dart';
import 'kit/kit.dart';
import 'theme.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final loc = await ref.read(locationServiceProvider).requestPermission();
    await ref.read(notificationServiceProvider).requestPermission();
    if (!loc) {
      setState(() {
        _busy = false;
        _error = 'LookUp needs your rough location to know what flies over you. '
            'You can also pin a place in Settings.';
      });
    }
    ref.read(playIntroProvider.notifier).set(true);
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(onboarded: true));
    // First refresh runs after the shell mounts.
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
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
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _go,
                    child: Text(_busy ? 'One moment…' : 'Allow location & alerts'),
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
