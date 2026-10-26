import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'fancy/rise.dart';
import 'fancy/woven.dart';
import 'format.dart';
import 'look_sheet.dart';
import 'places_screen.dart';
import 'satellites_screen.dart';
import 'theme.dart';

/// The week ahead (and the week behind) as a Woven-style timeline.
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
    return Scaffold(
      appBar: WovenHeader(
        title: const Text('The week'),
        subtitle: (place?.isNotEmpty ?? false) ? place! : 'Near you',
        onSubtitleTap: () => openPlaces(context),
      ),
      body: home.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final coming = d.events;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              WovenTabs(
                labels: const ['Coming up', 'Last 7 nights'],
                counts: [coming.length, d.recent.length],
                index: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 18),
              if (_tab == 0) ...[
                _SatellitesRow(),
                const SizedBox(height: 18),
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
    );
  }

  /// Day label, then that day's events on the timeline.
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(left: 2, bottom: 10), child: Eyebrow(g.key)),
            WovenTimeline(items: [
              for (final e in g.value)
                WovenTimelineItem(
                  now: !past && !now.isBefore(e.start) && now.isBefore(e.end),
                  dim: past || !e.type.pushes,
                  child: _EventLine(e, past: past),
                ),
            ]),
          ]),
        ),
    ];
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine(this.e, {required this.past});
  final SkyEvent e;
  final bool past;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => showLookSheet(context, e),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(past ? pastTitle(e) : eventTitle(e),
                  style: displaySerif(context, size: 22, weight: FontWeight.w500,
                      color: past ? LookUpColors.grey : LookUpColors.white)),
              const SizedBox(height: 3),
              Text(past ? pastVerdict(e) : eventSubtitle(e),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: LookUpColors.grey, fontSize: 13, height: 1.35)),
            ]),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(fmtTime(e.start), style: monoData(context, size: 13, color: LookUpColors.grey)),
          ),
        ]),
      );
}

class _SatellitesRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: () => openSatellitesTonight(context),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              Icon(Icons.satellite_alt_outlined, size: 20, color: LookUpColors.blue),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Satellites tonight', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text('Hubble and the other bright ones passing over', style: TextStyle(color: LookUpColors.grey, fontSize: 12.5)),
                ]),
              ),
              Icon(Icons.chevron_right, size: 20, color: LookUpColors.greyDim),
            ]),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
        child: Text(text, style: const TextStyle(color: LookUpColors.grey, height: 1.45)),
      );
}
