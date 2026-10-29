import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/sky/visibility.dart';
import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../format.dart';
import '../look_sheet.dart';
import '../night_vision_button.dart';
import '../kit/kit.dart';
import '../places_screen.dart';
import '../theme.dart';
import 'night_strip.dart';
import 'object_sheet.dart';
import 'sky_dome.dart';
import 'sky_panorama.dart';
import 'sky_thing.dart';
import 'sky_track.dart';

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

  /// How far ahead the map is looking, in minutes (0 = live).
  double _ahead = 0;

  /// Tracks are worked out once per pass and place, not on every tick.
  final _tracks = <String, SkyTrack>{};

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final place = (settings?.placeName?.isNotEmpty ?? false) ? settings!.placeName! : 'Near you';
    final sky = ref.watch(tonightSkyProvider);
    final catalog = ref.watch(skyCatalogProvider).value;
    final now = ref.watch(minuteProvider).value ?? DateTime.now();
    final later = _ahead > 0;
    final at = now.add(Duration(minutes: _ahead.round()));
    final top = MediaQuery.paddingOf(context).top + AppHeader.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppHeader(
        title: const Text('Sky'),
        place: place,
        onPlaceTap: () => openPlaces(context),
        actions: [
          const NightVisionButton(),
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
          // Ringed and named on the map while its sheet is open, then let go.
          Future<void> open(SkyThing x) async {
            setState(() => _selected = x.id);
            await showObjectSheet(context, x, at: later ? at : null);
            if (mounted && _selected == x.id) setState(() => _selected = null);
          }

          final events = ref.watch(homeProvider).value?.events ?? const <SkyEvent>[];
          final tracks = [
            for (final e in upcomingPasses(events, at))
              _tracks.putIfAbsent('${e.id}@$lat,$lon', () => passTrack(e, lat, lon)),
          ];
          // While one is overhead, move its dot every second.
          final passing = !later && tracks.any((t) => t.liveAt(DateTime.now()));
          final trackTime = passing ? (ref.watch(clockProvider).value ?? DateTime.now()) : at;
          final skyThen = later
              ? skyWords(SkyConditions.at(at.toUtc(), lat, lon, weather: ref.watch(weatherProvider).value))
              : null;
          void openPass(SkyEvent e) => showLookSheet(context, e);

          final list = switch (_tab) { 0 => planets, 1 => cons, _ => shows };
          return ListView(
            padding: EdgeInsets.fromLTRB(16, top + 8, 16, tabBarClearance(context)),
            children: [
              Rise(
                index: 0,
                child: _whole
                    ? SkyDome(
                        time: at,
                        lat: lat,
                        lon: lon,
                        catalog: catalog,
                        things: [moon, ...planets, ...shows],
                        selectedId: _selected,
                        onTap: open,
                        tracks: tracks,
                        trackTime: trackTime,
                        onTrackTap: openPass,
                      )
                    : SkyPanorama(
                        time: at,
                        lat: lat,
                        lon: lon,
                        catalog: catalog,
                        things: [moon, ...planets, ...shows],
                        selectedId: _selected,
                        onTap: open,
                        tracks: tracks,
                        trackTime: trackTime,
                        onTrackTap: openPass,
                      ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    later
                        ? const Kicker('Later', color: LookUpColors.blue)
                        : const Kicker('Live', color: LookUpColors.good, live: true),
                    Flexible(
                      child: Text(
                          later
                              ? '  ${fmtTime(at.toUtc())} · in ${_hoursWord(_ahead.round())}'
                              : '  ${fmtTime(now.toUtc())} · tap anything to open it',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: numeric(size: 13, color: LookUpColors.grey)),
                    ),
                  ]),
                ),
              ),
              _LookAhead(
                minutes: _ahead,
                onChanged: (m) => setState(() => _ahead = m),
                skyThen: skyThen,
                at: at,
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
                  'Judged for a ${t.darkness.label.toLowerCase()} sky, tonight\'s forecast and the Moon. Change your sky in Settings. '
                  'Tap the heart on anything to follow it on Tonight.',
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

/// "45 min", "3 h", "7 h 30 min".
String _hoursWord(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Slide the map up to ten hours ahead ("cloudy now, but clear at 3 AM:
/// will Saturn be up then?"), with the forecast sky for that moment.
class _LookAhead extends StatelessWidget {
  const _LookAhead({required this.minutes, required this.onChanged, required this.at, this.skyThen});
  final double minutes;
  final ValueChanged<double> onChanged;
  final DateTime at;
  final String? skyThen;

  static const max = 600.0;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Slider(
                value: minutes,
                max: max,
                divisions: (max / 15).round(),
                label: minutes == 0 ? 'Now' : fmtTime(at.toUtc()),
                semanticFormatterCallback: (_) => minutes == 0 ? 'Now' : 'At ${fmtTime(at.toUtc())}',
                onChanged: onChanged,
              ),
            ),
            TextButton(onPressed: minutes == 0 ? null : () => onChanged(0), child: const Text('Now')),
          ]),
          Text(
            skyThen == null
                ? 'Slide to see the sky up to 10 hours from now.'
                : 'Sky at ${fmtTime(at.toUtc())}: ${skyThen!.toLowerCase()}. Tap anything to see if you could spot it then.',
            textAlign: TextAlign.center,
            style: TextStyle(color: skyThen == null ? LookUpColors.greyDim : LookUpColors.grey, fontSize: 12.5, height: 1.4),
          ),
        ]),
      );
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
