import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/plan/night_plan.dart';
import '../../domain/sky/calendar.dart';
import '../../domain/sky/catalog.dart';
import '../../domain/sky/history.dart';
import '../../domain/sky/visibility.dart';
import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../format.dart';
import '../look_sheet.dart';
import '../kit/kit.dart';
import '../places_screen.dart';
import '../theme.dart';
import 'night_strip.dart';
import 'object_sheet.dart';
import 'sky_camera_screen.dart';
import 'sky_dome.dart';
import 'sky_panorama.dart';
import 'sky_thing.dart';
import 'sky_track.dart';
import 'time_travel_sheet.dart';

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

  /// Where the map is in time: a fixed moment once you jump (day steps, a
  /// picked date, a famous night), otherwise now; plus up to 12 hours either
  /// way on the slider. No anchor and no slide = live.
  DateTime? _anchor;
  double _minutes = 0;

  /// A famous night being visited: the map stands where it happened.
  FamousNight? _night;

  /// What the camera view would show, from the last build.
  ({List<SkyThing> things, List<SkyTrack> tracks, DateTime? time, double lat, double lon})? _camera;

  void _openCamera() {
    final c = _camera;
    if (c == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a location to see your sky.')));
      return;
    }
    openSkyCamera(context, things: c.things, tracks: c.tracks, time: c.time, lat: c.lat, lon: c.lon);
  }

  void _backToNow() => setState(() {
        _anchor = null;
        _minutes = 0;
        _night = null;
        _selected = null;
      });

  /// A day either way, staying inside 3000 BC – 3000 AD.
  void _step(DateTime now, int days) {
    final to = (_anchor ?? now.toUtc()).add(Duration(days: days));
    if (to.isBefore(skyTimeFirst) || to.isAfter(skyTimeLast)) return;
    setState(() => _anchor = to);
  }

  Future<void> _travel(DateTime at, double lon) async {
    final go = await showTimeTravelSheet(context, at: at, lonDeg: lon);
    if (go == null || !mounted) return;
    setState(() {
      _night = go.night;
      _minutes = 0;
      _anchor = go.utc;
      _selected = _focusId(go.night);
    });
  }

  /// The map id of what a famous night is about ("planet:jupiter", "moon",
  /// or "star:Thuban" for a star).
  static String? _focusId(FamousNight? n) {
    final f = n?.focus;
    if (f == null) return null;
    return f.contains(':') || f == SkyId.moon ? f : 'star:$f';
  }

  /// Tracks are worked out once per pass and place, not on every tick.
  final _tracks = <String, SkyTrack>{};

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final place = (settings?.placeName?.isNotEmpty ?? false) ? settings!.placeName! : 'Near you';
    final sky = ref.watch(tonightSkyProvider);
    final catalog = ref.watch(skyCatalogProvider).value;
    final now = ref.watch(minuteProvider).value ?? DateTime.now();
    final at = (_anchor ?? now.toUtc()).add(Duration(minutes: _minutes.round()));
    final offset = at.difference(now.toUtc());
    final later = _anchor != null || _minutes != 0;
    final top = MediaQuery.paddingOf(context).top + AppHeader.height;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppHeader(
        title: const Text('Sky'),
        place: _night?.place ?? place,
        onPlaceTap: () => openPlaces(context),
        actions: [
          CircleButton(
            tooltip: 'Sky through your camera',
            icon: Icons.photo_camera_rounded,
            onPressed: _openCamera,
          ),
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
          final night = _night;
          final lat = night?.lat ?? settings!.latitude!, lon = night?.lon ?? settings!.longitude!;
          final planets = [for (final p in t.planets) SkyThing.planet(p, lat, lon)];
          final moon = SkyThing.moon(t.moon, lat, lon);
          final cons = [for (final c in t.constellations) SkyThing.constellation(c, lat, lon, catalog)];
          final shows = [for (final s in t.showpieces) SkyThing.showpiece(s, lat, lon)];
          // A famous night about a star (Thuban at Giza) puts that star on the map.
          final focusStar = night?.focus == null ? null : catalog.stars.where((s) => s.name == night!.focus).firstOrNull;
          final stars = [if (focusStar != null) _starThing(focusStar, lat, lon)];
          // Ringed and named on the map while its sheet is open, then let go.
          Future<void> open(SkyThing x) async {
            setState(() => _selected = x.id);
            await showObjectSheet(context, x, at: later ? at : null, place: night == null ? null : (lat, lon));
            if (mounted && _selected == x.id) setState(() => _selected = _focusId(_night));
          }

          final events = ref.watch(homeProvider).value?.events ?? const <SkyEvent>[];
          // Passes are for here and near now; history has none.
          final tracks = [
            if (night == null && offset.inHours.abs() < 24)
              for (final e in upcomingPasses(events, at))
              _tracks.putIfAbsent('${e.id}@$lat,$lon', () => passTrack(e, lat, lon)),
          ];
          // While one is overhead, move its dot every second.
          final passing = !later && tracks.any((t) => t.liveAt(DateTime.now()));
          final trackTime = passing ? (ref.watch(clockProvider).value ?? DateTime.now()) : at;
          final skyThen = later
              ? skyWords(SkyConditions.at(at.toUtc(), lat, lon, weather: night == null ? ref.watch(weatherProvider).value : null))
              : null;
          void openPass(SkyEvent e) => showLookSheet(context, e);
          final mapped = [moon, ...planets, ...shows, ...stars];
          _camera = (things: mapped, tracks: tracks, time: later ? at : null, lat: lat, lon: lon);

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
                        things: mapped,
                        selectedId: _selected,
                        onTap: open,
                        tracks: tracks,
                        trackTime: trackTime,
                        onTrackTap: openPass,
                      )
                    : SkyPanorama(
                        // A famous night turns you to face what it's about.
                        key: ValueKey(night?.id),
                        initialFacing: mapped.where((x) => x.id == _focusId(night)).firstOrNull?.position(at).azimuthDeg,
                        time: at,
                        lat: lat,
                        lon: lon,
                        catalog: catalog,
                        things: mapped,
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
                        ? Kicker(offset.isNegative ? 'Earlier' : 'Later', color: LookUpColors.blue)
                        : const Kicker('Live', color: LookUpColors.good, live: true),
                    Flexible(
                      child: Text(
                          later
                              ? '  ${fmtSkyMoment(at.toUtc(), lon)}${offset.inMinutes.abs() < 24 * 60 ? ' · ${_offsetWord(offset)}' : ''}'
                              : '  ${fmtTime(now.toUtc())} · tap anything to open it',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: numeric(size: 13, color: LookUpColors.grey)),
                    ),
                  ]),
                ),
              ),
              if (night != null && at.difference(night.utc).inHours.abs() < 13) ...[
                const SizedBox(height: 10),
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Kicker('${night.place} · ${fmtSkyMoment(night.utc, night.lon)}', color: LookUpColors.blue),
                    const SizedBox(height: 6),
                    Text(night.title, style: display(20, weight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(night.blurb, style: const TextStyle(color: LookUpColors.grey, height: 1.45)),
                  ]),
                ),
              ],
              _TimeTravel(
                minutes: _minutes,
                onMinutes: (m) => setState(() => _minutes = m),
                onStep: (d) => _step(now, d),
                live: !later && night == null,
                onNow: _backToNow,
                onPickDate: () => _travel(at, lon),
                skyThen: skyThen,
                at: at,
                lon: lon,
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

/// "in 45 min", "in 7 h 30 min", "3 h ago".
String _offsetWord(Duration d) {
  final total = d.inMinutes.abs(), h = total ~/ 60, m = total % 60;
  final span = h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m min');
  return d.isNegative ? '$span ago' : 'in $span';
}

/// A star on the map as a [SkyThing] (for famous nights about one).
SkyThing _starThing(Star star, double lat, double lon) => SkyThing(
      id: 'star:${star.name}',
      name: star.name!,
      kind: 'Star',
      position: (t) => star.horizontal(t, lat, lon),
      mag: star.mag,
      finder: {'ra': star.raDeg, 'dec': star.decDeg},
    );

/// Move the map through time: the slider for tonight ("cloudy now, but
/// clear at 3 AM: will Saturn be up then?"), a day at a time either way, or
/// any night from 3000 BC to 3000 AD, famous ones included. Says the
/// forecast sky when there is one.
class _TimeTravel extends StatelessWidget {
  const _TimeTravel({
    required this.minutes,
    required this.onMinutes,
    required this.onStep,
    required this.live,
    required this.onNow,
    required this.onPickDate,
    required this.at,
    required this.lon,
    this.skyThen,
  });
  final double minutes;
  final ValueChanged<double> onMinutes;
  final ValueChanged<int> onStep;
  final bool live;
  final VoidCallback onNow;
  final VoidCallback onPickDate;
  final DateTime at;
  final double lon;
  final String? skyThen;

  static const span = 720.0; // 12 h either way

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    final when = fmtSkyMoment(at.toUtc(), lon);
    // Measured against JPL: the Moon drifts past half a degree before here.
    final rough = at.toUtc().isBefore(_roughBefore);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Slider(
          value: minutes,
          min: -span,
          max: span,
          divisions: (2 * span / 15).round(),
          label: live ? 'Now' : when,
          semanticFormatterCallback: (_) => live ? 'Now' : 'At $when',
          onChanged: onMinutes,
        ),
        // Wraps to two lines on narrow phones rather than overflowing.
        Wrap(alignment: WrapAlignment.center, children: [
          TextButton.icon(
            onPressed: () => onStep(-1),
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('Day', style: small),
          ),
          TextButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.history_edu_rounded, size: 18),
            label: const Text('Any night', style: small),
          ),
          TextButton(
            onPressed: () => onStep(1),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Day', style: small),
              SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18),
            ]),
          ),
          TextButton(onPressed: live ? null : onNow, child: const Text('Now', style: small)),
        ]),
        Text(
          [
            skyThen == null
                ? 'Slide through tonight, or go to any night from 3000 BC to 3000 AD.'
                : 'Sky at $when: ${skyThen!.toLowerCase()}. Tap anything to see if you could spot it then.',
            if (rough) 'This long ago the Moon can be a degree or two out; the stars and planets hold.',
          ].join(' '),
          textAlign: TextAlign.center,
          style: TextStyle(color: skyThen == null ? LookUpColors.greyDim : LookUpColors.grey, fontSize: 12.5, height: 1.4),
        ),
      ]),
    );
  }
}

final _roughBefore = utcFromJulianDay(julianDay(-999, 1, 1));

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
