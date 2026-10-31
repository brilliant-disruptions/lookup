import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plus/free_plan.dart';
import 'paywall_sheet.dart';

import '../domain/models/settings.dart';
import '../domain/plan/where_to_go.dart';
import '../domain/sky/direction.dart';
import '../domain/sky/skyglow.dart';
import '../domain/sky/tonight.dart';
import '../domain/sky/visibility.dart';
import '../state/plan_state.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart' show openDirections;
import 'places_screen.dart';
import 'plan_screen.dart';
import 'sky/night_strip.dart';
import 'sky/sky_thing.dart';
import 'theme.dart';

/// LookUp+: free users see what it does on the paywall instead.
Future<void> openWhereToGo(BuildContext context) {
  if (!FreePlan.canUse(PlusFeature.whereToGo, isPlus: hasPlus(context))) return showPaywall(context, feature: PlusFeature.whereToGo);
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WhereToGoScreen()));
}

/// "240 km east", or "40 km northeast"; null for here.
String? howFar(PlaceNight p) {
  final km = p.distanceKm, b = p.bearingDeg;
  if (km == null || b == null) return null;
  return '${roundKm(km)} km ${compassWord(b)}';
}

/// Distances to the nearest sensible step: never falsely precise.
int roundKm(double km) => km < 20 ? km.round() : km < 100 ? (km / 5).round() * 5 : (km / 10).round() * 10;

/// "30 km west".
String spotName(DarkSpot s) => '${roundKm(s.distanceKm)} km ${compassWord(s.bearingDeg)}';

bool _isDark(DarkSpot s) => darknessForSqm(s.sqm) == SkyDarkness.dark;

String _clearSpell(PlaceNight p) {
  final o = p.outlook!;
  if (o.bestStart == null) return _lower(outlookWords(o));
  return o.shape == 'clear' ? 'clear all night' : 'clear ${fmtTime(o.bestStart!)}–${fmtTime(o.bestEnd!)}';
}

/// The recommendation in words: a headline and one supporting line.
({String headline, String detail}) whereToGoWords(WhereToGo r) {
  final best = r.best;
  switch (r.kind) {
    case WhereToGoKind.noForecast:
      return (headline: 'No forecast yet', detail: 'We\'ll compare your places once the clouds are in.');
    case WhereToGoKind.cloudyEverywhere:
      return (headline: 'Cloudy at all your places', detail: 'Not a night for a drive. Try another night in Plan a night.');
    case WhereToGoKind.stayPut:
      final others = r.ranked.where((p) => !p.here && p.hasForecast).toList();
      final why = others.isEmpty
          ? ''
          : others.every((p) => p.clearHours == 0)
              ? ' Your other places are cloudy.'
              : ' Nowhere you\'ve saved is clearly better.';
      return (headline: 'Stay put tonight', detail: '${best!.name} is ${_clearSpell(best)}.$why');
    case WhereToGoKind.go:
      final far = howFar(best!);
      final here = r.ranked.where((p) => p.here).firstOrNull;
      final sky = best.darkness == SkyDarkness.dark ? ' under a dark sky' : '';
      final vsHere = here == null || !here.hasForecast ? '' : ' Here: ${_lower(outlookWords(here.outlook!))}.';
      return (
        headline: 'Head to ${best.name}',
        detail: '${_cap(_clearSpell(best))}$sky${far == null ? '' : ', $far'}.$vsHere',
      );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "Clear until 2:00 AM" → "clear until 2:00 AM" (times keep their case).
String _lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Here and every saved place, side by side on tonight's clouds and how
/// dark each sky is, best first.
class WhereToGoScreen extends ConsumerWidget {
  const WhereToGoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(whereToGoProvider);
    return PageScaffold(
      title: 'Where to go tonight',
      subtitle: 'Your places, clearest first',
      children: w.when(
        loading: () => const [Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))],
        error: (e, _) => [Text('$e', style: const TextStyle(color: LookUpColors.grey))],
        data: (w) => [
          ...w == null ? _empty(context) : _body(context, w.result, w.spots),
          const _DarkSpots(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
            child: Text(
              [
                if (w != null) 'Ranked on tonight\'s longest clear spell, counting a darker sky for more. '
                    'Set how dark each place is in Places. Tap a place to plan the night there.',
                'Darker skies are estimated from NASA\'s Black Marble night-lights map. It knows where the light is, '
                    'not where the roads or public land are: check you can get there and stay after dark.',
              ].join('\n\n'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _empty(BuildContext context) => [
        GlassCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Compare your places', style: display(22, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Save a place or two you could drive to (a cabin, a park, one of the darker skies below) and we\'ll compare '
              'tonight\'s clouds there with here, and tell you when it\'s worth the trip.',
              style: TextStyle(color: LookUpColors.grey, height: 1.45),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => openPlaces(context),
              icon: const Icon(Icons.add_location_alt_rounded, size: 18),
              label: const Text('Add a place'),
            ),
          ]),
        ),
      ];

  List<Widget> _body(BuildContext context, WhereToGo r, List<Spot> spots) {
    final words = whereToGoWords(r);
    int spotOf(PlaceNight p) => spots.indexWhere((s) => s.here == p.here && s.name == p.name).clamp(0, spots.length - 1);
    return [
      Rise(
        index: 0,
        child: GlassCard(
          tint: r.kind == WhereToGoKind.go ? LookUpColors.violet : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(words.headline, style: display(24, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(words.detail, style: const TextStyle(color: LookUpColors.grey, fontSize: 14.5, height: 1.4)),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      for (final (i, p) in r.ranked.indexed)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Rise(index: i + 1, child: _PlaceCard(p, best: identical(p, r.best), onTap: () => openPlan(context, spot: spotOf(p)))),
        ),
    ];
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard(this.p, {required this.best, required this.onTap});
  final PlaceNight p;
  final bool best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = p.outlook;
    final far = p.here ? 'You\'re here' : howFar(p);
    return GlassCard(
      onTap: onTap,
      border: best ? LookUpColors.violet.withValues(alpha: 0.6) : LookUpColors.line,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: display(18, weight: FontWeight.w600)),
              if (far != null) ...[
                const SizedBox(height: 2),
                Text(far, style: const TextStyle(color: LookUpColors.greyDim, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          if (best) ...[const Pill('Best', dot: true, color: LookUpColors.violet), const SizedBox(width: 6)],
          Pill(p.darkness.label, color: p.darkness == SkyDarkness.dark ? LookUpColors.good : LookUpColors.grey),
        ]),
        const SizedBox(height: 12),
        Text(
          o == null ? 'Doesn\'t get properly dark tonight' : o.hasForecast ? outlookWords(o) : 'No forecast for here yet',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        if (o != null && o.hasForecast) ...[
          const SizedBox(height: 10),
          NightStrip(outlook: o, compact: true),
        ],
      ]),
    );
  }
}

/// Darker skies within reach of where they are, from the night-lights map.
class _DarkSpots extends ConsumerWidget {
  const _DarkSpots();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(darkSpotsProvider).value;
    if (d == null) return const SizedBox.shrink();
    final here = d.here;
    final hereWords = here == null ? null : 'Your sky here: about ${darknessForSqm(here).label.toLowerCase()}.';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader('Darker skies nearby'),
      if (d.spots.isEmpty)
        GlassCard(
          child: Text(
            here != null && darknessForSqm(here) == SkyDarkness.dark
                ? 'Your sky is already about as dark as it gets around here.'
                : 'Nowhere within 150 km is clearly darker.',
            style: const TextStyle(color: LookUpColors.grey, height: 1.4),
          ),
        )
      else ...[
        if (hereWords != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(hereWords, style: const TextStyle(color: LookUpColors.grey, fontSize: 14)),
          ),
        for (final (i, s) in d.spots.indexed)
          Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 12), child: _SpotCard(s)),
      ],
    ]);
  }
}

const _compact = ButtonStyle(
  visualDensity: VisualDensity.compact,
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
);

class _SpotCard extends ConsumerWidget {
  const _SpotCard(this.spot);
  final DarkSpot spot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = spot;
    final dark = _isDark(s);
    final weather = ref.watch(placeForecastProvider((lat: s.lat, lon: s.lon)));
    final w = tonightWindow(DateTime.now().toUtc(), s.lat, s.lon);
    final outlook = w == null || weather.isLoading ? null : NightOutlook.from(start: w.start, end: w.end, weather: weather.value);
    final settings = ref.watch(settingsProvider).value;
    final saved = settings?.places.any((p) => p.sameSpot(s.lat, s.lon)) ?? false;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(spotName(s), style: display(18, weight: FontWeight.w600))),
          Pill(dark ? 'Dark sky' : 'Darker', color: dark ? LookUpColors.good : LookUpColors.grey),
        ]),
        const SizedBox(height: 4),
        Text(dark ? 'The Milky Way shows' : 'More stars than here', style: const TextStyle(color: LookUpColors.greyDim, fontSize: 13)),
        const SizedBox(height: 12),
        Text(
          outlook == null ? (w == null ? 'Doesn\'t get properly dark tonight' : 'Checking tonight\'s clouds…')
              : outlook.hasForecast ? outlookWords(outlook) : 'No forecast for here yet',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        if (outlook != null && outlook.hasForecast) ...[
          const SizedBox(height: 10),
          NightStrip(outlook: outlook, compact: true),
        ],
        const SizedBox(height: 6),
        Row(children: [
          TextButton.icon(
            style: _compact,
            onPressed: () => openDirections(s.lat, s.lon),
            icon: const Icon(Icons.directions_rounded, size: 18),
            label: const Text('Directions'),
          ),
          const SizedBox(width: 4),
          if (saved)
            const TextButton(style: _compact, onPressed: null, child: Text('Saved'))
          else
            TextButton.icon(
              style: _compact,
              onPressed: () => ref.read(settingsProvider.notifier).edit((x) => x.copyWith(places: [
                    ...x.places,
                    SavedPlace(
                        name: '${dark ? 'Dark sky' : 'Darker sky'}, ${spotName(s)}',
                        latitude: s.lat,
                        longitude: s.lon,
                        skyDarkness: darknessForSqm(s.sqm)),
                  ])),
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Save'),
            ),
        ]),
      ]),
    );
  }
}
