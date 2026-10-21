import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/home_shell.dart';
import 'ui/onboarding_screen.dart';

class LookUpApp extends ConsumerWidget {
  const LookUpApp({super.key});

  static final theme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF8FB3FF),
      brightness: Brightness.dark,
      surface: const Color(0xFF0B1020),
    ),
    scaffoldBackgroundColor: const Color(0xFF070B16),
    cardTheme: const CardThemeData(
      color: Color(0xFF121A30),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'LookUp',
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: settings.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => Scaffold(body: Center(child: Text('$e'))),
        data: (s) => s.onboarded ? const HomeShell() : const OnboardingScreen(),
      ),
    );
  }
}
