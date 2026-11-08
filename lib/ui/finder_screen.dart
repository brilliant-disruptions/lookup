/// Live sky finder: hold the phone up and Pip guides you onto the target,
/// tracking the satellite in real time. Words stay off the screen: Pip's
/// blink and the phone's ticks say how close you are, VoiceOver reads the
/// directions, and tapping the name opens the Look sheet with the numbers.
///
/// It's also the countdown ([FinderScreen.countdown]): in the last minutes
/// Pip waits where it will rise beside a small clock, and the same screen
/// becomes the finder the moment it appears.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:satellite_observer/satellite_observer.dart';

import '../data/local_store.dart';
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
import '../domain/finder/look_up_now.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'pip/pip_aim.dart';
import 'sky/figure_spotlight.dart';
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
      case SkyEventType.comet:
      case SkyEventType.nova:
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
        final h = event.details['body'] == 'Moon'
            ? moonHorizontal(u, latDeg, lonDeg)
            : sunHorizontal(u, latDeg, lonDeg);
        return SkyDir(h.azimuthDeg, h.altitudeDeg);
      case SkyEventType.lunarEclipse:
      case SkyEventType.occultation:
      case SkyEventType.occultationNear:
      case SkyEventType.fullMoonRise:
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
        return SkyDir(
          dirs.map((d) => d.azimuthDeg).reduce((a, b) => a + b) / dirs.length,
          dirs.map((d) => d.altitudeDeg).reduce((a, b) => a + b) / dirs.length,
        );
      default:
        // Before it starts, wait where it will appear, as for a live pass.
        if (u.isBefore(event.start)) return SkyDir(event.riseAzimuthDeg, 2);
        return SkyDir(event.peakAzimuthDeg, event.peakElevationDeg);
    }
  }
}

class FinderScreen extends ConsumerStatefulWidget {
  const FinderScreen({super.key, required this.event, this.orientationStream, this.camera, this.countdown = false});
  final SkyEvent event;

  /// Opened for the final countdown: Pip waits at the rise point with a
  /// clock, no route run, and a chime when it comes up.
  final bool countdown;

  /// Injected in tests; defaults to the fused rotation sensor.
  final Stream<List<double>>? orientationStream;

  /// Start over the camera; defaults to yes for things tracked live.
  final bool? camera;

  @override
  ConsumerState<FinderScreen> createState() => _FinderState();
}

class _FinderState extends ConsumerState<FinderScreen> with TickerProviderStateMixin, FigureSpotlight {
  // The finder buzzes when you're on the target; a tick per constellation
  // would muddle that.
  @override
  bool get figureTicks => false;

  StreamSubscription<List<double>>? _sub;
  List<double>? _r;
  String? _error;
  bool _wasOnTarget = false;
  bool _cameraOn = false;

  /// For the lock-rate tally: when a compass reading first came in, and how
  /// long until the first lock (the ghost run's demo doesn't count).
  final Stopwatch _since = Stopwatch();
  Duration? _toLock;
  late final LocalStore _store;

  /// Whether it had appeared at the last build; null before the first.
  bool? _wasUp;

  /// The ghost run: the firefly flies the route once before the pass.
  late final Ticker _ghost = createTicker(
    (elapsed) => setState(() {
      _ghostSince = elapsed;
      if (elapsed >= ghostRunLength) _ghost.stop();
    }),
  );
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
    _store = ref.read(storeProvider);
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
    _sub = stream?.listen((r) {
      if (!_since.isRunning) _since.start();
      setState(() => _r = r);
    }, onError: (e) => setState(() => _error = '$e'));
    if (stream == null) _error ??= 'This device has no orientation sensor.';
  }

  @override
  void dispose() {
    _landmarkHold?.cancel();
    if (_since.isRunning) _store.recordFinderSession(_toLock);
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
    figureFadeOn = !MediaQuery.disableAnimationsOf(context);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final target = _target!.at(now);
    final r = _r;
    final camera = r == null ? null : cameraDirection(r, declinationDeg: _declination);
    final e = widget.event;
    final nowUtc = now.toUtc();
    final before = nowUtc.isBefore(e.start);
    final counting = widget.countdown && before;

    // Before a pass, Pip first flies its route once (not in the countdown:
    // there's no time, just point where it rises).
    if (!_ghostStarted &&
        before &&
        !widget.countdown &&
        _route.length >= 2 &&
        !MediaQuery.of(context).disableAnimations) {
      _ghostStarted = true;
      _ghostSince = Duration.zero;
      _ghost.start();
    }
    final ghostAt = _ghostSince == null ? null : ghostProgress(_ghostSince!);

    // Star-hop: when the pass goes by a bright planet or star, find that
    // first, then the spot by it where the pass will go.
    final hop = counting ? null : landmarkPoints(e).firstOrNull;
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
    final ghosting = step == FireflyStep.ghostRun;

    final g = camera == null ? null : guide(camera, goal);
    if (g != null && g.onTarget != _wasOnTarget) {
      _wasOnTarget = g.onTarget;
      _landmarkHold?.cancel();
      if (g.onTarget && !ghosting) _toLock ??= _since.elapsed;
      // The first lock teaches it: the coach mark goes for good.
      if (g.onTarget && !ghosting && !(ref.read(settingsProvider).value?.pipCoached ?? true)) {
        // After this frame: a provider can't change while we build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(settingsProvider.notifier).edit((s) => s.copyWith(pipCoached: true));
        });
      }
    }
    // On the landmark for a moment: hop to the spot by it.
    if (step == FireflyStep.findLandmark && (g?.onTarget ?? false) && !(_landmarkHold?.isActive ?? false)) {
      _landmarkHold = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _landmarkFound = true);
      });
    }
    // The countdown ends: a chime, and this screen is now the finder.
    final up = !before;
    if (widget.countdown && up && _wasUp == false) SystemSound.play(SystemSoundType.alert);
    _wasUp = up;
    // Pip's guide: where the target is on screen, and which way to turn
    // when it isn't.
    ({double x, double y})? onScreen;
    if (g != null && r != null) {
      if (_cameraOn) {
        onScreen = projectToScreen(
          r,
          goal,
          declinationDeg: _declination,
          previewHeightPx: _previewHeight ?? MediaQuery.sizeOf(context).height,
        );
      } else {
        onScreen = (x: g.dAzimuth * 6, y: -g.dElevation * 6);
      }
    }
    Widget? pip(bool full) => g == null || _cameraOn != full
        ? null
        : PipAim(
            mode: counting ? PipMode.countdown : PipMode.find,
            target: onScreen,
            toward: towardOnScreen(g),
            distanceDeg: g.distanceDeg,
            onTarget: g.onTarget,
            canLock: !ghosting,
            appeared: up,
            ring: !full,
            words: ghosting ? 'Watch the route' : g.words,
            // Only a landmark's name: the rest is in the motion.
            label: step == FireflyStep.findLandmark ? hopName : null,
          );
    final coach = g != null && !ghosting && !(ref.watch(settingsProvider).value?.pipCoached ?? true);
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
                  art: (ref.watch(settingsProvider).value?.skyFigures ?? true) ? figureArt : null,
                  glow: figureGlow,
                  onSpotlit: onFigureSpotlit,
                  twinkle: figureFadeOn ? figureTwinkle : null,
                ),
              ),
            ),
          )
        : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
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
          if (pip(true) case final f?) Positioned.fill(child: f),
          Starfield(
            density: _cameraOn ? 0 : 0.0002,
            maxOpacity: 0.5,
            fadeBottom: false,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        CircleButton(
                          tooltip: 'Close',
                          icon: Icons.close_rounded,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Semantics(
                            button: true,
                            hint: 'Shows where and when to look',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => showLookSheet(context, e),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                child: Text(
                                  eventTitle(e),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: LookUpColors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        CircleButton(
                          tooltip: _cameraOn ? 'Hide camera' : 'Show camera',
                          icon: _cameraOn ? Icons.videocam_off_rounded : Icons.photo_camera_rounded,
                          onPressed: () => setState(() => _cameraOn = !_cameraOn),
                        ),
                      ],
                    ),
                  ),
                  // The clock stands alone.
                  if (counting)
                    Text(
                      LookUpNow.clock(e.start.difference(nowUtc)),
                      style: numeric(size: 22, color: LookUpColors.white),
                    ),
                  if (coach)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: Text(
                        'Bring the light into the ring',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: LookUpColors.grey, fontSize: 15),
                      ),
                    ),
                  Expanded(child: pip(false) ?? const SizedBox.expand()),
                  // No sensor, or none yet: the compass words are all there is.
                  if (g == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                      child: Text(
                        'Look ${compassWord(target.azimuthDeg)}, ${elevationWord(target.elevationDeg)}',
                        textAlign: TextAlign.center,
                        style: display(22, weight: FontWeight.w700),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (step == FireflyStep.findLandmark || step == FireflyStep.meetingPoint)
                          CircleButton(
                            tooltip: 'Go straight to where it rises',
                            icon: Icons.skip_next_rounded,
                            onPressed: () => setState(() => _skipHop = true),
                          ),
                        if (before && !counting && _route.length >= 2)
                          CircleButton(tooltip: 'Show the route again', icon: Icons.replay_rounded, onPressed: _replay),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
