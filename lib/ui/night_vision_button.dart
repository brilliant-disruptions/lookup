import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/night_state.dart';
import '../state/providers.dart';
import 'kit/controls.dart';
import 'theme.dart';

/// One tap to red: everything turns deep red so your eyes stay used to the
/// dark outside. On the everyday screens it's the same switch as Settings ›
/// Night vision; on an outside screen it decides for that visit only.
class NightVisionButton extends ConsumerWidget {
  const NightVisionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(nightVisionOnProvider);
    final outside = ref.watch(outsideScreensProvider) > 0;
    return CircleButton(
      tooltip: on ? 'Night vision off' : 'Night vision on',
      icon: Icons.remove_red_eye_rounded,
      color: LookUpColors.red,
      active: on,
      onPressed: () async {
        if (outside) {
          ref.read(nightOverrideProvider.notifier).set(!on);
        } else {
          await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(nightVision: !on));
        }
        if (on || !context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Night vision on: red light keeps your eyes used to the dark.'), duration: Duration(seconds: 3)),
          );
      },
    );
  }
}

/// Marks a screen that's used outside, in the dark: while it's open the app
/// can turn red by itself after dark (Settings › Red by itself outside).
/// The first time that happens in a session it says so, once.
class OutsideScreen extends ConsumerStatefulWidget {
  const OutsideScreen({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<OutsideScreen> createState() => _OutsideScreenState();
}

class _OutsideScreenState extends ConsumerState<OutsideScreen> {
  static bool _hinted = false;
  late final OutsideScreens _screens;

  @override
  void initState() {
    super.initState();
    _screens = ref.read(outsideScreensProvider.notifier);
    // Not during build: other widgets watch this count.
    scheduleMicrotask(() {
      try {
        _screens.enter();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    final screens = _screens;
    scheduleMicrotask(() {
      try {
        screens.exit();
      } catch (_) {
        // The app is shutting down; nothing to count.
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(nightVisionOnProvider, (was, on) {
      final s = ref.read(settingsProvider).value;
      final byItself = on && !(s?.nightVision ?? false) && ref.read(nightOverrideProvider) == null;
      if (!byItself || _hinted || !mounted) return;
      _hinted = true;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('It\'s dark out, so the screen went red to keep your eyes adjusted. Tap the eye to switch it off.'),
            duration: Duration(seconds: 4),
          ),
        );
    });
    return widget.child;
  }
}
