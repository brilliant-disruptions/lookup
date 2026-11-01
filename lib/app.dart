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
  static bool _hinted = false;

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
          // The first time it turns red by itself this session, say why.
          ref.listen(nightVisionRedProvider, (was, red) {
            if (!red || _hinted || ref.read(nightVisionDragProvider) != null) return;
            _hinted = true;
            ScaffoldMessenger.maybeOf(context)
              ?..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(
                content: Text('The Sun\'s down, so the screen went red to keep your eyes used to the dark. '
                    'Press and hold Settings to change how red.'),
                duration: Duration(seconds: 5),
              ));
          });
          final red = ref.watch(nightVisionRedProvider);
          return NightVision(
            enabled: red,
            // Watched only while red; full red until the first light reading.
            strength: red ? ref.watch(nightVisionStrengthProvider) : 0,
            quick: ref.watch(nightVisionDragProvider) != null,
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
