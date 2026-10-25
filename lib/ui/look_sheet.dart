import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/local_store.dart';
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
/// After the event: "Did you see it?" (spec §3.3), stored on-device.
class LookSheet extends ConsumerStatefulWidget {
  const LookSheet({super.key, required this.event, this.demo = false});
  final SkyEvent event;

  /// Preview mode: labelled, nothing stored, no share.
  final bool demo;
  @override
  ConsumerState<LookSheet> createState() => _LookSheetState();
}

class _LookSheetState extends ConsumerState<LookSheet> {
  bool? _seen;
  bool _askingWhy = false;

  SkyEvent get event => widget.event;

  Future<void> _answer(bool seen, {String? reason}) async {
    if (widget.demo) {
      setState(() {
        _seen = seen;
        _askingWhy = !seen && reason == null;
      });
      return;
    }
    await ref.read(storeProvider).addFeedback(SeenFeedback(eventId: event.id, seen: seen, at: DateTime.now().toUtc(), reason: reason));
    if (!mounted) return;
    setState(() {
      _seen = seen;
      _askingWhy = !seen && reason == null;
    });
  }

  @override
  Widget build(BuildContext context) {
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
            if (widget.demo)
              const Padding(padding: EdgeInsets.only(bottom: 6), child: Eyebrow('Preview · a pass in fast-forward', color: LookUpColors.blue)),
            if (event.details['past'] == true)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Eyebrow('${fmtDay(event.start)} · ${pastVerdict(event)}')),
            Text(event.details['past'] == true ? pastTitle(event) : eventTitle(event),
                style: displaySerif(context, size: 38, weight: FontWeight.w500)),
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
            if (widget.demo && over)
              _demoDone(context)
            else if (over || live)
              _feedbackRow(context, place)
            else
              _plainRow(context, place),
          ],
        ),
      ),
    );
  }

  Widget _demoDone(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('That\'s a LookUp night.', textAlign: TextAlign.center,
            style: displaySerif(context, size: 26, italic: true, weight: FontWeight.w500)),
        const SizedBox(height: 6),
        const Text('The real one taps you 10 minutes before, then again at one minute. Afterwards it asks if you saw it.',
            textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey, height: 1.4)),
        const SizedBox(height: 14),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
      ]);

  Widget _plainRow(BuildContext context, String? place) => Row(children: [
        if (!widget.demo) Expanded(
          child: OutlinedButton.icon(
            onPressed: () => SharePlus.instance.share(ShareParams(text: shareText(event, place))),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share'),
          ),
        ),
        if (!widget.demo) const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check),
            label: const Text('Got it'),
          ),
        ),
      ]);

  Widget _feedbackRow(BuildContext context, String? place) {
    final t = Theme.of(context).textTheme;
    if (_seen == true) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Glad you caught it.', textAlign: TextAlign.center, style: displaySerif(context, size: 24, italic: true, weight: FontWeight.w500)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => SharePlus.instance.share(ShareParams(text: shareText(event, place))),
          icon: const Icon(Icons.ios_share),
          label: const Text('Share it'),
        ),
      ]);
    }
    if (_askingWhy) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('What got in the way?', textAlign: TextAlign.center, style: t.titleMedium),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          for (final (label, key) in const [('Clouds', 'clouds'), ('Too low', 'too-low'), ('Missed it', 'missed')])
            OutlinedButton(onPressed: () => _answer(false, reason: key), child: Text(label)),
        ]),
      ]);
    }
    if (_seen == false) {
      return const Text('Thanks. We\'ll be pickier next time.', textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Did you see it?', textAlign: TextAlign.center, style: displaySerif(context, size: 26, weight: FontWeight.w500)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: () => _answer(false), child: const Text('No'))),
        const SizedBox(width: 12),
        Expanded(child: FilledButton(onPressed: () => _answer(true), child: const Text('Yes!'))),
      ]),
    ]);
  }
}
