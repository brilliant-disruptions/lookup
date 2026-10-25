import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/rise.dart';
import 'format.dart';
import 'look_sheet.dart';
import 'theme.dart';

class UpcomingScreen extends ConsumerWidget {
  const UpcomingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    return Scaffold(
      appBar: AppBar(title: Text('The sky over you', style: displaySerif(context, size: 26, weight: FontWeight.w600))),
      body: home.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final groups = <String, List<SkyEvent>>{};
          for (final e in d.events) {
            groups.putIfAbsent(fmtDay(e.start), () => []).add(e);
          }
          var i = 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 24, 4, 8),
                  child: Text('Nothing alert-worthy over you this week.', style: TextStyle(color: LookUpColors.grey)),
                ),
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 22, 0, 14),
                  child: OrnamentRule(label: g.key),
                ),
                for (final e in g.value)
                  Rise(
                    index: i++,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: InkWell(
                          onTap: () => showLookSheet(context, e),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(eventTitle(e), style: displaySerif(context, size: 24, weight: FontWeight.w500)),
                                    const SizedBox(height: 5),
                                    Text(eventSubtitle(e), style: const TextStyle(color: LookUpColors.grey, fontSize: 13, height: 1.35)),
                                  ]),
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(fmtTime(e.start), style: monoData(context, size: 14, weight: FontWeight.w600)),
                                    const SizedBox(height: 3),
                                    Text(cloudWord(e.cloudCoverPercent).toUpperCase(),
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10, letterSpacing: 1.2, color: LookUpColors.grey)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              if (d.recent.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(0, 30, 0, 14),
                  child: OrnamentRule(label: 'Last 7 nights'),
                ),
                for (final e in d.recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Opacity(
                      opacity: 0.8,
                      child: Card(
                        child: InkWell(
                          onTap: () => showLookSheet(context, e),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(pastTitle(e), style: displaySerif(context, size: 21, weight: FontWeight.w500)),
                                  const SizedBox(height: 3),
                                  Text(pastVerdict(e), style: const TextStyle(color: LookUpColors.grey, fontSize: 12.5)),
                                ]),
                              ),
                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                Text(fmtDay(e.start).toUpperCase(),
                                    style: const TextStyle(color: LookUpColors.grey, fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 3),
                                Text(fmtTime(e.start), style: monoData(context, size: 13, color: LookUpColors.grey)),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
