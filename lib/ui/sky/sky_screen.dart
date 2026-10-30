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
import 'sky_camera_screen.dart';
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

  /// What the camera view would show, from the last build.
  ({List<SkyThing> things, List<SkyTrack> tracks, DateTime? time})? _camera;

  void _openCamera() {
    final c = _camera;
    if (c == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a location to see your sky.')));
      return;
    }
    openSkyCamera(context, things: c.things, tracks: c.tracks, time: c.time);
  }

  Future<void> _pickDate(DateTime now, DateTime at) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: at.isBefore(_firstDay) || at.isAfter(_lastDay) ? now : at,
      firstDate: _firstDay,
      lastDate: _lastDay,
      helpText: 'See the sky on',
    );
    if (picked == null || !mounted) return;
    setState(() => _days = _daysBetween(now, picked).clamp(_minDays(now), _maxDays(now)));
  }
  String? _selected;

  /// The round whole-sky map instead of the horizon view.
  bool _whole = false;

  /// How far the map is moved from now: whole days (the date buttons) plus
  /// up to 12 hours either way (the slider). Both zero = live.
  int _days = 0;
  double _minutes = 0;

  /// Tracks are worked out once per pass and place, not on every tick.
  final _tracks = <String, SkyTrack>{};

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final place = (settings?.placeName?.isNotEmpty ?? false) ? settings!.placeName! : 'Near you';
    final sky = ref.watch(tonightSkyProvider);
    final catalog = ref.watch(skyCatalogProvider).value;
    final now = ref.watch(minuteProvider).value ?? DateTime.now();
    final offset = Duration(days: _days, minutes: _minutes.round());
    final later = offset != Duration.zero;
    final at = now.add(offset);
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
          _camera = (things: [moon, ...planets, ...shows], tracks: tracks, time: later ? at : null);

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
                        ? Kicker(offset.isNegative ? 'Earlier' : 'Later', color: LookUpColors.blue)
                        : const Kicker('Live', color: LookUpColors.good, live: true),
                    Flexible(
                      child: Text(
                          later
                              ? '  ${fmtMoment(at.toUtc())}${offset.inMinutes.abs() < 24 * 60 ? ' · ${_offsetWord(offset)}' : ''}'
                              : '  ${fmtTime(now.toUtc())} · tap anything to open it',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: numeric(size: 13, color: LookUpColors.grey)),
                    ),
                  ]),
                ),
              ),
              _TimeTravel(
                minutes: _minutes,
                onMinutes: (m) => setState(() => _minutes = m),
                onDays: (d) => setState(() => _days = d.clamp(_minDays(now), _maxDays(now))),
                days: _days,
                onNow: () => setState(() {
                  _days = 0;
                  _minutes = 0;
                }),
                onPickDate: () => _pickDate(now, at),
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

/// "in 45 min", "in 7 h 30 min", "3 h ago".
String _offsetWord(Duration d) {
  final total = d.inMinutes.abs(), h = total ~/ 60, m = total % 60;
  final span = h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m min');
  return d.isNegative ? '$span ago' : 'in $span';
}

/// How far the date buttons go: the years 1600 to 2400. Wider needs the
/// Julian calendar, ΔT and proper motion, which the sky maths leaves out.
final _firstDay = DateTime(1600), _lastDay = DateTime(2400, 12, 31);
int _daysBetween(DateTime a, DateTime b) =>
    (DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inHours / 24).round();
int _minDays(DateTime now) => _daysBetween(now, _firstDay) + 1;
int _maxDays(DateTime now) => _daysBetween(now, _lastDay) - 1;

/// Move the map through time: the slider for tonight ("cloudy now, but
/// clear at 3 AM: will Saturn be up then?"), a day at a time either way, or
/// any date from 1600 to 2400. Says the forecast sky when there is one.
class _TimeTravel extends StatelessWidget {
  const _TimeTravel({
    required this.minutes,
    required this.onMinutes,
    required this.days,
    required this.onDays,
    required this.onNow,
    required this.onPickDate,
    required this.at,
    this.skyThen,
  });
  final double minutes;
  final ValueChanged<double> onMinutes;
  final int days;
  final ValueChanged<int> onDays;
  final VoidCallback onNow;
  final VoidCallback onPickDate;
  final DateTime at;
  final String? skyThen;

  static const span = 720.0; // 12 h either way

  @override
  Widget build(BuildContext context) {
    final live = minutes == 0 && days == 0;
    const small = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Slider(
          value: minutes,
          min: -span,
          max: span,
          divisions: (2 * span / 15).round(),
          label: live ? 'Now' : fmtMoment(at.toUtc()),
          semanticFormatterCallback: (_) => live ? 'Now' : 'At ${fmtMoment(at.toUtc())}',
          onChanged: onMinutes,
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton.icon(
            onPressed: () => onDays(days - 1),
            icon: const Icon(Icons.chevron_left_rounded, size: 18),
            label: const Text('Day', style: small),
          ),
          TextButton.icon(
            onPressed: onPickDate,
            icon: const Icon(Icons.calendar_month_rounded, size: 18),
            label: const Text('Date', style: small),
          ),
          TextButton(
            onPressed: () => onDays(days + 1),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Day', style: small),
              SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18),
            ]),
          ),
          TextButton(onPressed: live ? null : onNow, child: const Text('Now', style: small)),
        ]),
        Text(
          skyThen == null
              ? 'Slide through tonight, or step to any date from 1600 to 2400.'
              : 'Sky at ${fmtMoment(at.toUtc())}: ${skyThen!.toLowerCase()}. Tap anything to see if you could spot it then.',
          textAlign: TextAlign.center,
          style: TextStyle(color: skyThen == null ? LookUpColors.greyDim : LookUpColors.grey, fontSize: 12.5, height: 1.4),
        ),
      ]),
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
