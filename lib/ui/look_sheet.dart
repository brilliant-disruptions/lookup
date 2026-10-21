import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../state/providers.dart';
import 'fancy/foil_text.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/stat_tile.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/compass_arrow.dart';
import 'widgets/pass_timeline.dart';

Future<void> showLookSheet(BuildContext context, SkyEvent event) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => LookSheet(event: event),
    );

/// What the notification opens: countdown, where to look, timeline, share.
class LookSheet extends ConsumerWidget {
  const LookSheet({super.key, required this.event});
  final SkyEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final t = Theme.of(context).textTheme;
    final nowUtc = now.toUtc();
    final live = !nowUtc.isBefore(event.start) && nowUtc.isBefore(event.end);
    final over = !nowUtc.isBefore(event.end);
    final isAurora = event.type == SkyEventType.auroraNow || event.type == SkyEventType.auroraOutlook;
    final place = ref.watch(settingsProvider).value?.placeName;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(eventTitle(event), style: displaySerif(context, size: 38, weight: FontWeight.w500)),
            const SizedBox(height: 2),
            FoilText(
              over
                  ? 'That one\'s over'
                  : live
                      ? 'Now — ${fmtCountdown(event.end.difference(nowUtc))} left'
                      : 'in ${fmtCountdown(event.start.difference(nowUtc))}',
              style: displaySerif(context, size: 44, weight: FontWeight.w600, italic: true, height: 1.0),
            ),
            const SizedBox(height: 18),
            Center(child: CompassArrow(azimuthDeg: isAurora ? 0 : event.riseAzimuthDeg)),
            const SizedBox(height: 10),
            Text(
              isAurora
                  ? 'Face north. Get away from streetlights and give your eyes five minutes.'
                  : 'Face ${compassWord(event.riseAzimuthDeg)}. It appears there and climbs ${elevationWord(event.peakElevationDeg)} before fading out toward the ${compassWord(event.setAzimuthDeg)}.',
              textAlign: TextAlign.center,
              style: t.bodyLarge,
            ),
            const SizedBox(height: 18),
            const OrnamentRule(),
            const SizedBox(height: 16),
            if (!isAurora) PassTimeline(event: event, now: now),
            if (isAurora)
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                StatTile(k: 'From', v: fmtTime(event.start), align: CrossAxisAlignment.center),
                StatTile(k: 'Until', v: fmtTime(event.end), align: CrossAxisAlignment.center),
                StatTile(k: 'Kp', v: (event.details['kp'] as num?)?.toStringAsFixed(1) ?? '–', align: CrossAxisAlignment.center),
              ]),
            const SizedBox(height: 14),
            Text(
              [
                if (event.details['brightness'] is String) '${event.details['brightness']}',
                cloudWord(event.cloudCoverPercent),
                if (event.isEstimate) 'estimate (orbit data is a few days old)',
              ].join('  ·  ').toUpperCase(),
              textAlign: TextAlign.center,
              style: t.labelSmall?.copyWith(color: LookUpColors.greyDim, letterSpacing: 1.8, fontSize: 10.5, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => SharePlus.instance.share(ShareParams(text: shareText(event, place))),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: Text(over || live ? 'I saw it!' : 'Got it'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
