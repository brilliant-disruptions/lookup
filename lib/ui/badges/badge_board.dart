/// The Log's patch board: this season's patches (with their best night),
/// then every patch. A tap opens the patch: how to earn it, how close you
/// are, and the next real chance over you. Nothing here sends a thing.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Badge;

import '../../domain/log/next_chance.dart';
import '../../domain/log/sky_log.dart';
import '../../domain/models/sky_event.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../kit/kit.dart';
import '../theme.dart';
import 'patch.dart';

class BadgeBoard extends ConsumerWidget {
  const BadgeBoard({super.key, required this.log});
  final SkyLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(homeProvider).value?.events ?? const <SkyEvent>[];
    final now = DateTime.now();
    final season = log.comingSeason(events, now);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (season.isNotEmpty) ...[
        const Kicker('This season', color: LookUpColors.cyan),
        const SizedBox(height: 8),
        for (final b in season)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SeasonRow(b: b, now: now, onTap: () => showBadgeSheet(context, b)),
          ),
        const SizedBox(height: 10),
        const Kicker('Your patches', color: LookUpColors.gold),
        const SizedBox(height: 8),
      ],
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 8,
        childAspectRatio: 0.74,
        children: [
          for (final (i, b) in log.badges.indexed)
            Rise(index: i, child: _PatchTile(b: b, next: nextChance(b, events, now), onTap: () => showBadgeSheet(context, b))),
        ],
      ),
    ]);
  }
}

/// "3 of 5", "Gold", "Next: Tue", or what kind of secret.
String patchLine(Badge b, SkyEvent? next) {
  if (b.hidden) return 'Secret';
  if (b.progress case final p?) return '${p.got} of ${p.of}';
  if (b.tier case final t?) return t.label;
  if (b.earned) return 'Sewn on';
  if (next != null) return 'Next: ${fmtDay(next.peak)}';
  return '';
}

class _PatchTile extends StatelessWidget {
  const _PatchTile({required this.b, required this.next, required this.onTap});
  final Badge b;
  final SkyEvent? next;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = patchLine(b, next);
    return Semantics(
      button: true,
      label: b.hidden ? 'Secret badge. ${b.riddle}' : '${b.fullTitle}, ${b.earned ? 'earned' : 'not yet earned'}. $line',
      excludeSemantics: true,
      child: Pressable(
        key: Key('patch-${b.id}'),
        onTap: onTap,
        child: Column(children: [
          LayoutBuilder(builder: (context, box) => BadgePatch.of(b, size: box.maxWidth.clamp(0, 92).toDouble())),
          const SizedBox(height: 6),
          Text(
            b.hidden ? '???' : b.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2, color: b.earned ? LookUpColors.white : LookUpColors.grey),
          ),
          if (line.isNotEmpty)
            Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: LookUpColors.greyDim)),
        ]),
      ),
    );
  }
}

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({required this.b, required this.now, required this.onTap});
  final Badge b;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final best = b.season!;
    final days = best.toLocal().difference(DateTime(now.year, now.month, now.day)).inDays;
    return Pressable(
      key: Key('season-${b.id}'),
      onTap: onTap,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(children: [
          BadgePatch.of(b, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text('Best night: ${fmtDay(best)}', style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
            ]),
          ),
          Pill(days <= 0 ? 'Tonight' : days == 1 ? 'Tomorrow' : '$days days', color: LookUpColors.cyan),
        ]),
      ),
    );
  }
}

Future<void> showBadgeSheet(BuildContext context, Badge b) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: LookUpColors.panel,
    builder: (_) => BadgeSheet(b: b),
  );
}

/// One patch, up close: how to earn it, how close you are, the next chance.
class BadgeSheet extends ConsumerWidget {
  const BadgeSheet({super.key, required this.b});
  final Badge b;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(homeProvider).value?.events ?? const <SkyEvent>[];
    final place = ref.watch(settingsProvider).value?.placeName;
    final next = nextChance(b, events, DateTime.now());
    final p = b.progress;
    final nextGoalName = b.goals == null || p == null
        ? null
        : switch (b.goals!.indexOf(p.of)) { 0 => 'bronze', 1 => 'silver', _ => 'gold' };
    return SafeArea(
      child: SingleChildScrollView(
        key: Key('badge-sheet-${b.id}'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: BadgePatch.of(b, size: 132)),
          const SizedBox(height: 12),
          Text(b.hidden ? 'A secret patch' : b.fullTitle, textAlign: TextAlign.center, style: display(24, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(b.hidden ? b.riddle ?? '' : b.description,
              textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.grey, height: 1.45)),
          if (b.earnedAt case final at? when !b.hidden) ...[
            const SizedBox(height: 6),
            Text(b.tier == null ? 'Sewn on ${fmtDay(at)}' : 'First sewn on ${fmtDay(at)}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: LookUpColors.greyDim)),
          ],
          if (b.slots case final slots?) ...[
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              for (final s in slots) Pill(s.got ? s.label : '${s.label} ?', color: s.got ? LookUpColors.gold : LookUpColors.greyDim),
            ]),
          ],
          if (p != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                key: const Key('badge-progress'),
                value: p.got / p.of,
                minHeight: 6,
                backgroundColor: LookUpColors.glassStrong,
                color: fireflyGlow,
              ),
            ),
            const SizedBox(height: 6),
            Text(nextGoalName == null ? '${p.got} of ${p.of}' : '${p.got} of ${p.of} for $nextGoalName',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
          ],
          if (!b.hidden && (p != null || !b.earned)) ...[
            const SizedBox(height: 14),
            GlassCard(
              key: const Key('badge-next-chance'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                const PipMark(size: 26, mood: PipMood.curious),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    next != null
                        ? 'Next chance${place == null ? '' : ' over $place'}: ${eventTitle(next)}, ${fmtDay(next.peak)} at ${fmtTime(next.peak)}'
                        : _noChanceLine(b),
                    style: const TextStyle(fontSize: 13.5, height: 1.35),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ]),
      ),
    );
  }

  static String _noChanceLine(Badge b) => switch (b.id) {
        'aurora-chaser' => 'Aurora can\'t be known days ahead. Pip taps you the moment it\'s visible from here.',
        'planet-set' => 'Look in Explore for the planets up tonight, then catch them with Pip.',
        'moon-phases' => 'Catch the Moon with Pip on a few different nights as it changes.',
        'eclipse' || 'shadow' => 'None over you soon. Pip will tell you when there is one.',
        _ => 'Nothing coming over you yet. Pip will tell you.',
      };
}

/// A patch arriving: it spins in and its stitched ring sews itself on.
class PatchArrives extends StatelessWidget {
  const PatchArrives({super.key, required this.b, this.size = 64, this.delay = Duration.zero, this.animate = true});
  final Badge b;
  final double size;
  final Duration delay;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate || MediaQuery.disableAnimationsOf(context)) return BadgePatch.of(b, size: size);
    final total = const Duration(milliseconds: 1300) + delay;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      builder: (_, v, _) {
        final k = ((v - start) / (1 - start)).clamp(0.0, 1.0);
        final spin = Curves.elasticOut.transform((k / 0.6).clamp(0.0, 1.0));
        final sew = Curves.easeInOut.transform(((k - 0.35) / 0.65).clamp(0.0, 1.0));
        return Opacity(
          opacity: (k * 4).clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: (1 - spin) * -0.6,
            child: Transform.scale(scale: 0.3 + 0.7 * spin, child: BadgePatch.of(b, size: size, stitch: sew)),
          ),
        );
      },
    );
  }
}
