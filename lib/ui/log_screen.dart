import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/log/sky_log.dart';
import '../domain/models/sky_event.dart';
import '../state/providers.dart';
import 'fancy/foil_text.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/rise.dart';
import 'fancy/stat_tile.dart';
import 'format.dart';
import 'theme.dart';

/// Your sky log: what you've seen and the badges you've earned.
class LogScreen extends ConsumerWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(skyLogProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Your sky log', style: displaySerif(context, size: 26, weight: FontWeight.w600))),
      body: log.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (l) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Rise(
              index: 0,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    StatTile(k: 'Seen', v: '${l.total}'),
                    StatTile(k: 'Badges', v: '${l.earnedCount}/${l.badges.length}', align: CrossAxisAlignment.center),
                    StatTile(
                      k: 'Hit rate',
                      v: l.hitRate == null ? '–' : '${(l.hitRate! * 100).round()}%',
                      align: CrossAxisAlignment.end,
                      valueColor: LookUpColors.blue,
                    ),
                  ]),
                ),
              ),
            ),
            if (l.total == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 0),
                child: Text(
                  'Nothing logged yet. After each event LookUp asks "Did you see it?". Every yes lands here.',
                  style: const TextStyle(color: LookUpColors.grey, height: 1.45),
                ),
              ),
            const Padding(padding: EdgeInsets.fromLTRB(0, 26, 0, 14), child: OrnamentRule(label: 'Badges')),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
              children: [for (final (i, b) in l.badges.indexed) Rise(index: 1 + i, child: _BadgeTile(b))],
            ),
            if (l.seen.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.fromLTRB(0, 26, 0, 14), child: OrnamentRule(label: 'Seen')),
              for (final s in l.seen.take(50))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      title: Text(_typeLabel(s.inferredType), style: displaySerif(context, size: 21, weight: FontWeight.w500)),
                      subtitle: Text([
                        fmtDay(s.eventTime ?? s.at),
                        if (s.place != null && s.place!.isNotEmpty) s.place!,
                        if (s.peakElevationDeg != null) '${s.peakElevationDeg!.round()}° up',
                      ].join(' · ')),
                      trailing: s.magnitude == null
                          ? null
                          : Text('mag ${s.magnitude!.toStringAsFixed(1)}', style: monoData(context, size: 12, color: LookUpColors.grey)),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _typeLabel(SkyEventType? t) => switch (t) {
        SkyEventType.iss => 'Space station',
        SkyEventType.tiangong => 'Tiangong',
        SkyEventType.starlinkTrain => 'Starlink train',
        SkyEventType.auroraNow || SkyEventType.auroraOutlook => 'Aurora',
        SkyEventType.meteorShower => 'Meteor shower',
        SkyEventType.lunarEclipse => 'Lunar eclipse',
        SkyEventType.planetPairing => 'Planet pairing',
        SkyEventType.rocketLaunch => 'Rocket launch',
        null => 'Sky event',
      };
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile(this.b);
  final Badge b;
  @override
  Widget build(BuildContext context) {
    final earned = b.earned;
    return Semantics(
      label: '${b.title}${earned ? ', earned' : ', not yet earned'}. ${b.description}',
      child: Container(
        decoration: BoxDecoration(
          color: LookUpColors.panel,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: earned ? const Color(0x663C9DFF) : LookUpColors.line),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(earned ? Icons.auto_awesome : Icons.lock_outline,
              size: 26, color: earned ? LookUpColors.blue : LookUpColors.greyDim),
          const SizedBox(height: 8),
          earned
              ? FoilText(b.title, gold: true, textAlign: TextAlign.center, style: displaySerif(context, size: 17, weight: FontWeight.w600))
              : Text(b.title, textAlign: TextAlign.center, style: displaySerif(context, size: 17, weight: FontWeight.w500, color: LookUpColors.greyDim)),
          const SizedBox(height: 4),
          Text(b.description, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, height: 1.25, color: earned ? LookUpColors.grey : LookUpColors.greyDim)),
        ]),
      ),
    );
  }
}
