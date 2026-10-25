import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'fancy/foil_text.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/rise.dart';
import 'fancy/starfield.dart';
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
    final notif = await ref.read(notificationServiceProvider).requestPermission();
    final a = ref.read(analyticsProvider);
    await a.log('location_permission', {'granted': loc});
    await a.log('notif_permission', {'granted': notif});
    await a.log('onboarded');
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
      body: Starfield(
        density: 0.0005,
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Rise(
                index: 0,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    FoilText('LookUp', style: displaySerif(context, size: 54, weight: FontWeight.w600)),
                    Text('.', style: displaySerif(context, size: 54, weight: FontWeight.w700, color: LookUpColors.blue)),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              const Rise(index: 1, child: Eyebrow('Step outside right now')),
              const SizedBox(height: 22),
              const Rise(index: 2, child: OrnamentRule()),
              const SizedBox(height: 22),
              Rise(
                index: 3,
                child: Text('It taps you when something is about to fly over.',
                    style: displaySerif(context, size: 34, weight: FontWeight.w500, italic: true, height: 1.1)),
              ),
              const SizedBox(height: 16),
              Rise(index: 4, child: Text(
                'The space station. A fresh Starlink train. An aurora. '
                'A few minutes before, with which way to face. '
                'Quiet when it\'s cloudy. No account, no setup.',
                style: t.bodyLarge?.copyWith(color: LookUpColors.grey, height: 1.45),
              )),
              const Spacer(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton(
                onPressed: _busy ? null : _go,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(_busy ? 'ONE MOMENT…' : 'ALLOW LOCATION & ALERTS'),
              ),
              const SizedBox(height: 8),
              Text('We only use a rough location, and it never leaves your phone.',
                  style: t.bodySmall?.copyWith(color: LookUpColors.greyDim)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
