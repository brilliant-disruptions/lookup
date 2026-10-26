import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../fancy/ornament_rule.dart';
import '../fancy/rise.dart';
import '../fancy/woven.dart';
import '../format.dart';
import '../places_screen.dart';
import '../theme.dart';
import 'night_strip.dart';
import 'object_sheet.dart';
import 'sky_dome.dart';
import 'sky_thing.dart';

/// Everything above you: a live map, tonight's clouds, and what's worth
/// finding (planets, constellations, showpieces), each with a verdict.
class SkyScreen extends ConsumerStatefulWidget {
  const SkyScreen({super.key});
  @override
  ConsumerState<SkyScreen> createState() => _SkyScreenState();
}

class _SkyScreenState extends ConsumerState<SkyScreen> {
  int _tab = 0;
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final place = (settings?.placeName?.isNotEmpty ?? false) ? settings!.placeName! : 'Near you';
    final sky = ref.watch(tonightSkyProvider);
    final catalog = ref.watch(skyCatalogProvider).value;
    final now = ref.watch(minuteProvider).value ?? DateTime.now();
    return Scaffold(
      appBar: WovenHeader(title: const Text('Sky'), subtitle: place, onSubtitleTap: () => openPlaces(context)),
      body: sky.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (t) {
          if (t == null || settings?.latitude == null || catalog == null) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Set a location to see your sky.', style: TextStyle(color: LookUpColors.grey)),
            );
          }
          final lat = settings!.latitude!, lon = settings.longitude!;
          final planets = [for (final p in t.planets) SkyThing.planet(p, lat, lon)];
          final moon = SkyThing.moon(t.moon, lat, lon);
          final cons = [for (final c in t.constellations) SkyThing.constellation(c, lat, lon, catalog)];
          final shows = [for (final s in t.showpieces) SkyThing.showpiece(s, lat, lon)];
          void open(SkyThing x) {
            setState(() => _selected = x.id);
            showObjectSheet(context, x);
          }

          final list = switch (_tab) { 0 => planets, 1 => cons, _ => shows };
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              Rise(
                index: 0,
                child: SkyDome(
                  time: now,
                  lat: lat,
                  lon: lon,
                  catalog: catalog,
                  things: [moon, ...planets, ...shows],
                  selectedId: _selected,
                  onTap: open,
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Now, ${fmtTime(now.toUtc())} · tap anything',
                      style: const TextStyle(color: LookUpColors.greyDim, fontSize: 11.5)),
                ),
              ),
              if (t.outlook != null) ...[
                const Padding(padding: EdgeInsets.fromLTRB(0, 22, 0, 12), child: OrnamentRule(label: 'Tonight\'s clouds')),
                NightStrip(outlook: t.outlook!),
              ],
              const SizedBox(height: 18),
              WovenRows(padding: EdgeInsets.zero, children: [_Row(moon, onTap: () => open(moon))]),
              const SizedBox(height: 14),
              WovenTabs(
                labels: const ['Planets', 'Constellations', 'Showpieces'],
                counts: [
                  planets.where((p) => p.seeable).length,
                  cons.where((c) => c.seeable).length,
                  shows.where((s) => s.seeable).length,
                ],
                index: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 4),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Nothing well placed tonight.', style: TextStyle(color: LookUpColors.grey)),
                )
              else
                WovenRows(padding: EdgeInsets.zero, children: [for (final x in list) _Row(x, onTap: () => open(x))]),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Judged for a ${t.darkness.label.toLowerCase()} sky, tonight\'s forecast and the Moon. Change your sky in Settings.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LookUpColors.greyDim, fontSize: 11.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.x, {required this.onTap});
  final SkyThing x;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = x.sighting?.verdict;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x.name, style: displaySerif(context, size: 21, weight: FontWeight.w500,
                  color: x.seeable ? LookUpColors.white : LookUpColors.grey)),
              const SizedBox(height: 2),
              Text(x.id == 'moon' ? x.kind : x.status,
                  style: const TextStyle(color: LookUpColors.grey, fontSize: 12.5)),
            ]),
          ),
          if (v != null && x.whyNot == null)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(shape: BoxShape.circle, color: verdictColor(v)),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 18, color: LookUpColors.greyDim),
        ]),
      ),
    );
  }
}

