import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'fancy/foil_text.dart';
import 'fancy/invite_frame.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/rise.dart';
import 'fancy/starfield.dart';
import 'format.dart';
import 'look_sheet.dart';
import 'paywall_sheet.dart';
import 'theme.dart';

class NowScreen extends ConsumerWidget {
  const NowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final settings = ref.watch(settingsProvider).value;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('LookUp', style: displaySerif(context, size: 26, weight: FontWeight.w600)),
          Text('.', style: displaySerif(context, size: 26, weight: FontWeight.w700, color: LookUpColors.blue)),
        ]),
        actions: [
          if (settings?.placeName != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: Eyebrow(settings!.placeName!)),
            ),
        ],
      ),
      body: Starfield(
        child: RefreshIndicator(
        onRefresh: () => ref.read(homeProvider.notifier).refresh(force: true),
        child: home.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
          data: (d) => ListView(
            padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 64, 16, 32),
            children: [
              Rise(index: 0, child: d.next == null ? const _EmptyCard() : _NextCard(event: d.next!)),
              const SizedBox(height: 14),
              if (d.auroraOutlook != null) Rise(index: 1, child: _OutlookCard(d.auroraOutlook!)),
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
        padding: EdgeInsets.fromLTRB(4, 26, 4, 14),
        child: OrnamentRule(label: 'Then'),
      ),
      for (final (i, e) in rest.indexed) Rise(index: 2 + i, child: _SmallRow(e)),
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
    return InviteFrame(
      onTap: () => showLookSheet(context, event),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Eyebrow(live ? 'Happening now' : 'Next up', color: live ? LookUpColors.blue : LookUpColors.grey),
                const Spacer(),
                _CloudChip(event.cloudCoverPercent),
              ]),
              const SizedBox(height: 14),
              Text(eventTitle(event), style: displaySerif(context, size: 40, weight: FontWeight.w500)),
              const SizedBox(height: 2),
              FoilText(
                live ? 'Go outside now' : 'in ${fmtCountdown(until)}',
                style: displaySerif(context, size: 58, weight: FontWeight.w600, italic: true, height: 1.0),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Text(fmtDay(event.start).toUpperCase(),
                    style: t.labelSmall?.copyWith(color: LookUpColors.grey, letterSpacing: 2, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Container(width: 1, height: 10, color: LookUpColors.line),
                const SizedBox(width: 10),
                Text(fmtTime(event.start), style: monoData(context, size: 13, color: LookUpColors.grey)),
              ]),
              const SizedBox(height: 16),
              Container(height: 1, color: LookUpColors.line),
              const SizedBox(height: 14),
              Text(eventSubtitle(event), style: t.bodyLarge?.copyWith(height: 1.4)),
              if (event.isEstimate)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Estimate — orbit data is a few days old', style: t.bodySmall?.copyWith(color: LookUpColors.warn)),
                ),
              if (event.plusOnly && !(ref.watch(settingsProvider).value?.isPlus ?? false))
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: GestureDetector(
                    onTap: () => showPaywall(context, reason: event),
                    child: Row(children: [
                      const Eyebrow('LookUp+ taps you 10 min before', color: LookUpColors.blue),
                      const Spacer(),
                      Icon(Icons.arrow_forward, size: 16, color: LookUpColors.blue),
                    ]),
                  ),
                ),
            ],
          ),
    );
  }
}

class _OutlookCard extends StatelessWidget {
  const _OutlookCard(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eventTitle(e), style: displaySerif(context, size: 24, weight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(eventSubtitle(e), style: const TextStyle(color: LookUpColors.grey, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 12),
            _CloudChip(e.cloudCoverPercent),
          ]),
        ),
      );
}

class _SmallRow extends StatelessWidget {
  const _SmallRow(this.e);
  final SkyEvent e;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: InkWell(
            onTap: () => showLookSheet(context, e),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(eventTitle(e), style: displaySerif(context, size: 24, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(fmtDay(e.start).toUpperCase(),
                            style: const TextStyle(color: LookUpColors.grey, fontSize: 10.5, letterSpacing: 1.8, fontWeight: FontWeight.w700)),
                        Text('${fmtTime(e.start)} · ${e.peakElevationDeg.round()}°',
                            style: monoData(context, size: 12, color: LookUpColors.grey)),
                      ],
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                _CloudChip(e.cloudCoverPercent),
              ]),
            ),
          ),
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
              Text('Nothing worth going out for yet', style: TextStyle(fontFamily: 'Cormorant', fontSize: 30, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('Visible passes come in cycles of a couple of weeks. We\'ll tap you when the next one is on. Pull down to refresh.',
                  style: TextStyle(color: LookUpColors.grey)),
            ],
          ),
        ),
      );
}
