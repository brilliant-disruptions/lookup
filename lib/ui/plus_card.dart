import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plus/plus_preview.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'theme.dart';

/// "LookUp+ near you": a quiet card on Tonight for free users with the real
/// taps they won't get over the next few weeks and what else LookUp+ does.
/// Not a pop-up: it sits in the list, opens the paywall only when tapped,
/// and "Not now" puts it away for a week. Never shown to LookUp+ users.
class PlusNearYouCard extends ConsumerWidget {
  const PlusNearYouCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final events = ref.watch(homeProvider).value?.events;
    final now = DateTime.now();
    if (s == null || events == null || !s.hasLocation) return const SizedBox.shrink();
    if (!PlusPreview.show(isPlus: s.isPlus, snoozedUntil: s.plusCardSnoozedUntil, now: now)) return const SizedBox.shrink();
    final p = PlusPreview.of(events, now);
    final title = switch (p.count) {
      0 => 'More to see than the station',
      1 => '1 more tap coming that free won\'t send',
      final n => '$n more taps coming that free won\'t send',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        tint: LookUpColors.blue,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Kicker('LookUp+ near you', color: LookUpColors.blue),
            const SizedBox(height: 4),
            Text(title, style: display(20, weight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final e in p.soonest)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    EventGlyph.of(e, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(eventTitle(e), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          Text('${fmtDay(e.start)}, ${fmtTime(e.start)}', style: const TextStyle(fontSize: 13, color: LookUpColors.grey)),
                        ],
                      ),
                    ),
                    const Icon(Icons.notifications_off_outlined, size: 18, color: LookUpColors.greyDim, semanticLabel: 'No alert on free'),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Text(
              p.count == 0
                  ? 'Live aurora alerts the moment it starts, where to go for a clear dark sky tonight, the whole fortnight ahead and photo planning.'
                  : 'And where to go for a clear dark sky tonight, the whole fortnight ahead and photo planning.',
              style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.35),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => showPaywall(context, reason: p.soonest.firstOrNull),
                    child: const Text('See LookUp+'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => ref
                      .read(settingsProvider.notifier)
                      .edit((x) => x.copyWith(plusCardSnoozedUntil: DateTime.now().toUtc().add(PlusPreview.snooze))),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
