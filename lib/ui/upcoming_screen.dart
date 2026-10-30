import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/scheduling/missed.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'plan_screen.dart';
import 'satellites_screen.dart';
import 'theme.dart';
import 'where_to_go_screen.dart';

/// The week ahead (and the week behind), night by night.
class UpcomingScreen extends ConsumerStatefulWidget {
  const UpcomingScreen({super.key});
  @override
  ConsumerState<UpcomingScreen> createState() => _UpcomingScreenState();
}

class _UpcomingScreenState extends ConsumerState<UpcomingScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(homeProvider);
    final settings = ref.watch(settingsProvider).value;
    final place = settings?.placeName;
    final isPlus = settings?.isPlus ?? false;
    final top = MediaQuery.paddingOf(context).top + AppHeader.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppHeader(
        title: const Text('The week'),
        place: (place?.isNotEmpty ?? false) ? place! : 'Near you',
        onPlaceTap: () => openPlaces(context),
      ),
      body: SkyBackdrop(
        stars: false,
        child: home.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (d) {
            final coming = d.events;
            final missed = isPlus ? const <SkyEvent>[] : missedWithoutPlus(d.recent);
            return ListView(
              padding: EdgeInsets.fromLTRB(16, top + 14, 16, tabBarClearance(context)),
              children: [
                SegmentedTabs(
                  labels: const ['Coming up', 'Last 7 nights'],
                  counts: [coming.length, d.recent.length],
                  index: _tab,
                  onSelect: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 14),
                if (_tab == 0) ...[
                  if (missed.isNotEmpty) ...[
                    _MissedCard(
                      missed: missed,
                      lead: settings?.leadMinutes ?? 10,
                      next: coming.where((e) => e.plusOnly && e.type.pushes).firstOrNull,
                    ),
                    const SizedBox(height: 14),
                  ],
                  GroupedList(indent: 64, children: [
                    ListRow(
                      leading: const EventGlyph(icon: Icons.calendar_month_rounded, color: LookUpColors.violet),
                      title: 'Plan a night',
                      subtitle: 'Any night in the next two weeks, here or at a saved place',
                      onTap: () => openPlan(context),
                    ),
                    ListRow(
                      leading: const EventGlyph(icon: Icons.near_me_rounded, color: LookUpColors.violet),
                      title: 'Where to go tonight',
                      subtitle: 'Compare tonight\'s clouds at your saved places',
                      onTap: () => openWhereToGo(context),
                    ),
                    ListRow(
                      leading: EventGlyph.forType(SkyEventType.satellitePass),
                      title: 'Satellites tonight',
                      subtitle: 'Hubble and the other bright ones passing over',
                      onTap: () => openSatellitesTonight(context),
                    ),
                  ]),
                  if (coming.isEmpty)
                    const _Empty('Nothing worth stepping out for this week. We\'ll tap you when there is.')
                  else
                    ..._byNight(coming, past: false, isPlus: isPlus),
                ] else if (d.recent.isEmpty)
                  const _Empty('Nothing passed over in the last week.')
                else
                  ..._byNight(d.recent, past: true, isPlus: isPlus),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Day header, then that day's events on one card.
  List<Widget> _byNight(List<SkyEvent> events, {required bool past, required bool isPlus}) {
    final groups = <String, List<SkyEvent>>{};
    for (final e in events) {
      groups.putIfAbsent(fmtDay(e.start), () => []).add(e);
    }
    final now = DateTime.now().toUtc();
    var i = 0;
    return [
      for (final g in groups.entries)
        Rise(
          index: i++,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(g.key, padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
            GroupedList(indent: 64, children: [
              for (final e in g.value)
                _EventRow(e,
                    past: past,
                    now: !past && !now.isBefore(e.start) && now.isBefore(e.end),
                    locked: !isPlus && e.plusOnly && e.type.pushes),
            ]),
          ]),
        ),
    ];
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e, {required this.past, required this.now, this.locked = false});
  final SkyEvent e;
  final bool past;
  final bool now;

  /// Plus-only, for someone on free: no tap unless they upgrade.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final quiet = past || !e.type.pushes;
    return ListRow(
      onTap: () => showLookSheet(context, e),
      leading: EventGlyph.of(e, dim: past),
      title: past ? pastTitle(e) : eventTitle(e),
      titleColor: quiet ? LookUpColors.grey : LookUpColors.white,
      subtitle: past ? pastVerdict(e) : eventSubtitle(e),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text(fmtTime(e.start), style: numeric(size: 14, weight: FontWeight.w600, color: quiet ? LookUpColors.grey : LookUpColors.white)),
        if (now) ...[
          const SizedBox(height: 4),
          const Pill('Now', dot: true, color: LookUpColors.good),
        ] else if (!past && !e.type.pushes) ...[
          const SizedBox(height: 4),
          const Text('No alert', style: TextStyle(fontSize: 11.5, color: LookUpColors.greyDim)),
        ] else if (!past && locked) ...[
          const SizedBox(height: 4),
          const Text('LookUp+', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: LookUpColors.blue)),
        ],
      ]),
    );
  }
}

/// "You missed it": Plus-only sights that really went over in clear sky
/// last week, for someone on free. Loss is the honest pitch here, because
/// every one of these happened.
class _MissedCard extends StatelessWidget {
  const _MissedCard({required this.missed, required this.lead, this.next});
  final List<SkyEvent> missed;
  final int lead;

  /// The next Plus-only thing coming, for the paywall's headline.
  final SkyEvent? next;

  @override
  Widget build(BuildContext context) {
    final n = missed.length;
    return GlassCard(
      tint: LookUpColors.orange,
      onTap: () => showPaywall(context, reason: next),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Kicker('Last 7 nights', color: LookUpColors.orange),
        const SizedBox(height: 6),
        Text(n == 1 ? 'You missed one' : 'You missed $n', style: display(26, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final e in missed.take(3))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              EventGlyph.of(e, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(pastTitle(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text('${fmtDay(e.start)}, ${fmtTime(e.start)}', style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey)),
            ]),
          ),
        const SizedBox(height: 2),
        Text(
          'Each under a mostly clear sky over you. LookUp+ would have tapped you $lead minutes before.',
          style: const TextStyle(color: LookUpColors.grey, height: 1.4),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => showPaywall(context, reason: next),
          child: const Text('Don\'t miss the next one'),
        ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 0),
        child: Text(text, style: const TextStyle(color: LookUpColors.grey, height: 1.45)),
      );
}
