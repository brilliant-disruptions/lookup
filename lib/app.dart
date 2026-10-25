import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      builder: (context, child) => NightVision(
        enabled: settings.value?.nightVision ?? false,
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
