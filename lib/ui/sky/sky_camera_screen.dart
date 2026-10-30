/// The whole sky over the camera: stars, constellation figures, planets, the
/// Moon, showpieces and any pass coming over, painted where they are even
/// when cloud, haze or a roof hides the real thing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/finder/pointing.dart';
import '../../domain/sky/direction.dart';
import '../../domain/sky/wmm.dart';
import '../../services/orientation.dart';
import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../finder_camera.dart';
import '../format.dart';
import '../kit/kit.dart';
import '../night_vision_button.dart';
import '../theme.dart';
import 'sky_thing.dart';
import 'sky_track.dart';

Future<void> openSkyCamera(BuildContext context, {required List<SkyThing> things, required List<SkyTrack> tracks, DateTime? time}) =>
    Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => SkyCameraScreen(things: things, tracks: tracks, time: time)));

class SkyCameraScreen extends ConsumerStatefulWidget {
  const SkyCameraScreen({super.key, required this.things, required this.tracks, this.time, this.orientationStream, this.camera = true});
  final List<SkyThing> things;
  final List<SkyTrack> tracks;

  /// A moment the Sky map was moved to; null follows the clock.
  final DateTime? time;

  /// Injected in tests; defaults to the fused rotation sensor.
  final Stream<List<double>>? orientationStream;

  /// Start with the camera on (tests turn it off).
  final bool camera;

  @override
  ConsumerState<SkyCameraScreen> createState() => _SkyCameraState();
}

class _SkyCameraState extends ConsumerState<SkyCameraScreen> {
  StreamSubscription<List<double>>? _sub;
  List<double>? _r;
  String? _error;
  late bool _cameraOn = widget.camera;
  double? _previewHeight;
  double _declination = 0;

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
  }

  @override
  void dispose() {
    _sub?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
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
        ? 'The sky at ${fmtMoment(utc)}'
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
        if (r != null && s?.latitude != null)
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
                  latDeg: s!.latitude!,
                  lonDeg: s.longitude!,
                  tracks: tracks,
                  marks: marks,
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
                const Spacer(),
                const Text('Sky through your camera',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: LookUpColors.grey)),
                const Spacer(),
                const NightVisionButton(),
                const SizedBox(width: 8),
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
