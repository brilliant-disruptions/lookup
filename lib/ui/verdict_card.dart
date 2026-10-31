import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/plan/tonight_verdict.dart';
import '../domain/sky/astro.dart' show PlanetInfo;
import '../domain/sky/direction.dart';
import '../domain/sky/tonight.dart';
import '../domain/sky/visibility.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'finder_screen.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'look_up_now_screen.dart';
import 'paywall_sheet.dart';
import 'sky/night_strip.dart';
import 'sky/sky_thing.dart';
import 'theme.dart';
import 'widgets/pass_arc.dart';

/// The top of Tonight: one answer to "should I go out?" ("Go out at
/// 10:17 PM.", "Stay in tonight."), why in a few chips, one button, and
/// tonight's clouds with its things marked on them. The decision is
/// [TonightVerdict]; this is its words and picture.
class VerdictCard extends ConsumerStatefulWidget {
  const VerdictCard({super.key, required this.home});
  final HomeData home;
  @override
  ConsumerState<VerdictCard> createState() => _VerdictCardState();
}

class _VerdictCardState extends ConsumerState<VerdictCard> {
  bool? _wasLive;

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final sky = ref.watch(tonightSkyProvider).value;
    final isPlus = ref.watch(settingsProvider).value?.isPlus ?? false;
    final outlook = sky?.outlook;
    final planets = [...?sky?.visiblePlanets]..sort((a, b) => a.magnitude.compareTo(b.magnitude));
    final planet = planets.firstOrNull;
    final tonightEnds = sky?.window?.end ?? now.toUtc().add(const Duration(hours: 18));
    final v = TonightVerdict.decide(
      events: widget.home.events,
      now: now,
      tonightEnds: tonightEnds,
      outlook: outlook,
      planetUp: planet != null,
    );
    final e = v.event;
    final live = v.kind == VerdictKind.live;

    // The go-now moment with the app open: a firm buzz and a chime, and in
    // the last two minutes the takeover.
    if (_wasLive == false && live) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      ref.read(liveActivityProvider).markLive();
    }
    _wasLive = live;
    if (e != null && (ModalRoute.of(context)?.isCurrent ?? false) && ref.read(homeTabProvider) == 0) {
      maybeOpenLookUpNow(context, e, now);
    }

    final tint = switch (v.kind) {
      VerdictKind.go || VerdictKind.live => e == null ? LookUpColors.good : eventStyle(e.type, details: e.details).color,
      VerdictKind.maybe => LookUpColors.warn,
      VerdictKind.clearNight => LookUpColors.gold,
      _ => LookUpColors.grey,
    };
    final kicker = switch (v.kind) {
      VerdictKind.live => 'Happening now',
      VerdictKind.go || VerdictKind.maybe => fmtDay(e!.start),
      _ => 'Tonight',
    };
    final headline = switch (v.kind) {
      VerdictKind.go => 'Go out at ${fmtTime(e!.start)}.',
      VerdictKind.live => 'Look up now.',
      VerdictKind.maybe => 'Worth a look at ${fmtTime(e!.start)}.',
      VerdictKind.stayIn => 'Stay in tonight.',
      VerdictKind.clearNight => 'A clear night for ${planet!.planet.label}.',
      VerdictKind.quiet => 'A quiet sky tonight.',
    };
    final line = switch (v.kind) {
      VerdictKind.go || VerdictKind.live => '${eventTitle(e!)}. ${_sentence(eventSubtitle(e))}',
      VerdictKind.maybe => '${eventTitle(e!)}. Some cloud is forecast, so look for the gaps. ${_sentence(eventSubtitle(e))}',
      VerdictKind.stayIn when e != null => 'Cloud is forecast over the ${eventTitle(e)} at ${fmtTime(e.start)}.',
      VerdictKind.stayIn => 'Cloud all night, and nothing bright passes over.',
      VerdictKind.clearNight => _planetLine(planet!),
      VerdictKind.quiet => 'Nothing bright passes over tonight.',
    };

    final chips = <Widget>[
      if (outlook != null && outlook.hasForecast) _outlookPill(outlook),
      if (e != null && e.cloudCoverPercent == null && v.kind != VerdictKind.stayIn)
        const Pill('No cloud forecast yet', icon: Icons.cloud_outlined),
      ?_moonPill(sky?.moon, sky?.window?.start, tonightEnds),
      if (planet != null && v.kind != VerdictKind.clearNight) Pill('${planet.planet.label} up', dot: true, color: LookUpColors.gold),
    ];

    final ahead = [
      for (final x in widget.home.events)
        if (x.type.pushes && x.start.isAfter(now.toUtc().subtract(const Duration(minutes: 10))) && x.start.isBefore(tonightEnds)) x,
    ];
    final marks = [
      for (final x in ahead.take(3))
        (at: x.start, color: eventStyle(x.type, details: x.details).color, label: '${_short(x)} ${fmtTime(x.start)}'),
      if (planet?.sighting case final s?) (at: s.best, color: LookUpColors.gold, label: planet!.planet.label),
    ];

    final until = e?.start.difference(now.toUtc());
    final isPass = e != null && (e.type == SkyEventType.iss || e.type == SkyEventType.tiangong || e.type == SkyEventType.starlinkTrain);
    final next = v.nextGood;

    return GlassCard(
      tint: tint,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(kicker, color: tint == LookUpColors.grey ? LookUpColors.grey : tint, live: live || v.kind == VerdictKind.go),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(headline, style: display(42, weight: FontWeight.w800, height: 1.04)),
          ),
          const SizedBox(height: 10),
          Text(line, style: const TextStyle(fontSize: 16, color: LookUpColors.grey, height: 1.4)),
          if (e?.details['landmarks'] case final String near when v.kind != VerdictKind.stayIn) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.auto_awesome_rounded, size: 16, color: LookUpColors.gold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Look for it $near', style: const TextStyle(fontSize: 15, color: LookUpColors.white)),
                ),
              ],
            ),
          ],
          if (chips.isNotEmpty) ...[const SizedBox(height: 14), Wrap(spacing: 8, runSpacing: 8, children: chips)],
          if (live && isPass) ...[const SizedBox(height: 16), LivePassArc(event: e, now: now)],
          const SizedBox(height: 18),
          if (e != null && v.kind != VerdictKind.stayIn)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => live || until! < const Duration(minutes: 30) ? openFinder(context, e) : showLookSheet(context, e),
                    icon: const Icon(Icons.explore_rounded),
                    label: Text(live ? 'Find it in the sky' : 'Where to look'),
                  ),
                ),
                if (!live) ...[
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('in', style: TextStyle(fontSize: 12, color: LookUpColors.grey)),
                      Text(fmtCountdown(until!), style: numeric(size: 20, weight: FontWeight.w700)),
                    ],
                  ),
                ],
              ],
            )
          else if (v.kind == VerdictKind.clearNight)
            FilledButton.icon(
              onPressed: () => ref.read(homeTabProvider.notifier).set(1),
              icon: const Icon(Icons.explore_rounded),
              label: Text('Find ${planet!.planet.label}'),
            ),
          if (next != null && (v.kind == VerdictKind.stayIn || v.kind == VerdictKind.quiet || v.kind == VerdictKind.clearNight)) ...[
            if (v.kind == VerdictKind.clearNight) const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => showLookSheet(context, next),
              child: Text(
                'Next good night: ${eventTitle(next)}, ${fmtDay(next.start)} ${fmtTime(next.start)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (outlook != null && outlook.hasForecast) ...[
            const SizedBox(height: 18),
            NightStrip(outlook: outlook, compact: true, marks: marks),
          ],
          if (e != null && e.isEstimate)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: LookUpColors.warn),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('Estimate: orbit data is a few days old', style: TextStyle(color: LookUpColors.warn, fontSize: 13)),
                  ),
                ],
              ),
            ),
          if (e != null && e.plusOnly && !isPlus && v.kind != VerdictKind.stayIn)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: GestureDetector(
                onTap: () => showPaywall(context, reason: e),
                behavior: HitTestBehavior.opaque,
                child: const Row(
                  children: [
                    Pill('LookUp+', color: LookUpColors.blue),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Get a tap 10 minutes before', style: TextStyle(fontSize: 14, color: LookUpColors.white)),
                    ),
                    Icon(Icons.arrow_forward_rounded, size: 18, color: LookUpColors.blue),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _sentence(String s) {
    if (s.isEmpty) return s;
    final t = '${s[0].toUpperCase()}${s.substring(1)}';
    return t.endsWith('.') ? t : '$t.';
  }

  static String _planetLine(PlanetTonight p) {
    final s = p.sighting;
    if (s == null) return '${p.planet.label} is up tonight.';
    return 'Nothing passes over, but ${p.planet.label} is easy to find: best at ${fmtTime(s.best)}, ${elevationWord(s.altDeg)} in the ${compassWord(s.azDeg)}.';
  }

  static String _short(SkyEvent e) => switch (e.type) {
    SkyEventType.iss => 'ISS',
    SkyEventType.tiangong => 'Tiangong',
    SkyEventType.starlinkTrain => 'Starlink',
    SkyEventType.auroraNow => 'Aurora',
    SkyEventType.meteorShower => 'Meteors',
    SkyEventType.rocketLaunch => 'Launch',
    SkyEventType.lunarEclipse => 'Eclipse',
    _ => eventTitle(e),
  };

  static Widget _outlookPill(NightOutlook o) {
    final (icon, color) = switch (o.shape) {
      'clear' || 'clouds-later' || 'clearing' => (Icons.nightlight_round, LookUpColors.good),
      'patchy' => (Icons.cloud_queue_rounded, LookUpColors.warn),
      _ => (Icons.cloud_rounded, LookUpColors.grey),
    };
    return Pill(outlookWords(o), icon: icon, color: color);
  }

  static Widget? _moonPill(MoonTonight? m, DateTime? tonightStarts, DateTime tonightEnds) {
    if (m == null) return null;
    final set = m.set;
    // Only a Moon that sets during the dark hours is tonight's news.
    final from = tonightStarts ?? DateTime.now().toUtc();
    if (set != null && set.isAfter(from) && set.isBefore(tonightEnds) && m.illumination > 0.15) {
      return Pill('Moon sets ${fmtTime(set)}', icon: Icons.dark_mode_rounded);
    }
    if (m.sighting?.verdict.yes ?? false) return Pill('Moon ${(m.illumination * 100).round()}%', icon: Icons.dark_mode_rounded);
    return null;
  }
}
