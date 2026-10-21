import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'format.dart';
import 'look_sheet.dart';
import 'theme.dart';

class UpcomingScreen extends ConsumerWidget {
  const UpcomingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('NEXT 7 NIGHTS')),
      body: home.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) {
          final groups = <String, List<SkyEvent>>{};
          for (final e in d.events) {
            groups.putIfAbsent(fmtDay(e.start), () => []).add(e);
          }
          if (groups.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Nothing scheduled over you this week.', textAlign: TextAlign.center)));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
                  child: Eyebrow(g.key),
                ),
                for (final e in g.value)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        onTap: () => showLookSheet(context, e),
                        leading: Text(eventEmoji(e), style: const TextStyle(fontSize: 22)),
                        title: Text(eventTitle(e)),
                        subtitle: Text(eventSubtitle(e)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(fmtTime(e.start), style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(cloudWord(e.cloudCoverPercent).toUpperCase(),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10, letterSpacing: 1.2, color: LookUpColors.grey)),
                          ],
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
