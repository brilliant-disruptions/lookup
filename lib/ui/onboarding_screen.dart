import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

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
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(onboarded: true));
    // First refresh runs after the shell mounts.
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text('🛰️', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 20),
              Text('LookUp taps you when something is about to fly over.',
                  style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Text(
                'The space station. A fresh Starlink train. An aurora. '
                'A few minutes before, with which way to face. '
                'Quiet when it\'s cloudy. No account, no setup.',
                style: t.bodyLarge?.copyWith(color: Colors.white70),
              ),
              const Spacer(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton(
                onPressed: _busy ? null : _go,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(_busy ? 'One moment…' : 'Allow location & alerts'),
              ),
              const SizedBox(height: 8),
              Text('We only use a rough location, and it never leaves your phone.',
                  style: t.bodySmall?.copyWith(color: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }
}
