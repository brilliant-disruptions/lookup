import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'kit/controls.dart';
import 'theme.dart';

/// One tap to red: everything turns deep red so your eyes stay used to the
/// dark outside. The same switch as Settings › Night vision.
class NightVisionButton extends ConsumerWidget {
  const NightVisionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(settingsProvider).value?.nightVision ?? false;
    return CircleButton(
      tooltip: on ? 'Night vision off' : 'Night vision on',
      icon: Icons.remove_red_eye_rounded,
      color: LookUpColors.red,
      active: on,
      onPressed: () async {
        await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(nightVision: !on));
        if (on || !context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('Night vision on: red light keeps your eyes used to the dark.'),
            duration: Duration(seconds: 3),
          ));
      },
    );
  }
}
