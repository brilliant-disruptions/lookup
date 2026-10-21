import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../state/providers.dart';
import 'format.dart';
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
            Text(eventTitle(event), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              over
                  ? 'That one\'s over'
                  : live
                      ? 'Happening now — ${fmtCountdown(event.end.difference(nowUtc))} left'
                      : 'in ${fmtCountdown(event.start.difference(nowUtc))}',
              style: t.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Center(child: CompassArrow(azimuthDeg: isAurora ? 0 : event.riseAzimuthDeg)),
            const SizedBox(height: 8),
            Text(
              isAurora
                  ? 'Face north. Get away from streetlights and give your eyes five minutes.'
                  : 'Face ${compassWord(event.riseAzimuthDeg)}. It appears there and climbs ${elevationWord(event.peakElevationDeg)} before fading out toward the ${compassWord(event.setAzimuthDeg)}.',
              textAlign: TextAlign.center,
              style: t.bodyLarge,
            ),
            const SizedBox(height: 20),
            if (!isAurora) PassTimeline(event: event, now: now),
            if (isAurora)
              Text('Window: ${fmtTime(event.start)} – ${fmtTime(event.end)}', textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: Colors.white70)),
            const SizedBox(height: 12),
            Text(
              [
                if (event.details['brightness'] is String) '${event.details['brightness']}',
                cloudWord(event.cloudCoverPercent),
                if (event.isEstimate) 'estimate (orbit data is a few days old)',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 20),
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
