/// The Pro camera (LookUp+): LookUp works out the photograph, then helps
/// you take it.
///
///  * Photo: the right lens, shutter, ISO, focus and white balance for what
///    you're shooting (domain/photo/shot_plan.dart); Pip leads you to it;
///    it waits until the phone is pointed, level and still; a self-timer so
///    the tap doesn't shake it; then many frames stacked into one picture
///    (domain/photo/frame_stack.dart). While you aim it watches the frames
///    and fixes the exposure itself, saying why (frame_check.dart).
///  * Timelapse: LookUp says where to point and how to stand the phone,
///    then it starts by itself when the thing appears and stops when it's
///    gone (domain/photo/timelapse_plan.dart), and saves the clip.
///
/// Passes photograph best as a streak: Catch it (catch_it_screen.dart).
/// Numbers live in one line, behind "Pro": everything else is words.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/finder/firefly.dart' show towardOnScreen;
import '../domain/finder/pointing.dart';
import '../domain/models/sky_event.dart';
import '../domain/photo/camera.dart';
import '../domain/photo/capture_plan.dart';
import '../domain/photo/exposure.dart';
import '../domain/photo/frame_check.dart';
import '../domain/photo/frame_stack.dart';
import '../domain/photo/framing.dart';
import '../domain/photo/shot_plan.dart';
import '../domain/photo/timelapse_plan.dart';
import '../domain/plus/free_plan.dart';
import '../domain/sky/astro.dart';
import '../domain/sky/direction.dart';
import '../domain/sky/wmm.dart';
import '../services/capture/capture_backend.dart';
import '../services/capture/native_capture.dart';
import '../services/capture/plugin_capture.dart';
import '../services/capture/timelapse_encoder.dart';
import '../services/capture/timelapse_runner.dart';
import '../services/orientation.dart';
import 'keep_catch.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'catch_it_screen.dart';
import 'caught_it_screen.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'pip/pip_aim.dart';
import 'sky/sky_capture.dart';
import 'sky/sky_thing.dart';
import 'theme.dart';

/// What the Pro camera is pointed at.
class ShotTarget {
  const ShotTarget({required this.name, required this.subject, required this.position, this.event, this.thing, this.path});

  /// In a sentence: "the Moon", "Jupiter", "ISS flyover".
  final String name;
  final ShotSubject subject;
  final Horizontal Function(DateTime utc) position;
  final SkyEvent? event;
  final SkyThing? thing;

  /// A pass's way across the sky, for framing its timelapse.
  final List<PathPoint>? path;

  factory ShotTarget.ofThing(SkyThing t) =>
      ShotTarget(name: t.id == 'moon' ? 'the Moon' : t.name, subject: subjectForThing(t.id), position: t.position, thing: t);

  /// For an event; null where there's nothing to photograph (the Sun).
  static ShotTarget? ofEvent(SkyEvent e, double lat, double lon) {
    final subject = subjectForEvent(e.type);
    if (subject == null) return null;
    if (subject == ShotSubject.pass) {
      final path = passPath(e, lat, lon);
      if (path.isEmpty) return null;
      Horizontal at(DateTime t) {
        final p = path.lastWhere((p) => !p.t.isAfter(t), orElse: () => path.first);
        return Horizontal(p.d.azimuthDeg, p.d.elevationDeg);
      }

      return ShotTarget(name: eventTitle(e), subject: subject, position: at, event: e, path: path);
    }
    return ShotTarget(
        name: eventTitle(e), subject: subject, position: (_) => Horizontal(e.peakAzimuthDeg, e.peakElevationDeg), event: e);
  }

  /// The sighting a picture of it logs.
  SkyEvent asEvent(DateTime now, double lat, double lon) => event ?? thing!.asEvent(now, lat, lon);
}

enum ProMode { photo, timelapse }

/// Opens the Pro camera on [target]: LookUp+ only (free gets the paywall),
/// and a pass's photo goes to Catch it.
Future<void> openProCamera(BuildContext context, WidgetRef ref, ShotTarget target, {ProMode mode = ProMode.photo}) {
  final isPlus = ref.read(settingsProvider).value?.isPlus ?? false;
  if (!FreePlan.canUse(PlusFeature.camera, isPlus: isPlus)) return showPaywall(context, feature: PlusFeature.camera);
  if (target.subject == ShotSubject.pass && mode == ProMode.photo && target.event != null) {
    return openCatchIt(context, target.event!);
  }
  return Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true, builder: (_) => ProCameraScreen(target: target, mode: mode)));
}

class ProCameraScreen extends ConsumerStatefulWidget {
  const ProCameraScreen({
    super.key,
    required this.target,
    this.mode = ProMode.photo,
    this.backend,
    this.encoder,
    this.orientationStream,
    this.clock,
    this.tempDir,
  });

  final ShotTarget target;
  final ProMode mode;

  /// Injected in tests; otherwise LookUp's own camera, or the plugin's.
  final CaptureBackend? backend;
  final VideoEncoder? encoder;
  final Stream<List<double>>? orientationStream;
  final DateTime Function()? clock;

  /// Where the clip is written; the app's temporary folder by default.
  final String? tempDir;

  @override
  ConsumerState<ProCameraScreen> createState() => _ProCameraState();
}

enum _Phase { opening, aim, timer, shooting, armed, finishing, done, failed }

class _ProCameraState extends ConsumerState<ProCameraScreen> {
  late ProMode _mode = widget.mode;
  _Phase _phase = _Phase.opening;
  String? _error;

  CaptureBackend? _backend;
  CameraCaps? _caps;
  ShotPlan? _plan;
  TimelapsePlan? _tl;
  CaptureOverrides _overrides = const CaptureOverrides();

  /// Stops the plan is nudged by, from what the frames show (Auto only).
  double _autoStops = 0;
  ExposureCheck _check = ExposureCheck.good;
  DateTime _lastCheck = DateTime(2000);

  StreamSubscription<CaptureFrame>? _framesSub;
  StreamSubscription<List<double>>? _rotSub;
  List<double>? _r;
  final _recent = <({DateTime t, SkyDir d})>[];
  double _decl = 0;
  late double _lat, _lon;

  // Photo
  int _countdown = 0;
  Timer? _ticker;
  FrameStack? _stack;
  Uint8List? _lastY;
  int _meteors = 0;
  int _rotation = 0;

  // Timelapse
  TimelapseRunner? _runner;

  // Result
  Uint8List? _png;
  String _resultWords = '';

  DateTime _now() => (widget.clock?.call() ?? DateTime.now()).toUtc();

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _framesSub?.cancel();
    _rotSub?.cancel();
    final b = _backend;
    if (b != null) {
      unawaited(b.keepAwake(false));
      unawaited(b.close());
    }
    unawaited(_runner?.cancel());
    super.dispose();
  }

  Future<void> _open() async {
    final s = ref.read(settingsProvider).value;
    _lat = s?.latitude ?? 0;
    _lon = s?.longitude ?? 0;
    _decl = declinationDeg(_lat, _lon, _now());
    final rot = widget.orientationStream ?? _safeRotation();
    _rotSub = rot?.listen(_onRotation);
    try {
      final given = widget.backend;
      if (given != null) {
        _caps = await given.open();
        _backend = given;
      } else {
        try {
          final n = NativeCapture();
          _caps = await n.open();
          _backend = n;
        } on CaptureUnavailable catch (x) {
          if (x.reason == 'denied') rethrow;
          final p = PluginCapture();
          _caps = await p.open();
          _backend = p;
        }
      }
      _replan();
      _framesSub = _backend!.frames.listen(_onFrame);
      await _stream();
      await _backend!.keepAwake(true);
      if (mounted) setState(() => _phase = _Phase.aim);
    } on CaptureUnavailable catch (x) {
      _fail(x.reason == 'denied' ? 'Camera access is off. Turn it on in Settings to take the picture.' : 'The camera didn\'t start.');
    } catch (_) {
      _fail('The camera didn\'t start.');
    }
  }

  Stream<List<double>>? _safeRotation() {
    try {
      return deviceRotation();
    } catch (_) {
      return null;
    }
  }

  void _fail(String why) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = why;
    });
  }

  /// The plan for now: the sky's brightness from the site, the Sun and the
  /// Moon; the timelapse's window and framing; Pro choices and the
  /// exposure fixes from the frames on top.
  void _replan() {
    final caps = _caps;
    if (caps == null) return;
    final now = _now();
    final s = ref.read(settingsProvider).value;
    final sqm = skySqm(
      siteSqm: s == null ? 19.8 : typicalSqm(s.skyDarkness),
      sunAltDeg: sunHorizontal(now, _lat, _lon).altitudeDeg,
      moonIllumination: moonIllumination(now),
      moonAltDeg: moonHorizontal(now, _lat, _lon).altitudeDeg,
    );
    // A pass's timelapse is exposed like star trails: its streak draws itself.
    final subject = widget.target.subject == ShotSubject.pass ? ShotSubject.trails : widget.target.subject;
    _tl = _mode == ProMode.timelapse ? _planTimelapse(caps) : null;
    final lens = _overrides.lensId ?? _tl?.framing?.lens.id;
    final base = planShot(
      subject: subject,
      caps: caps,
      sqm: sqm,
      moonIllumination: moonIllumination(now),
      overrides: CaptureOverrides(shutterS: _overrides.shutterS, iso: _overrides.iso, lensId: lens),
    );
    final manualChoice = _overrides.shutterS != null || _overrides.iso != null;
    _plan = !base.manual || manualChoice || _autoStops == 0
        ? base
        : ShotPlan(
            subject: base.subject,
            lens: base.lens,
            exposure: adjustExposure(base.exposure, _autoStops, caps, maxShutterS: subject == ShotSubject.moon ? 1 / 30 : null),
            manual: base.manual,
            stack: base.stack,
            frames: base.frames,
            keep: base.keep,
            selfTimer: base.selfTimer,
            whiteBalanceK: base.whiteBalanceK,
            tips: base.tips,
            overridden: base.overridden,
          );
  }

  TimelapsePlan? _planTimelapse(CameraCaps caps) {
    final t = widget.target;
    final now = _now();
    final e = t.event;
    final window = timelapseWindow(
      now: now,
      eventStart: e?.start,
      eventEnd: e?.end,
      altitudeAt: e == null ? (u) => t.position(u).altitudeDeg : null,
      nightEnd: ref.read(tonightSkyProvider).value?.window?.end,
    );
    if (window == null) return null;
    final step = t.subject == ShotSubject.pass ? const Duration(seconds: 10) : const Duration(minutes: 10);
    final path = t.path ??
        [
          for (var u = window.start; !u.isAfter(window.end); u = u.add(step))
            (t: u, d: SkyDir(t.position(u).azimuthDeg, t.position(u).altitudeDeg)),
        ];
    return planTimelapse(start: window.start, end: window.end, shutterS: 1, path: path, lenses: caps.lenses);
  }

  /// Streams frames at the plan's exposure (the phone's own when it can't).
  Future<void> _stream() async {
    final b = _backend, p = _plan;
    if (b == null || p == null) return;
    await b.stop().catchError((_) {});
    await b.startWith(lensId: p.lens.id, exposure: p.manual ? p.exposure : null);
  }

  void _onRotation(List<double> r) {
    final now = DateTime.now();
    final d = cameraDirection(r, declinationDeg: _decl);
    _recent
      ..add((t: now, d: d))
      ..removeWhere((x) => now.difference(x.t) > const Duration(milliseconds: 1500));
    if (mounted) setState(() => _r = r);
  }

  void _onFrame(CaptureFrame f) {
    _rotation = f.rotation;
    final now = _now();
    switch (_phase) {
      case _Phase.aim:
        // Watch the exposure while aiming, and fix it in Auto.
        if (DateTime.now().difference(_lastCheck) < const Duration(milliseconds: 1500)) break;
        _lastCheck = DateTime.now();
        final c = checkExposure(f.y, _plan?.subject ?? widget.target.subject);
        final auto = _plan != null && _plan!.manual && !_plan!.overridden;
        if (c.verdict != ExposureVerdict.good && auto) {
          _autoStops = (_autoStops + c.stops * 0.7).clamp(-6.0, 4.0);
          _replan();
          unawaited(_stream());
        }
        if (mounted) setState(() => _check = c);
      case _Phase.shooting:
        final s = _stack ??= FrameStack(_plan!.stack, f.width, f.height, keep: _plan!.keep);
        if (_plan!.subject == ShotSubject.meteors && _lastY != null && caughtStreak(_lastY!, f.y, f.width)) _meteors++;
        _lastY = f.y;
        s.add(f.y, u: f.u, v: f.v);
        if (s.frames >= _plan!.frames) {
          unawaited(_finishPhoto());
        } else if (mounted) {
          setState(() {});
        }
      case _Phase.armed:
        final r = _runner;
        if (r == null) break;
        unawaited(r.onFrame(f, now).then((_) {
          if (!mounted) return;
          if (r.stage(_now()) == TimelapseStage.done) {
            unawaited(_finishTimelapse());
          } else {
            setState(() {});
          }
        }));
      default:
        break;
    }
  }

  // MARK: Photo

  void _takePhoto() {
    final p = _plan;
    if (p == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _phase = _Phase.timer;
      _countdown = p.selfTimer.inSeconds;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_countdown <= 1) {
        t.cancel();
        HapticFeedback.lightImpact();
        setState(() {
          _stack = null;
          _lastY = null;
          _meteors = 0;
          _phase = _Phase.shooting;
        });
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _finishPhoto() async {
    if (_phase != _Phase.shooting) return;
    final s = _stack;
    if (s == null || s.frames == 0) {
      setState(() => _phase = _Phase.aim);
      return;
    }
    setState(() => _phase = _Phase.finishing);
    final img = s.rgba(quarterTurns: _rotation ~/ 90);
    await _save(img.rgba, img.width, img.height,
        words: switch (_plan!.subject) {
          ShotSubject.meteors when _meteors > 0 => 'Saved to Photos, with $_meteors meteor${_meteors == 1 ? '' : 's'} caught. It\'s in your Log.',
          _ => 'Saved to Photos. It\'s in your Log.',
        });
  }

  // MARK: Timelapse

  Future<void> _armTimelapse() async {
    final tl = _tl;
    if (tl == null) return;
    var dir = widget.tempDir;
    if (dir == null) {
      try {
        dir = (await getTemporaryDirectory()).path;
      } catch (_) {
        dir = Directory.systemTemp.path;
      }
    }
    if (!mounted) return;
    final path = '$dir/lookup-timelapse-${DateTime.now().millisecondsSinceEpoch}.mp4';
    setState(() {
      _runner = TimelapseRunner(plan: tl, encoder: widget.encoder ?? const PlatformVideoEncoder(), videoPath: path);
      _phase = _Phase.armed;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_runner?.stage(_now()) == TimelapseStage.done) {
        unawaited(_finishTimelapse());
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _finishTimelapse() async {
    final r = _runner;
    if (r == null || _phase != _Phase.armed) return;
    _ticker?.cancel();
    setState(() => _phase = _Phase.finishing);
    final out = await r.finish();
    if (out.frames == 0) {
      setState(() {
        _phase = _Phase.done;
        _resultWords = 'Stopped before it began: nothing was recorded.';
      });
      return;
    }
    final library = ref.read(photoLibraryProvider);
    if (out.videoPath != null && mounted) await askAboutPhotos(context, ref);
    if (!mounted) return;
    final s = ref.read(settingsProvider).value;
    final video = out.videoPath != null &&
        (await library.saveVideo(out.videoPath!, title: _title(widget.target.name), at: _now(), lat: s?.latitude, lon: s?.longitude)).toPhotos;
    final t = out.trail;
    final words = video
        ? 'The ${out.videoSeconds.round()}-second timelapse is in your Photos, with the trail picture. It\'s in your Log.'
        : 'This phone can\'t make the video yet, so here is the whole timelapse in one picture. It\'s in Photos and your Log.';
    if (t == null) {
      setState(() {
        _phase = _Phase.done;
        _resultWords = words;
      });
      return;
    }
    await _save(t.rgba, t.width, t.height, words: words);
  }

  /// Captions and saves a picture: to Photos, to LookUp's copy, and the
  /// sighting to the Log (a picture of it is a catch).
  Future<void> _save(Uint8List rgba, int width, int height, {required String words}) async {
    final now = _now();
    final s = ref.read(settingsProvider).value;
    final place = s?.placeName;
    final png = await captionedPng(rgba, width, height,
        title: _title(widget.target.name),
        line: '${fmtDay(now)} · ${fmtTime(now)}${place == null ? '' : ' · $place'}',
        caption: FreePlan.caption(isPlus: s?.isPlus ?? false, wanted: s?.photoCaption ?? true));
    if (png == null || !mounted) return _fail('Couldn\'t make the picture.');
    final e = widget.target.asEvent(now, _lat, _lon);
    final saved = await keepCatch(context, ref, event: e, png: png, title: _title(widget.target.name), at: now, place: place);
    if (!mounted) return;
    setState(() {
      _png = png;
      _phase = _Phase.done;
      _resultWords = saved.toPhotos ? words : '$words (Allow Photos for LookUp in Settings to keep it in Photos too.)';
    });
    HapticFeedback.heavyImpact();
  }

  static String _title(String name) => name.isEmpty ? name : '${name[0].toUpperCase()}${name.substring(1)}';

  void _setMode(ProMode m) {
    if (m == _mode || (_phase != _Phase.aim)) return;
    setState(() {
      _mode = m;
      _autoStops = 0;
      _replan();
    });
    unawaited(_stream());
  }

  // MARK: Pro sheet

  Future<void> _showPro() async {
    final caps = _caps;
    if (caps == null || _plan == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: LookUpColors.panel,
      builder: (context) => StatefulBuilder(builder: (context, set) {
        final p = _plan!;
        void pick(CaptureOverrides o) {
          _overrides = o;
          _autoStops = 0;
          _replan();
          unawaited(_stream());
          set(() {});
          setState(() {});
        }

        Widget chips<T>(String title, List<(String, T)> options, T current, CaptureOverrides Function(T) choose) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: LookUpColors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final (label, v) in options)
                    ChoiceChip(label: Text(label), selected: v == current, onSelected: (_) => pick(choose(v))),
                ]),
              ]),
            );

        final moonish = p.subject == ShotSubject.moon || p.subject == ShotSubject.planet;
        final shutters = moonish
            ? const [1 / 4000, 1 / 2000, 1 / 1000, 1 / 500, 1 / 250, 1 / 125, 1 / 60, 1 / 30, 1 / 8, 1 / 2]
            : const [1 / 8, 1 / 4, 1 / 2, 1.0, 2.0, 4.0, 8.0, 15.0, 30.0];
        const isos = [32, 50, 100, 200, 400, 800, 1600, 3200, 6400];
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Camera settings', style: display(22, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(p.detail, key: const Key('pro-detail'), style: numeric(size: 13, color: LookUpColors.grey)),
              const SizedBox(height: 18),
              if (!caps.manual)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text('This phone doesn\'t let apps set the shutter or ISO, so LookUp stacks its quick frames instead.',
                      style: TextStyle(color: LookUpColors.grey, height: 1.4)),
                )
              else ...[
                chips<double>('Shutter, each frame', [
                  for (final v in shutters)
                    if (v >= caps.minShutterS && v <= caps.maxShutterS) (shutterLabel(v), v),
                ], p.exposure.shutterS, (v) => CaptureOverrides(shutterS: v, iso: _overrides.iso, lensId: _overrides.lensId)),
                chips<int>('ISO', [
                  for (final v in isos)
                    if (v >= caps.minIso && v <= caps.maxIso) ('$v', v),
                ], p.exposure.iso, (v) => CaptureOverrides(shutterS: _overrides.shutterS, iso: v, lensId: _overrides.lensId)),
              ],
              if (caps.lenses.length > 1)
                chips<String>('Lens', [for (final l in caps.lenses) ('${l.kind.label} f/${l.fNumber}', l.id)], p.lens.id,
                    (id) => CaptureOverrides(shutterS: _overrides.shutterS, iso: _overrides.iso, lensId: id)),
              Text(
                '${p.apertureWords} Focus stays at infinity, and the colour is set for '
                '${p.whiteBalanceK >= 5000 ? 'sunlight on the Moon' : 'a night sky'}.',
                style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _overrides.any ? () => pick(const CaptureOverrides()) : null,
                child: const Text('Back to automatic'),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // MARK: Layout

  @override
  Widget build(BuildContext context) {
    final p = _plan;
    final screen = MediaQuery.sizeOf(context);
    final r = _r;
    final now = _now();
    final aimAt = _mode == ProMode.timelapse && _tl?.framing != null
        ? _tl!.framing!.center
        : switch (widget.target.position(now)) { final h => SkyDir(h.azimuthDeg, h.altitudeDeg) };
    final camera = r == null ? null : cameraDirection(r, declinationDeg: _decl);
    final g = camera == null ? null : guide(camera, aimAt);
    final held = r == null ? 0 : heldQuarterTurns(r);
    final level = r == null ? null : levelWords(tiltDeg(r, quarterTurns: held));
    final still = isSteady([for (final x in _recent) x.d], toleranceDeg: 0.4);
    final ready = (g?.onTarget ?? false) && level == null && still;
    final onScreen = r == null || p == null
        ? null
        : projectToScreen(r, aimAt, declinationDeg: _decl, previewHeightPx: screen.height, verticalFovDeg: p.lens.longFovDeg);
    final preview = _backend?.preview();
    final guiding = g != null && (_phase == _Phase.aim || (_phase == _Phase.armed && _runner?.stage(now) == TimelapseStage.waiting));
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // The camera's own shape, filling the screen and cropped at the edges.
        if (preview != null)
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(width: screen.width, height: screen.width / (_backend?.portraitAspect ?? 3 / 4), child: preview),
            ),
          ),
        if (guiding)
          Positioned.fill(
            child: PipAim(
              key: const Key('pro-pip'),
              mode: PipMode.find,
              target: onScreen,
              toward: towardOnScreen(g),
              distanceDeg: g.distanceDeg,
              onTarget: g.onTarget,
              words: '${g.words} for ${widget.target.name}',
              ring: false,
            ),
          ),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ScanTopBar(
                title: scanTitle('Pro · ${_title(widget.target.name)}'),
                trailing: CircleButton(
                  tooltip: 'Camera settings',
                  icon: Icons.tune_rounded,
                  onPressed: _phase == _Phase.aim ? _showPro : null,
                ),
              ),
            ),
            if (_phase == _Phase.aim) ...[
              const SizedBox(height: 10),
              SegmentedButton<ProMode>(
                key: const Key('pro-mode'),
                segments: const [
                  ButtonSegment(value: ProMode.photo, label: Text('Photo'), icon: Icon(Icons.photo_camera_rounded)),
                  ButtonSegment(value: ProMode.timelapse, label: Text('Timelapse'), icon: Icon(Icons.timelapse_rounded)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => _setMode(s.first),
              ),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _panel(p, g: g, level: level, still: still, ready: ready, now: now),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _panel(ShotPlan? p, {required Guidance? g, required String? level, required bool still, required bool ready, required DateTime now}) {
    final body = switch (_phase) {
      _Phase.opening => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
      _Phase.failed => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_error ?? 'Something went wrong.', style: const TextStyle(fontSize: 16, height: 1.4)),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Close')),
        ]),
      _Phase.aim => _aimPanel(p!, g: g, level: level, still: still, ready: ready),
      _Phase.timer => Center(
          child: Text('$_countdown', key: const Key('pro-countdown'), style: display(64, weight: FontWeight.w800)),
        ),
      _Phase.shooting => _shootingPanel(p!),
      _Phase.armed => _armedPanel(now),
      _Phase.finishing => const Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Putting it together…'),
        ]),
      _Phase.done => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_png != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 260), child: Image.memory(_png!, fit: BoxFit.contain)),
            ),
          const SizedBox(height: 12),
          Text(_resultWords, key: const Key('pro-result'), style: const TextStyle(fontSize: 15, height: 1.4)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () async {
              final nav = Navigator.of(context);
              final e = widget.target.asEvent(_now(), _lat, _lon);
              if (_png != null) await showCaughtIt(context, e);
              if (mounted) nav.maybePop();
            },
            child: const Text('Done'),
          ),
        ]),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: LookUpColors.line),
      ),
      child: body,
    );
  }

  Widget _aimPanel(ShotPlan p, {required Guidance? g, required String? level, required bool still, required bool ready}) {
    final tl = _tl;
    Widget check(String label, bool ok, {String? why}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Chip(
            avatar: Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 16, color: ok ? LookUpColors.good : LookUpColors.grey),
            label: Text(ok ? label : (why ?? label)),
            visualDensity: VisualDensity.compact,
          ),
        );
    final timelapse = _mode == ProMode.timelapse;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (timelapse && tl == null)
        Text('${_title(widget.target.name)} won\'t be up again tonight, so there\'s nothing to timelapse.',
            style: const TextStyle(fontSize: 15, height: 1.4))
      else ...[
        Text(
          timelapse ? _timelapseWords(tl!) : p.tips.first,
          key: const Key('pro-words'),
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 10),
        Wrap(runSpacing: 4, children: [
          check('Pointed at it', g?.onTarget ?? false, why: g == null ? 'Hold it up' : g.words),
          check('Level', level == null, why: level),
          check('Steady', still, why: timelapse ? 'Prop it up' : 'Hold it still'),
        ]),
        if (_check.verdict != ExposureVerdict.good) ...[
          const SizedBox(height: 8),
          Text(_check.words, key: const Key('pro-advice'), style: const TextStyle(color: LookUpColors.warn, fontSize: 13.5, height: 1.35)),
        ],
        const SizedBox(height: 8),
        // The one place numbers show: tap for the controls.
        InkWell(
          onTap: _showPro,
          child: Text('${timelapse && tl != null ? _timelapseDetail(p, tl) : p.detail} ›',
              style: numeric(size: 12.5, color: LookUpColors.grey)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('pro-go'),
          onPressed: timelapse ? _armTimelapse : _takePhoto,
          icon: Icon(timelapse ? Icons.timelapse_rounded : Icons.camera_rounded),
          label: Text(timelapse ? 'Start the timelapse' : (ready ? 'Take it' : 'Take it anyway')),
        ),
      ],
    ]);
  }

  /// The detail line for a timelapse: the frame's settings and its pace.
  static String _timelapseDetail(ShotPlan p, TimelapsePlan tl) {
    final every = tl.interval.inMilliseconds / 1000;
    final pace = every >= 2 ? '${every.round()} s' : '${every.toStringAsFixed(1)} s';
    return '${shutterLabel(p.exposure.shutterS)} · ISO ${p.exposure.iso} · f/${p.lens.fNumber} · ${p.lens.kind.label} · '
        'a frame every $pace · ${tl.speedUp.round()}× speed';
  }

  String _timelapseWords(TimelapsePlan tl) {
    final hold = tl.framing == null
        ? 'Prop your phone up pointing at it'
        : tl.framing!.landscape
            ? 'Turn your phone on its side and prop it up'
            : 'Prop your phone up, standing upright';
    final aim = tl.framing == null
        ? ''
        : ', pointing ${compassWord(tl.framing!.center.azimuthDeg)}, ${elevationWord(tl.framing!.center.elevationDeg)}';
    final starts = tl.start.isAfter(_now().add(const Duration(minutes: 1)))
        ? 'It starts by itself at ${fmtTime(tl.start)}, when ${widget.target.name} ${widget.target.event == null ? 'is clear of the trees' : 'begins'},'
        : 'It starts as soon as you\'re ready';
    return '$hold$aim. $starts and stops at ${fmtTime(tl.end)}, making a ${tl.clipSeconds.round()}-second clip.';
  }

  Widget _shootingPanel(ShotPlan p) {
    final n = _stack?.frames ?? 0;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        p.subject == ShotSubject.meteors ? 'Watching for meteors · $_meteors caught' : 'Taking it · keep the phone still',
        key: const Key('pro-shooting'),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 10),
      LinearProgressIndicator(value: n / math.max(1, p.frames)),
      const SizedBox(height: 6),
      Text('Frame $n of ${p.frames}', style: numeric(size: 12.5, color: LookUpColors.grey)),
      const SizedBox(height: 10),
      OutlinedButton(onPressed: _finishPhoto, child: Text(n == 0 ? 'Stop' : 'Stop and keep it')),
    ]);
  }

  Widget _armedPanel(DateTime now) {
    final r = _runner!;
    final tl = r.plan;
    final stage = r.stage(now);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        switch (stage) {
          TimelapseStage.waiting => 'Waiting for ${widget.target.name} · starts in ${fmtCountdown(tl.start.difference(now))}',
          TimelapseStage.recording => 'Recording · ${r.kept} of about ${tl.frames} frames',
          TimelapseStage.done => 'Finishing…',
        },
        key: const Key('pro-armed'),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      if (stage == TimelapseStage.recording) LinearProgressIndicator(value: r.kept / math.max(1, tl.frames)),
      const SizedBox(height: 8),
      const Text('Leave the phone where it is. The screen stays on; you can dim it.',
          style: TextStyle(color: LookUpColors.grey, fontSize: 13)),
      const SizedBox(height: 10),
      Row(children: [
        if (stage == TimelapseStage.waiting) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => r.startNow(_now())),
              child: const Text('Start now'),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FilledButton(
            key: const Key('pro-stop'),
            onPressed: () {
              r.stopNow(_now());
              unawaited(_finishTimelapse());
            },
            child: Text(stage == TimelapseStage.waiting ? 'Cancel' : 'Stop'),
          ),
        ),
      ]),
    ]);
  }
}
