import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
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
    final place = ref.watch(settingsProvider).value?.placeName;
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
                    ..._byNight(coming, past: false),
                ] else if (d.recent.isEmpty)
                  const _Empty('Nothing passed over in the last week.')
                else
                  ..._byNight(d.recent, past: true),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Day header, then that day's events on one card.
  List<Widget> _byNight(List<SkyEvent> events, {required bool past}) {
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
                _EventRow(e, past: past, now: !past && !now.isBefore(e.start) && now.isBefore(e.end)),
            ]),
          ]),
        ),
    ];
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e, {required this.past, required this.now});
  final SkyEvent e;
  final bool past;
  final bool now;

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
        ],
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
