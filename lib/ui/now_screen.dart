import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'format.dart';
import 'look_sheet.dart';
import 'theme.dart';

class NowScreen extends ConsumerWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final settings = ref.watch(settingsProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('LookUp'),
        actions: [
          if (settings?.placeName != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: Eyebrow(settings!.placeName!)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(homeProvider.notifier).refresh(force: true),
        child: home.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
          data: (d) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (d.next == null) const _EmptyCard() else _NextCard(event: d.next!),
              const SizedBox(height: 12),
              if (d.auroraOutlook != null) _OutlookCard(d.auroraOutlook!),
              ..._then(d),
              if (d.errors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text('Some data didn\'t refresh: ${d.errors.length} source(s). Using the last good copy.',
                      style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
                ),
              if (d.lastRefresh != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Eyebrow('Updated ${fmtDay(d.lastRefresh!)} ${fmtTime(d.lastRefresh!)}', color: LookUpColors.greyDim),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _then(HomeData d) {
    final rest = d.events
        .where((e) => e.id != d.next?.id && e.type != SkyEventType.auroraOutlook)
        .take(2)
        .toList();
    if (rest.isEmpty) return const [];
    return [
      const Padding(
        padding: EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Eyebrow('Then'),
      ),
      for (final e in rest) _SmallRow(e),
    ];
  }
}

class _NextCard extends ConsumerWidget {
  const _NextCard({required this.event});
  final SkyEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final t = Theme.of(context).textTheme;
    final live = !now.toUtc().isBefore(event.start);
    final until = event.start.difference(now.toUtc());
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showLookSheet(context, event),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(eventEmoji(event), style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Eyebrow(live ? 'Happening now' : 'Next up', color: live ? LookUpColors.blue : LookUpColors.grey),
                const Spacer(),
                _CloudChip(event.cloudCoverPercent),
              ]),
              const SizedBox(height: 10),
              Text(eventTitle(event), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(live ? 'Go outside now' : 'in ${fmtCountdown(until)}',
                  style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
              const SizedBox(height: 6),
              Text('${fmtDay(event.start)} · ${fmtTime(event.start)}', style: t.bodyMedium?.copyWith(color: LookUpColors.grey)),
              const SizedBox(height: 14),
              Text(eventSubtitle(event), style: t.bodyLarge),
              if (event.isEstimate)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Estimate — orbit data is a few days old', style: t.bodySmall?.copyWith(color: LookUpColors.warn)),
                ),
              if (event.plusOnly && !(ref.watch(settingsProvider).value?.isPlus ?? false))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('LookUp+ taps you 10 minutes before this one.', style: t.bodySmall?.copyWith(color: LookUpColors.grey)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlookCard extends StatelessWidget {
  const _OutlookCard(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Text('🌌', style: TextStyle(fontSize: 22)),
          title: Text(eventTitle(e)),
          subtitle: Text(eventSubtitle(e)),
          trailing: _CloudChip(e.cloudCoverPercent),
        ),
      );
}

class _SmallRow extends StatelessWidget {
  const _SmallRow(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: () => showLookSheet(context, e),
          leading: Text(eventEmoji(e), style: const TextStyle(fontSize: 22)),
          title: Text(eventTitle(e)),
          subtitle: Text('${fmtDay(e.start)} · ${fmtTime(e.start)} · ${e.peakElevationDeg.round()}° peak'),
          trailing: _CloudChip(e.cloudCoverPercent),
        ),
      );
}

class _CloudChip extends StatelessWidget {
  const _CloudChip(this.cover);
  final int? cover;
  @override
  Widget build(BuildContext context) {
    final icon = cover == null
        ? Icons.help_outline
        : cover! <= 20
            ? Icons.nightlight_round
            : cover! <= 60
                ? Icons.cloud_queue
                : Icons.cloud;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: LookUpColors.grey),
      const SizedBox(width: 5),
      Text(cloudWord(cover).toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: LookUpColors.grey, fontSize: 10.5, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();
  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nothing worth going out for yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              Text('Visible passes come in cycles of a couple of weeks. We\'ll tap you when the next one is on. Pull down to refresh.',
                  style: TextStyle(color: LookUpColors.grey)),
            ],
          ),
        ),
      );
}
