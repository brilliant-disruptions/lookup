import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plus/free_plan.dart';
import 'paywall_sheet.dart';
import 'package:intl/intl.dart';

import '../domain/models/settings.dart';
import '../domain/models/sky_event.dart';
import '../domain/plan/night_plan.dart';
import '../domain/sky/direction.dart';
import '../domain/sky/visibility.dart';
import '../state/plan_state.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'sky/night_strip.dart';
import 'sky/object_sheet.dart';
import 'sky/sky_thing.dart';
import 'theme.dart';

/// Tonight and the next two nights are free; the rest of the fortnight is
/// LookUp+ ([FreePlan]).
Future<void> openPlan(BuildContext context, {int night = 0, int spot = 0}) {
  if (!FreePlan.canPlanNight(night, isPlus: hasPlus(context))) return showPaywall(context, feature: PlusFeature.planAhead);
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanScreen(initialNight: night, initialSpot: spot)));
}

/// Pick a night in the next fortnight and a place, and see what it's like:
/// when it's dark, the Moon, the clouds (once the forecast reaches), what's
/// worth finding and, for where they are, what passes over.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key, this.initialNight = 0, this.initialSpot = 0});
  final int initialNight;
  final int initialSpot;

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  late int _night = widget.initialNight.clamp(0, nightsAhead - 1);
  late int _spot = widget.initialSpot;

  static String nightLabel(int i) {
    if (i == 0) return 'Tonight';
    if (i == 1) return 'Tomorrow';
    return DateFormat('EEE d').format(DateTime.now().add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    final spots = s == null ? const <Spot>[] : planSpots(s);
    if (spots.isEmpty) {
      return const PageScaffold(title: 'Plan a night', children: [
        Text('Set a location to plan a night.', style: TextStyle(color: LookUpColors.grey)),
      ]);
    }
    final spot = spots[_spot.clamp(0, spots.length - 1)];
    final plan = ref.watch(nightPlanProvider(
        (lat: spot.lat, lon: spot.lon, night: _night, darkness: spot.darkness ?? s!.skyDarkness)));
    return PageScaffold(
      title: 'Plan a night',
      subtitle: spot.name,
      children: [
        if (spots.length > 1) ...[
          ChipRow(
            labels: [for (final p in spots) p.here ? '${p.name} (here)' : p.name],
            index: _spot,
            onSelect: (i) => setState(() => _spot = i),
          ),
          const SizedBox(height: 10),
        ],
        ChipRow(
          labels: [for (var i = 0; i < nightsAhead; i++) nightLabel(i)],
          index: _night,
          onSelect: (i) => FreePlan.canPlanNight(i, isPlus: s?.isPlus ?? false)
              ? setState(() => _night = i)
              : showPaywall(context, feature: PlusFeature.planAhead),
        ),
        if (!(s?.isPlus ?? false))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Tonight and the next two nights on free. LookUp+ plans the whole fortnight.',
                style: TextStyle(fontSize: 12.5, color: LookUpColors.greyDim)),
          ),
        const SizedBox(height: 16),
        ...plan.when(
          loading: () => const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
          error: (e, _) => [Text('$e', style: const TextStyle(color: LookUpColors.grey))],
          data: (p) => _body(context, p, spot, s!),
        ),
      ],
    );
  }

  List<Widget> _body(BuildContext context, NightPlan p, Spot spot, LookUpSettings settings) {
    final w = p.window;
    if (w == null) {
      return const [
        GlassCard(
          child: Text('It doesn\'t get properly dark this night here: the Sun stays too close below the horizon.',
              style: TextStyle(color: LookUpColors.grey, height: 1.45)),
        ),
      ];
    }
    final catalog = ref.watch(skyCatalogProvider).value;
    final live = _night == 0 && spot.here;
    final things = catalog == null ? const <String, SkyThing>{} : skyThingsOf(p, spot.lat, spot.lon, catalog);
    final favourites = settings.favourites;
    final worth = [
      ...p.visiblePlanets.map((x) => SkyId.planet(x.planet)),
      if (p.moon.sighting?.verdict.yes ?? false) SkyId.moon,
      ...p.showpieces.where((x) => x.sighting.verdict.yes).map((x) => x.showpiece.id),
      ...p.constellations.where((x) => x.sighting.verdict.yes).take(4).map((x) => SkyId.constellation(x.constellation.id)),
    ].where((id) => !favourites.contains(id)).toList();
    final passes = !spot.here
        ? const <SkyEvent>[]
        : (ref.watch(homeProvider).value?.events ?? const <SkyEvent>[])
            .where((e) => !e.start.isBefore(w.start.subtract(const Duration(hours: 1))) && e.start.isBefore(w.end))
            .toList();

    Widget row(String id) {
      final sight = p.sightings[id];
      final thing = things[id];
      return ListRow(
        leading: glyphForId(id, dim: !(sight?.verdict.yes ?? false)),
        title: catalog == null ? id : skyName(id, catalog),
        subtitle: sight == null
            ? 'Not up this night'
            : sight.verdict.yes
                ? 'Best ${fmtTime(sight.best)}, ${compassWord(sight.azDeg)}'
                : sight.verdict.words,
        subtitleLines: 1,
        trailing: sight == null ? null : Pill(_verdictShort(sight.verdict), dot: true, color: verdictColor(sight.verdict)),
        chevron: live && thing != null,
        onTap: live && thing != null ? () => showObjectSheet(context, thing) : null,
      );
    }

    return [
      Rise(index: 0, child: _NightCard(plan: p, night: _night)),
      if (favourites.isNotEmpty) ...[
        const SectionHeader('Your favourites'),
        GroupedList(indent: 64, children: [for (final id in favourites) row(id)]),
      ],
      if (passes.isNotEmpty) ...[
        const SectionHeader('Passing over'),
        GroupedList(indent: 64, children: [
          for (final e in passes)
            ListRow(
              leading: EventGlyph.of(e),
              title: eventTitle(e),
              subtitle: '${fmtTime(e.start)} · ${eventSubtitle(e)}',
              subtitleLines: 1,
              onTap: () => showLookSheet(context, e),
            ),
        ]),
      ],
      if (worth.isNotEmpty) ...[
        const SectionHeader('Worth finding'),
        GroupedList(indent: 64, children: [for (final id in worth) row(id)]),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        child: Text(
          [
            'Judged for a ${p.darkness.label.toLowerCase()} sky${spot.darkness == null ? '' : ' (set for ${spot.name})'}, the Moon '
                'and ${p.outlook?.hasForecast ?? false ? 'the forecast' : 'clear skies (the forecast doesn\'t reach this night yet)'}.',
            if (!spot.here) 'Passes overhead are worked out for where you are, so they aren\'t listed here.',
          ].join(' '),
          textAlign: TextAlign.center,
          style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12.5, height: 1.4),
        ),
      ),
    ];
  }

  static String _verdictShort(Seeability v) => switch (v) {
        Seeability.great => 'Easy',
        Seeability.good => 'Good',
        Seeability.low => 'Low',
        Seeability.patchy => 'Gaps',
        Seeability.cloudy => 'Cloud',
        Seeability.foggy => 'Haze',
        Seeability.rain => 'Rain',
        Seeability.moonlit => 'Moonlit',
        Seeability.twilight => 'Too light',
        Seeability.tooFaint => 'Too faint',
        Seeability.belowHorizon => 'Not up',
      };
}

/// The night at a glance: when it's dark, the clouds, the Moon.
class _NightCard extends StatelessWidget {
  const _NightCard({required this.plan, required this.night});
  final NightPlan plan;
  final int night;

  @override
  Widget build(BuildContext context) {
    final w = plan.window!;
    final o = plan.outlook;
    final m = plan.moon;
    final pct = (m.illumination * 100).round();
    final moonTimes = [if (m.rise != null) 'rises ${fmtTime(m.rise!)}', if (m.set != null) 'sets ${fmtTime(m.set!)}'].join(', ');
    final moonNote = m.illumination >= 0.6
        ? 'Bright Moon: faint galaxies and the Milky Way wash out.'
        : m.illumination <= 0.25
            ? 'Dark Moon: a good night for faint things.'
            : null;
    return GlassCard(
      tint: LookUpColors.violet,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Kicker(night == 0 ? 'Tonight' : night == 1 ? 'Tomorrow night' : DateFormat('EEEE, MMM d').format(w.start.toLocal()),
            color: LookUpColors.violet),
        const SizedBox(height: 6),
        Text(o != null && o.hasForecast ? outlookWords(o) : 'Forecast not out yet', style: display(24, weight: FontWeight.w700)),
        if (o != null && o.hasForecast) ...[
          const SizedBox(height: 14),
          NightStrip(outlook: o, compact: true),
        ],
        const SizedBox(height: 16),
        _Fact(Icons.dark_mode_rounded, 'Dark ${fmtTime(w.start)} – ${fmtTime(w.end)}'),
        const SizedBox(height: 8),
        _Fact(Icons.nightlight_round, '${m.phase.label}, $pct% lit${moonTimes.isEmpty ? '' : ' · $moonTimes'}'),
        if (moonNote != null) ...[
          const SizedBox(height: 8),
          Text(moonNote, style: const TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.4)),
        ],
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: LookUpColors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: numeric(size: 14.5, color: LookUpColors.white))),
      ]);
}
