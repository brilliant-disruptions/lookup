import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../format.dart';
import '../kit/kit.dart';
import '../places_screen.dart';
import '../theme.dart';
import 'night_strip.dart';
import 'object_sheet.dart';
import 'sky_dome.dart';
import 'sky_panorama.dart';
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

  /// The round whole-sky map instead of the horizon view.
  bool _whole = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final place = (settings?.placeName?.isNotEmpty ?? false) ? settings!.placeName! : 'Near you';
    final sky = ref.watch(tonightSkyProvider);
    final catalog = ref.watch(skyCatalogProvider).value;
    final now = ref.watch(minuteProvider).value ?? DateTime.now();
    final top = MediaQuery.paddingOf(context).top + AppHeader.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppHeader(
        title: const Text('Sky'),
        place: place,
        onPlaceTap: () => openPlaces(context),
        actions: [
          CircleButton(
            tooltip: _whole ? 'Horizon view' : 'Whole sky',
            icon: _whole ? Icons.panorama_horizontal_rounded : Icons.blur_circular_rounded,
            onPressed: () => setState(() => _whole = !_whole),
          ),
        ],
      ),
      body: SkyBackdrop(
        stars: false,
        child: sky.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (t) {
          if (t == null || settings?.latitude == null || catalog == null) {
            return Padding(
              padding: EdgeInsets.fromLTRB(24, top + 24, 24, 24),
              child: const Text('Set a location to see your sky.', style: TextStyle(color: LookUpColors.grey)),
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
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, tabBarClearance(context)),
            children: [
              Rise(
                index: 0,
                child: _whole
                    ? SkyDome(
                        time: now,
                        lat: lat,
                        lon: lon,
                        catalog: catalog,
                        things: [moon, ...planets, ...shows],
                        selectedId: _selected,
                        onTap: open,
                      )
                    : SkyPanorama(
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
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Kicker('Live', color: LookUpColors.good, live: true),
                    Flexible(
                      child: Text('  ${fmtTime(now.toUtc())} · tap anything to open it',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: numeric(size: 13, color: LookUpColors.grey)),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                child: Text(
                  _whole
                      ? 'You\'re in the middle, looking straight up; the edge is the horizon all around you. '
                          'Hold it overhead with N to the north and it matches the real sky.'
                      : 'What you\'d see standing outside. The ground is at the bottom; higher up the screen is higher in the sky.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12.5, height: 1.4),
                ),
              ),
              if (t.outlook != null) ...[
                const SizedBox(height: 20),
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Kicker('Tonight\'s clouds'),
                    const SizedBox(height: 6),
                    NightStrip(outlook: t.outlook!),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              GroupedList(children: [_Row(moon, onTap: () => open(moon))]),
              const SizedBox(height: 24),
              SegmentedTabs(
                labels: const ['Planets', 'Constellations', 'Showpieces'],
                counts: [
                  planets.where((p) => p.seeable).length,
                  cons.where((c) => c.seeable).length,
                  shows.where((s) => s.seeable).length,
                ],
                index: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                  child: Text('Nothing well placed tonight.', style: TextStyle(color: LookUpColors.grey)),
                )
              else
                GroupedList(indent: 64, children: [for (final x in list) _Row(x, onTap: () => open(x))]),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                child: Text(
                  'Judged for a ${t.darkness.label.toLowerCase()} sky, tonight\'s forecast and the Moon. Change your sky in Settings.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          );
        },
        ),
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
    return ListRow(
      leading: thingGlyph(x),
      title: x.name,
      titleColor: x.seeable ? LookUpColors.white : LookUpColors.grey,
      subtitle: x.id == 'moon' ? x.kind : x.status,
      subtitleLines: 1,
      onTap: onTap,
      chevron: true,
      trailing: v != null && x.whyNot == null
          ? Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: verdictColor(v)))
          : null,
    );
  }
}
