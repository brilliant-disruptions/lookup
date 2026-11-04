/// The whole sky over the camera: stars, constellation figures, planets, the
/// Moon, showpieces and any pass coming over, painted where they are even
/// when cloud, haze or a roof hides the real thing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/finder/pointing.dart';
import '../../domain/models/sky_event.dart';
import '../../domain/sky/direction.dart';
import '../../domain/sky/wmm.dart';
import '../../services/orientation.dart';
import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../finder_camera.dart';
import '../format.dart';
import '../kit/kit.dart';
import '../theme.dart';
import 'constellation_glow.dart' show figureFade;
import 'figure_art.dart';
import 'sky_thing.dart';
import 'sky_track.dart';

Future<void> openSkyCamera(BuildContext context,
        {required List<SkyThing> things, required List<SkyTrack> tracks, DateTime? time, double? lat, double? lon}) =>
    Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SkyCameraScreen(things: things, tracks: tracks, time: time, lat: lat, lon: lon)));

/// The camera view of the sky as it is now, from outside the Sky tab (Tonight's
/// header): the Moon, planets, showpieces and passes the live map shows.
Future<void> openLiveSkyCamera(BuildContext context, WidgetRef ref) async {
  final s = ref.read(settingsProvider).value;
  final lat = s?.latitude, lon = s?.longitude;
  final t = await ref.read(tonightSkyProvider.future);
  if (!context.mounted) return;
  if (t == null || lat == null || lon == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Set a location to see your sky.')));
    return;
  }
  final events = ref.read(homeProvider).value?.events ?? const <SkyEvent>[];
  return openSkyCamera(context,
      things: [
        SkyThing.moon(t.moon, lat, lon),
        for (final p in t.planets) SkyThing.planet(p, lat, lon),
        for (final x in t.showpieces) SkyThing.showpiece(x, lat, lon),
      ],
      tracks: [for (final e in upcomingPasses(events, DateTime.now().toUtc())) passTrack(e, lat, lon)],
      lat: lat,
      lon: lon);
}

class SkyCameraScreen extends ConsumerStatefulWidget {
  const SkyCameraScreen(
      {super.key, required this.things, required this.tracks, this.time, this.lat, this.lon, this.orientationStream, this.camera = true});
  final List<SkyThing> things;
  final List<SkyTrack> tracks;

  /// Where the sky map is standing, when it isn't home (a famous night).
  final double? lat, lon;

  /// A moment the Sky map was moved to; null follows the clock.
  final DateTime? time;

  /// Injected in tests; defaults to the fused rotation sensor.
  final Stream<List<double>>? orientationStream;

  /// Start with the camera on (tests turn it off).
  final bool camera;

  @override
  ConsumerState<SkyCameraScreen> createState() => _SkyCameraState();
}

class _SkyCameraState extends ConsumerState<SkyCameraScreen> with SingleTickerProviderStateMixin {
  StreamSubscription<List<double>>? _sub;
  List<double>? _r;
  String? _error;
  late bool _cameraOn = widget.camera;
  double? _previewHeight;
  double _declination = 0;
  FigureArt? _art;

  /// The picture in the middle lights up and the last one lets go, as on
  /// the Sky tab: how lit each is, 0 to 1.
  final _glow = ValueNotifier<Map<String, double>>(const {});
  late final _glowTicker = createTicker(_stepGlow);
  Duration _glowLast = Duration.zero;
  String? _spotlit;
  bool _fade = true;
  String? _ticked;

  /// A running clock (seconds) for the lit constellation's stars to twinkle
  /// by. It only ticks while something is lit and motion is allowed.
  final _twinkle = ValueNotifier<double>(0);

  /// Called from paint, so it only starts the ticker; the levels change on
  /// the next frame.
  void _onSpotlit(String? id) {
    if (id == _spotlit) return;
    _spotlit = id;
    // A light tick as a new constellation settles in the middle; not again
    // for the same one, so wavering on its edge doesn't buzz.
    if (id != null && id != _ticked) {
      _ticked = id;
      HapticFeedback.selectionClick();
    }
    if (!_glowTicker.isActive) {
      _glowLast = Duration.zero;
      _glowTicker.start();
    }
  }

  void _stepGlow(Duration elapsed) {
    final dt = elapsed - _glowLast;
    final step = _fade ? dt.inMicroseconds / figureFade.inMicroseconds : 1.0;
    _glowLast = elapsed;
    final next = <String, double>{};
    var settled = true, changed = false;
    for (final id in {..._glow.value.keys, ?_spotlit}) {
      final target = id == _spotlit ? 1.0 : 0.0;
      final n = ((_glow.value[id] ?? 0.0) + (target > 0 ? step : -step)).clamp(0.0, 1.0);
      if (n > 0) next[id] = n;
      if (n != target) settled = false;
      if (n != _glow.value[id]) changed = true;
    }
    if (changed) _glow.value = next;
    final twinkling = _fade && _spotlit != null;
    if (twinkling) _twinkle.value += dt.inMicroseconds / 1e6;
    if (settled && !twinkling) _glowTicker.stop();
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final s = ref.read(settingsProvider).value;
    _declination = declinationDeg(s?.latitude ?? 0, s?.longitude ?? 0, DateTime.now().toUtc());
    var stream = widget.orientationStream;
    try {
      stream ??= deviceRotation();
    } catch (e) {
      _error = '$e';
    }
    _sub = stream?.listen((r) => setState(() => _r = r), onError: (e) => setState(() => _error = '$e'));
    if (stream == null) _error ??= 'This device has no orientation sensor.';
    FigureArt.load().then((art) {
      if (!mounted) return;
      setState(() => _art = art..addListener(_onArt));
    }, onError: (_) {});
  }

  void _onArt() => setState(() {});

  @override
  void dispose() {
    _sub?.cancel();
    _art?.removeListener(_onArt);
    _glowTicker.dispose();
    _glow.dispose();
    _twinkle.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    _fade = !MediaQuery.disableAnimationsOf(context);
    // The sky drawn is the map's place; the compass is always where you are.
    final lat = widget.lat ?? s?.latitude, lon = widget.lon ?? s?.longitude;
    final now = widget.time ?? ref.watch(clockProvider).value ?? DateTime.now();
    final utc = now.toUtc();
    final r = _r;
    final marks = <OverlayMark>[
      for (final t in widget.things)
        if (t.position(utc) case final h when h.altitudeDeg > -1)
          (label: t.id == 'moon' ? 'Moon' : t.name, d: SkyDir(h.azimuthDeg, h.altitudeDeg), bright: t.id == 'moon' || t.kind == 'Planet'),
    ];
    final tracks = <OverlayTrack>[
      for (final tr in widget.tracks)
        (
          label: eventTitle(tr.event),
          path: [for (final p in tr.points) (t: p.t, d: SkyDir(p.h.azimuthDeg, p.h.altitudeDeg))],
          now: switch (tr.at(utc)) { final h? => SkyDir(h.azimuthDeg, h.altitudeDeg), null => null },
          color: tr.color,
        ),
    ];
    final camera = r == null ? null : cameraDirection(r, declinationDeg: _declination);
    // Whatever sits nearest the middle of the view, if anything's close.
    final centred = camera == null
        ? null
        : marks
            .map((m) => (m: m, d: angularDistanceDeg(camera, m.d)))
            .where((x) => x.d < 12)
            .fold<({OverlayMark m, double d})?>(null, (best, x) => best == null || x.d < best.d ? x : best);
    final passing = widget.tracks.where((tr) => tr.liveAt(utc)).map((tr) => eventTitle(tr.event)).toList();
    final status = widget.time != null
        ? 'The sky at ${fmtSkyMoment(utc, lon ?? 0)}'
        : passing.isNotEmpty
            ? '${passing.join(' and ')} going over now'
            : widget.tracks.isNotEmpty
                ? 'Next: ${widget.tracks.first.label}'
                : 'Stars, planets and the Moon, live';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_cameraOn)
          Positioned.fill(
            child: CameraBackdrop(
              onHeight: (h) => _previewHeight = h,
              onError: (msg) {
                if (!mounted) return;
                setState(() => _cameraOn = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              },
            ),
          ),
        if (r != null && lat != null && lon != null)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) => CustomPaint(
                painter: SkyOverlayPainter(
                  r: r,
                  declinationDeg: _declination,
                  now: utc,
                  previewHeightPx: _previewHeight ?? c.maxHeight,
                  labelStyle: Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
                  catalog: ref.watch(skyCatalogProvider).value,
                  latDeg: lat,
                  lonDeg: lon,
                  tracks: tracks,
                  marks: marks,
                  art: (s?.skyFigures ?? true) ? _art : null,
                  glow: _glow,
                  onSpotlit: _onSpotlit,
                  twinkle: _fade ? _twinkle : null,
                ),
              ),
            ),
          ),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                CircleButton(tooltip: 'Close', icon: Icons.close_rounded, onPressed: () => Navigator.of(context).pop()),
                // Between the buttons, trimmed rather than overflowing on a small phone with big text.
                const Expanded(
                  child: Text('Sky through your camera',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: LookUpColors.grey)),
                ),
                CircleButton(
                  tooltip: _cameraOn ? 'Hide camera' : 'Show camera',
                  icon: _cameraOn ? Icons.videocam_off_rounded : Icons.photo_camera_rounded,
                  onPressed: () => setState(() => _cameraOn = !_cameraOn),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
              child: Text(
                camera == null
                    ? (_error != null ? 'No motion sensor here, so this view can\'t follow the phone.' : 'Hold your phone up to the sky')
                    : centred != null
                        ? 'That\'s ${centred.m.label == 'Moon' ? 'the Moon' : centred.m.label}'
                        : 'Looking ${compassWord(camera.azimuthDeg)}, ${elevationWord(camera.elevationDeg)}',
                textAlign: TextAlign.center,
                style: display(24, weight: FontWeight.w700).copyWith(shadows: const [Shadow(blurRadius: 8, color: Colors.black)]),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                'Cloud, haze or a roof in the way? Everything is still drawn where it is. '
                'Wave the phone in a figure-8 if it drifts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: LookUpColors.grey, fontSize: 12, shadows: [Shadow(blurRadius: 6, color: Colors.black)]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
