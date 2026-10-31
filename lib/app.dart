import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/night_state.dart';
import 'state/providers.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding_screen.dart';
import 'ui/theme.dart';

class LookUpApp extends ConsumerWidget {
  const LookUpApp({super.key});

  static final theme = buildLookUpTheme();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'LookUp',
      theme: theme,
      debugShowCheckedModeBanner: false,
      // Its own Consumer, so a new light reading repaints only the filter.
      builder: (context, child) => Consumer(
        builder: (context, ref, child) {
          final on = ref.watch(nightVisionOnProvider);
          return NightVision(
            enabled: on,
            // Watched only while on; full red until the first reading.
            strength: on ? ref.watch(nightVisionStrengthProvider).value ?? 1 : 1,
            child: child!,
          );
        },
        // Respect large text, but cap it where the layouts would break.
        child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.6, child: child ?? const SizedBox()),
      ),
      home: settings.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
        data: (s) => s.onboarded ? const HomeShell() : const OnboardingScreen(),
      ),
    );
  }
}
