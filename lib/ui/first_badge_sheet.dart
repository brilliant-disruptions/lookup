/// The first badge, the moment setting up is done: Pip says hi, "Looked up"
/// goes on the shelf, and the next one is named (catch something with Pip).
/// Shown once, the first time Home opens after onboarding.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'kit/kit.dart';
import 'theme.dart';

Future<void> showFirstBadge(BuildContext context) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: LookUpColors.panel,
    builder: (context) => const FirstBadgeSheet(),
  );
}

class FirstBadgeSheet extends StatelessWidget {
  const FirstBadgeSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: PipMark(key: Key('first-badge-pip'), size: 120, state: PipState.greet)),
            const SizedBox(height: 4),
            const Kicker('Your first badge', color: LookUpColors.gold),
            const SizedBox(height: 10),
            Row(children: [
              const EventGlyph(icon: Icons.workspace_premium_rounded, color: LookUpColors.gold, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Looked up', style: display(26, weight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  const Text('You\'re all set. LookUp is watching your sky.',
                      style: TextStyle(color: LookUpColors.grey, height: 1.35)),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            const Text(
              'Next badge: point your phone up, and when Pip waves at something, tap Pip to catch it.',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Let\'s look')),
          ]),
        ),
      );
}
