/// Live sky finder: hold the phone up and it guides you onto the target,
/// tracking the satellite in real time. Vibrates when you're on it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:satellite_observer/satellite_observer.dart';

import '../domain/finder/firefly.dart';
import '../domain/finder/pointing.dart';
import '../domain/models/sky_event.dart';
import '../domain/orbit/omm.dart';
import '../domain/sky/astro.dart';
import '../domain/sky/direction.dart';
import '../domain/sky/landmarks.dart';
import '../domain/sky/wmm.dart';
import '../services/orientation.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'finder_camera.dart';
import 'finder_firefly.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'night_vision_button.dart';
import 'theme.dart';

Future<void> openFinder(BuildContext context, SkyEvent event) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => FinderScreen(event: event)));

/// Where to point at [now] for [event]. Satellites are propagated live from
/// the elements stored on the event; sky objects are computed live.
class FinderTarget {
  FinderTarget(this.event, {required this.latDeg, required this.lonDeg}) {
    final omm = event.details['omm'];
    if (omm is Map) {
      try {
        _sat = SatelliteObserver(
          elements: OmmRecord.fromJson(omm.cast<String, Object?>()).toElements(),
          observer: Observer(latitudeDeg: latDeg, longitudeDeg: lonDeg),
        );
      } catch (_) {
        _sat = null;
      }
    }
  }

  final SkyEvent event;
  final double latDeg, lonDeg;
  SatelliteObserver? _sat;

  bool get isLive => _sat != null;

  /// The whole pass across the sky, for the camera overlay. Empty for
  /// things that don't move across it.
  late final List<({DateTime t, SkyDir d})> path = () {
    final sat = _sat;
    if (sat == null) return const <({DateTime t, SkyDir d})>[];
    final out = <({DateTime t, SkyDir d})>[];
    for (var t = event.start; !t.isAfter(event.end); t = t.add(const Duration(seconds: 10))) {
      final look = sat.lookAngleAt(t);
      out.add((t: t, d: SkyDir(look.azimuthDeg, look.elevationDeg)));
    }
    return out;
  }();

  SkyDir at(DateTime now) {
    final u = now.toUtc();
    final sat = _sat;
    if (sat != null) {
      // Before the pass: wait where it will appear. During: track it.
      final t = u.isBefore(event.start) ? event.start : (u.isAfter(event.end) ? event.end : u);
      final look = sat.lookAngleAt(t);
      return SkyDir(look.azimuthDeg, math.max(look.elevationDeg, 2));
    }
    switch (event.type) {
      case SkyEventType.auroraNow:
      case SkyEventType.auroraOutlook:
        return const SkyDir(0, 15);
      case SkyEventType.planetHighlight:
      case SkyEventType.skyObject:
        final planet = Planet.values.where((p) => p.label == event.details['planet']).firstOrNull;
        if (planet != null) {
          final h = planetHorizontal(planet, u, latDeg, lonDeg);
          return SkyDir(h.azimuthDeg, h.altitudeDeg);
        }
        if (event.details['moon'] == true) {
          final h = moonHorizontal(u, latDeg, lonDeg);
          return SkyDir(h.azimuthDeg, h.altitudeDeg);
        }
        final ra = event.details['ra'], dec = event.details['dec'];
        if (ra is num && dec is num) {
          final h = catalogHorizontal(ra.toDouble(), dec.toDouble(), u, latDeg, lonDeg);
          return SkyDir(h.azimuthDeg, h.altitudeDeg);
        }
        return SkyDir(event.peakAzimuthDeg, event.peakElevationDeg);
      case SkyEventType.issTransit:
        final h = event.details['body'] == 'Moon' ? moonHorizontal(u, latDeg, lonDeg) : sunHorizontal(u, latDeg, lonDeg);
        return SkyDir(h.azimuthDeg, h.altitudeDeg);
      case SkyEventType.lunarEclipse:
        final m = moonHorizontal(u, latDeg, lonDeg);
        return SkyDir(m.azimuthDeg, m.altitudeDeg);
      case SkyEventType.planetPairing:
        final bodies = (event.details['bodies'] as List?)?.cast<String>() ?? const [];
        final dirs = [
          for (final b in bodies)
            if (b == 'Moon')
              moonHorizontal(u, latDeg, lonDeg)
            else
              for (final p in Planet.values)
                if (p.label == b) planetHorizontal(p, u, latDeg, lonDeg),
        ];
        if (dirs.isEmpty) return SkyDir(event.peakAzimuthDeg, event.peakElevationDeg);
        return SkyDir(dirs.map((d) => d.azimuthDeg).reduce((a, b) => a + b) / dirs.length,
            dirs.map((d) => d.altitudeDeg).reduce((a, b) => a + b) / dirs.length);
      default:
        return SkyDir(event.peakAzimuthDeg, event.peakElevationDeg);
    }
  }
}

class FinderScreen extends ConsumerStatefulWidget {
  const FinderScreen({super.key, required this.event, this.orientationStream, this.camera});
  final SkyEvent event;

  /// Injected in tests; defaults to the fused rotation sensor.
  final Stream<List<double>>? orientationStream;

  /// Start over the camera; defaults to yes for things tracked live.
  final bool? camera;

  @override
  ConsumerState<FinderScreen> createState() => _FinderState();
}

class _FinderState extends ConsumerState<FinderScreen> with SingleTickerProviderStateMixin {
  StreamSubscription<List<double>>? _sub;
  List<double>? _r;
  String? _error;
  bool _wasOnTarget = false;
  bool _cameraOn = false;

  /// Whether it had appeared at the last build; null before the first.
  bool? _wasUp;
  bool _details = false;

  /// The ghost run: the firefly flies the route once before the pass.
  late final Ticker _ghost = createTicker((elapsed) => setState(() {
        _ghostSince = elapsed;
        if (elapsed >= ghostRunLength) _ghost.stop();
      }));
  Duration? _ghostSince;
  bool _ghostStarted = false;

  /// Star-hop: held on the landmark a moment (or skipped it).
  bool _landmarkFound = false, _skipHop = false;
  Timer? _landmarkHold;
  late final double _declination;
  FinderTarget? _target;
  double? _previewHeight;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final s = ref.read(settingsProvider).value;
    final lat = s?.latitude ?? 0, lon = s?.longitude ?? 0;
    _declination = declinationDeg(lat, lon, DateTime.now().toUtc());
    _target = FinderTarget(widget.event, latDeg: lat, lonDeg: lon);
    // Things tracked live open over the camera: the path shows through
    // cloud, haze and rooftops.
    _cameraOn = widget.camera ?? _target!.isLive;
    Stream<List<double>>? stream = widget.orientationStream;
    if (stream == null) {
      try {
        stream = deviceRotation();
      } catch (e) {
        _error = '$e';
      }
    }
    _sub = stream?.listen((r) => setState(() => _r = r), onError: (e) => setState(() => _error = '$e'));
    if (stream == null) _error ??= 'This device has no orientation sensor.';
  }

  @override
  void dispose() {
    _landmarkHold?.cancel();
    _ghost.dispose();
    _sub?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  late final List<SkyDir> _route = [for (final p in _target!.path) p.d];

  void _replay() {
    _ghost.stop();
    setState(() => _ghostSince = Duration.zero);
    _ghost.start();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final target = _target!.at(now);
    final r = _r;
    final camera = r == null ? null : cameraDirection(r, declinationDeg: _declination);
    final e = widget.event;
    final nowUtc = now.toUtc();
    final before = nowUtc.isBefore(e.start);
    final over = !nowUtc.isBefore(e.end);

    // Before a pass, the firefly first flies its route once.
    if (!_ghostStarted && before && _route.length >= 2 && !MediaQuery.of(context).disableAnimations) {
      _ghostStarted = true;
      _ghostSince = Duration.zero;
      _ghost.start();
    }
    final ghostAt = _ghostSince == null ? null : ghostProgress(_ghostSince!);

    // Star-hop: when the pass goes by a bright planet or star, find that
    // first, then the spot by it where the pass will go.
    final hop = landmarkPoints(e).firstOrNull;
    final hopAt = hop == null
        ? null
        : landmarkDirection(hop.name, ref.watch(skyCatalogProvider).value, nowUtc, _target!.latDeg, _target!.lonDeg);
    final step = fireflyStep(
      beforePass: before,
      ghostRunning: ghostAt != null && _ghost.isActive,
      hasLandmark: hop != null && hopAt != null && hopAt.altitudeDeg > 0 && _route.length >= 2,
      landmarkFound: _landmarkFound,
      skipped: _skipHop,
    );
    final goal = switch (step) {
      FireflyStep.ghostRun => alongRoute(_route, ghostAt!),
      FireflyStep.findLandmark => SkyDir(hopAt!.azimuthDeg, hopAt.altitudeDeg),
      FireflyStep.meetingPoint => alongRoute(_route, hop!.f),
      FireflyStep.target => target,
    };
    final hopName = hop == null ? '' : '${hop.name[0].toUpperCase()}${hop.name.substring(1)}';
    final hopWhen = hop == null ? null : e.start.add(e.end.difference(e.start) * hop.f);
    final hopHow = hop == null ? '' : (hop.close ? 'right by' : 'close to');

    final g = camera == null ? null : guide(camera, goal);
    if (g != null && g.onTarget != _wasOnTarget) {
      _wasOnTarget = g.onTarget;
      _landmarkHold?.cancel();
      if (g.onTarget && step != FireflyStep.ghostRun) HapticFeedback.heavyImpact();
    }
    // On the landmark for a moment: hop to the spot by it.
    if (step == FireflyStep.findLandmark && (g?.onTarget ?? false) && !(_landmarkHold?.isActive ?? false)) {
      _landmarkHold = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _landmarkFound = true);
      });
    }
    // It appears while the finder is open: one firm buzz.
    final up = !nowUtc.isBefore(e.start);
    if (up && _wasUp == false) HapticFeedback.heavyImpact();
    _wasUp = up;
    // The firefly's guide: where the target is on screen, and which way to
    // turn when it isn't.
    ({double x, double y})? onScreen;
    if (g != null && r != null) {
      if (_cameraOn) {
        onScreen = projectToScreen(r, goal,
            declinationDeg: _declination, previewHeightPx: _previewHeight ?? MediaQuery.sizeOf(context).height);
      } else {
        onScreen = (x: g.dAzimuth * 6, y: -g.dElevation * 6);
      }
    }
    final targetLabel = !_target!.isLive
        ? eventTitle(e)
        : before
            ? 'Comes up here ${fmtTime(e.start)}'
            : !over
                ? '${eventTitle(e)} · now'
                : null;
    final ghosting = step == FireflyStep.ghostRun;
    Widget? firefly(bool full) => g == null || _cameraOn != full
        ? null
        : FireflyLayer(
            target: onScreen,
            toward: towardOnScreen(g),
            // A lazy blink while it flies the route; no "you're on it".
            distanceDeg: ghosting ? 40 : g.distanceDeg,
            onTarget: !ghosting && g.onTarget,
            label: switch (step) {
              FireflyStep.ghostRun => null,
              FireflyStep.findLandmark => hopName,
              FireflyStep.meetingPoint => 'Passes here · ${fmtTime(hopWhen!)}',
              FireflyStep.target => targetLabel,
            },
          );
    final status = switch (step) {
      FireflyStep.ghostRun => 'Here\'s the route it will take.',
      FireflyStep.findLandmark => 'Start from $hopName: it passes $hopHow it at ${fmtTime(hopWhen!)}.',
      FireflyStep.meetingPoint =>
        'It passes $hopHow ${hop!.name} here at ${fmtTime(hopWhen!)}. Appears in ${fmtCountdown(e.start.difference(nowUtc))}.',
      FireflyStep.target => before
          ? 'Appears in ${fmtCountdown(e.start.difference(nowUtc))}. Point where it will rise.'
          : !over
              ? (_target!.isLive || e.type == SkyEventType.skyObject ? 'Tracking it live' : 'Happening now')
              : 'That one\'s over',
    };
    final hopping = step == FireflyStep.findLandmark || step == FireflyStep.meetingPoint;
    final overlay = _cameraOn && r != null
        ? Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) => CustomPaint(
                painter: SkyOverlayPainter(
                  r: r,
                  declinationDeg: _declination,
                  path: _target!.path,
                  now: nowUtc,
                  onTarget: g?.onTarget ?? false,
                  previewHeightPx: _previewHeight ?? c.maxHeight,
                  labelStyle: Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
                  catalog: ref.watch(skyCatalogProvider).value,
                  latDeg: _target!.latDeg,
                  lonDeg: _target!.lonDeg,
                ),
              ),
            ),
          )
        : null;
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
        ?overlay,
        if (firefly(true) case final f?) Positioned.fill(child: f),
        Starfield(
        density: _cameraOn ? 0 : 0.0002,
        maxOpacity: 0.5,
        fadeBottom: false,
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                CircleButton(tooltip: 'Close', icon: Icons.close_rounded, onPressed: () => Navigator.of(context).pop()),
                const Spacer(),
                const Text('Sky finder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: LookUpColors.grey)),
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
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(children: [
                Text(eventTitle(e), textAlign: TextAlign.center, style: display(28, weight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(status, textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.grey, fontSize: 15)),
                if (hopping)
                  TextButton(
                    onPressed: () => setState(() => _skipHop = true),
                    child: const Text('Go straight to where it rises'),
                  ),
                if (_route.length >= 2 && !over)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: RouteMap(
                      route: _route,
                      at: ghosting
                          ? ghostAt
                          : before
                              ? null
                              : nowUtc.difference(e.start).inMilliseconds / e.end.difference(e.start).inMilliseconds,
                      facingAzimuth: camera?.azimuthDeg,
                      onReplay: before ? _replay : null,
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Semantics(
                  liveRegion: true,
                  label: g == null
                      ? 'Look ${compassWord(target.azimuthDeg)}, ${elevationWord(target.elevationDeg)}'
                      : g.words,
                  child: _cameraOn
                      ? const SizedBox.expand()
                      : Stack(children: [
                          CustomPaint(
                            size: Size(c.maxWidth, c.maxHeight),
                            painter: _ReticlePainter(onTarget: g?.onTarget ?? false),
                          ),
                          ?firefly(false),
                        ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                (ghosting ? 'Watch the route' : g?.words) ?? (_error != null ? 'Look ${compassWord(target.azimuthDeg)}, ${elevationWord(target.elevationDeg)}' : 'Hold your phone up toward the sky'),
                textAlign: TextAlign.center,
                style: display(28, weight: FontWeight.w700,
                    color: (g?.onTarget ?? false) ? LookUpColors.blue : LookUpColors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _details = !_details),
                child: Semantics(
                  button: true,
                  label: _details ? 'Hide details' : 'Show details',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      _details
                          ? '${compassAbbrev(target.azimuthDeg)} ${target.azimuthDeg.round()}°  ·  ${target.elevationDeg.round()}° up'
                              '${camera == null ? '' : '   ·   you ${camera.azimuthDeg.round()}° / ${camera.elevationDeg.round()}°'}'
                          : 'Look ${compassWord(target.azimuthDeg)}, ${elevationWord(target.elevationDeg)}  ·  Details',
                      textAlign: TextAlign.center,
                      style: _details ? numeric(size: 13, color: LookUpColors.grey) : const TextStyle(fontSize: 13, color: LookUpColors.grey),
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text('No motion sensor here, so use the directions above.',
                    textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                  _cameraOn
                      ? 'Cloud or a roof in the way? The line still shows where it is. '
                          'Wave the phone in a figure-8 if it drifts.'
                      : 'Tip: wave the phone in a figure-8 once to calibrate the compass.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
            ),
          ]),
        ),
      ),
      ]),
    );
  }
}

/// The ring in the middle: bring the firefly into it.
class _ReticlePainter extends CustomPainter {
  _ReticlePainter({required this.onTarget});
  final bool onTarget;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ring = Paint()
      ..color = (onTarget ? fireflyWarm : LookUpColors.white).withValues(alpha: onTarget ? 0.9 : 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = onTarget ? 2.5 : 1.2;
    canvas.drawCircle(c, 44, ring);
    final tick = Paint()
      ..color = LookUpColors.grey.withValues(alpha: 0.4)
      ..strokeWidth = 1.2;
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(c + d * 52, c + d * 64, tick);
    }
  }

  @override
  bool shouldRepaint(_ReticlePainter o) => o.onTarget != onTarget;
}
