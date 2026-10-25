import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../state/providers.dart';
import 'fancy/foil_text.dart';
import 'finder_screen.dart';
import 'share_card.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/stat_tile.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/compass_arrow.dart';
import 'widgets/countdown_ring.dart';
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

  @override
  void initState() {
    super.initState();
    // Opening an event that's about to start: put the countdown on the Lock
    // Screen / Dynamic Island (iOS 16.2+, once the widget extension exists).
    if (!widget.demo && event.details['past'] != true) {
      unawaited(ref.read(liveActivityProvider).startIfSoon(event));
    }
  }

  Future<void> _answer(bool seen, {String? reason}) async {
    if (widget.demo) {
      setState(() {
        _seen = seen;
        _askingWhy = !seen && reason == null;
      });
      return;
    }
    await ref.read(storeProvider).addFeedback(SeenFeedback.forEvent(event,
        seen: seen, reason: reason, place: ref.read(settingsProvider).value?.placeName));
    ref.invalidate(skyLogProvider);
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
    final isPass = event.type == SkyEventType.iss || event.type == SkyEventType.tiangong || event.type == SkyEventType.starlinkTrain;
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
            Semantics(
              liveRegion: true,
              child: FoilText(
              over
                  ? 'That one\'s over'
                  : live
                      ? 'Now — ${fmtCountdown(event.end.difference(nowUtc))} left'
                      : 'in ${fmtCountdown(event.start.difference(nowUtc))}',
              style: displaySerif(context, size: 44, weight: FontWeight.w600, italic: true, height: 1.0),
            ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Semantics(
                label: 'Compass arrow pointing ${compassWord(isAurora ? 0 : (isPass ? event.riseAzimuthDeg : event.peakAzimuthDeg))}',
                child: CountdownRing(
                  progress: event.details['past'] == true ? null : ringProgress(event, now),
                  live: live,
                  child: CompassArrow(azimuthDeg: isAurora ? 0 : (isPass ? event.riseAzimuthDeg : event.peakAzimuthDeg)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              lookLine(event),
              textAlign: TextAlign.center,
              style: t.bodyLarge,
            ),
            const SizedBox(height: 18),
            const OrnamentRule(),
            const SizedBox(height: 16),
            if (isPass)
              Semantics(
                label: 'Rises ${compassWord(event.riseAzimuthDeg)} at ${fmtTime(event.start)}, '
                    'peaks ${event.peakElevationDeg.round()} degrees at ${fmtTime(event.peak)}, '
                    'sets ${compassWord(event.setAzimuthDeg)} at ${fmtTime(event.end)}',
                child: PassTimeline(event: event, now: now),
              )
            else
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final (k, v) in statsFor(event)) StatTile(k: k, v: v, align: CrossAxisAlignment.center),
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
            if (!over && event.details['past'] != true)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () => openFinder(context, event),
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('FIND IT IN THE SKY'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ),
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
            onPressed: () => showShareCard(context, event, mode: ShareMode.invite),
            icon: const Icon(Icons.group_add_outlined),
            label: const Text('Tell someone'),
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
          onPressed: () => showShareCard(context, event),
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

/// One plain sentence: where to look and what you'll see.
String lookLine(SkyEvent e) => switch (e.type) {
      SkyEventType.auroraNow || SkyEventType.auroraOutlook =>
        'Face north. Get away from streetlights and give your eyes five minutes.',
      SkyEventType.meteorShower =>
        'Lie back and look up, anywhere. Meteors seem to come from the ${compassWord(e.peakAzimuthDeg)}, but they streak across the whole sky. Give your eyes 20 minutes in the dark.',
      SkyEventType.lunarEclipse =>
        'Look ${compassWord(e.peakAzimuthDeg)} at the Moon, ${elevationWord(e.peakElevationDeg)}. It darkens and turns copper-red at its deepest.',
      SkyEventType.planetPairing =>
        '${e.details['label']}: two bright points ${e.details['separation']}° apart, ${elevationWord(e.peakElevationDeg)} in the ${compassWord(e.peakAzimuthDeg)}. Hold your thumb out at arm\'s length: they fit behind it.',
      SkyEventType.rocketLaunch =>
        'Look ${compassWord(e.peakAzimuthDeg)}, low on the horizon. A bright point climbs and arcs away; at twilight the plume glows like a jellyfish.',
      _ =>
        'Face ${compassWord(e.riseAzimuthDeg)}. It appears there and climbs ${elevationWord(e.peakElevationDeg)} before fading out toward the ${compassWord(e.setAzimuthDeg)}.',
    };

/// Three stat tiles for non-pass events.
List<(String, String)> statsFor(SkyEvent e) => switch (e.type) {
      SkyEventType.meteorShower => [
          ('Best', fmtTime(e.peak)),
          ('Per hour', '~${e.details['perHour']}'),
          ('Moon', '${(((e.details['moonIllumination'] as num?) ?? 0) * 100).round()}%'),
        ],
      SkyEventType.lunarEclipse => [
          ('Starts', fmtTime(e.start)),
          ('Deepest', fmtTime(e.peak)),
          ('Ends', fmtTime(e.end)),
        ],
      SkyEventType.planetPairing => [
          ('Apart', '${e.details['separation']}°'),
          ('Look', compassAbbrev(e.peakAzimuthDeg)),
          ('Height', '${e.peakElevationDeg.round()}°'),
        ],
      SkyEventType.rocketLaunch => [
          ('Liftoff', fmtTime(e.start)),
          ('Away', '${e.details['distanceKm']} km'),
          ('Look', compassAbbrev(e.peakAzimuthDeg)),
        ],
      _ => [
          ('From', fmtTime(e.start)),
          ('Until', fmtTime(e.end)),
          ('Kp', (e.details['kp'] as num?)?.toStringAsFixed(1) ?? '–'),
        ],
    };
