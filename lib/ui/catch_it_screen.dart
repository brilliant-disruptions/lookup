/// Catch it: prop the phone up, point it where LookUp says, and it
/// photographs the pass by itself — many long exposures stacked into one
/// unbroken streak. The plan (lens, framing, shutter, ISO, timing) is
/// domain/photo/capture_plan.dart; the camera is services/capture/.
///
/// Words on the main path, never degrees or settings: those sit behind the
/// detail line, which opens the Pro sheet on phones that allow manual
/// exposure.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/local_store.dart';
import '../domain/finder/pointing.dart';
import '../domain/models/sky_event.dart';
import '../domain/photo/camera.dart';
import '../domain/photo/capture_plan.dart';
import '../domain/photo/exposure.dart';
import '../domain/photo/framing.dart';
import '../domain/sky/astro.dart';
import '../domain/sky/wmm.dart';
import '../services/capture/capture_backend.dart';
import '../services/capture/native_capture.dart';
import '../services/capture/plugin_capture.dart';
import '../services/capture/practice_capture.dart';
import '../services/capture/stack_runner.dart';
import '../services/orientation.dart';
import '../services/photo_store.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'caught_it_screen.dart';
import '../domain/finder/firefly.dart';
import 'pip/pip_aim.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'theme.dart';

Future<void> openCatchIt(BuildContext context, SkyEvent event, {bool practice = false}) =>
    Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => CatchItScreen(event: event, practice: practice)));

enum CatchPhase { opening, aim, capturing, finishing, done, failed }

/// For tests.
abstract final class CatchItScreenTesting {
  static const skyShotLength = _CatchItState.skyShotLength;
}

/// For screenshots: open straight into a phase of the practice run, with
/// [progress] (0–1) of the pass already stacked.
class CatchItDebug {
  const CatchItDebug({required this.phase, this.progress = 0});
  final CatchPhase phase;
  final double progress;
}

class CatchItScreen extends ConsumerStatefulWidget {
  const CatchItScreen({
    super.key,
    required this.event,
    this.practice = false,
    this.backend,
    this.orientationStream,
    this.clock,
    this.debug,
  });

  final SkyEvent event;

  /// Fast-forward over a made-up sky; nothing saved.
  final bool practice;

  /// Injected in tests; otherwise native, then the camera plugin.
  final CaptureBackend? backend;
  final Stream<List<double>>? orientationStream;

  /// Injected in tests.
  final DateTime Function()? clock;
  final CatchItDebug? debug;

  @override
  ConsumerState<CatchItScreen> createState() => _CatchItState();
}

class _CatchItState extends ConsumerState<CatchItScreen> {
  CaptureBackend? _backend;
  CameraCaps? _caps;
  CapturePlan? _plan;
  CaptureOverrides _overrides = const CaptureOverrides();
  List<PathPoint> _path = const [];
  double _mag = 0, _lat = 0, _lon = 0, _decl = 0;
  String? _place;
  CatchPhase _phase = CatchPhase.opening;
  String? _error;

  List<double>? _r;
  final _recent = <SkyDir>[];
  StreamSubscription<List<double>>? _rot;

  StackRunner? _runner;
  StreamSubscription<CaptureFrame>? _frames;
  int _frameTurns = 0, _heldTurns = 0;
  List<double>? _startPose;
  ui.Image? _practiceView, _live, _result;
  DateTime _lastPreview = DateTime.fromMillisecondsSinceEpoch(0);
  bool _previewing = false;
  Timer? _tick;
  bool _saved = false;

  /// A long exposure of the sky right now (the shutter, hours before the
  /// pass): a look at what the camera sees with tonight's settings. Not
  /// the pass, so it's never logged as a sighting.
  bool _skyShot = false;
  DateTime? _skyShotUntil;
  static const skyShotLength = Duration(minutes: 2);

  SkyEvent get e => widget.event;
  bool get _practice => _backend?.isPractice ?? widget.practice;
  DateTime get _now => widget.clock?.call().toUtc() ?? _backend?.now() ?? DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (!widget.practice) {
      final stream = widget.orientationStream ?? _deviceRotation();
      _rot = stream?.listen((r) {
        _r = r;
        _recent.add(cameraDirection(r, declinationDeg: _decl));
        if (_recent.length > 20) _recent.removeAt(0);
      }, onError: (_) {});
    }
    _tick = Timer.periodic(const Duration(milliseconds: 400), (_) => _onTick());
    unawaited(_open());
  }

  Stream<List<double>>? _deviceRotation() {
    try {
      return deviceRotation();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rot?.cancel();
    _frames?.cancel();
    _runner?.dispose();
    unawaited(_backend?.close());
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  // MARK: Camera and plan

  /// Where you are (settings may still be loading when the screen opens).
  Future<void> _locate() async {
    final s = ref.read(settingsProvider).value ?? await ref.read(settingsProvider.future);
    _lat = s?.latitude ?? 0;
    _lon = s?.longitude ?? 0;
    _place = s?.placeName;
    _decl = declinationDeg(_lat, _lon, DateTime.now().toUtc());
    _path = passPath(e, _lat, _lon);
    _mag = typicalMagnitude(e);
  }

  Future<void> _open() async {
    try {
      await _locate();
      final b = widget.backend ?? (widget.practice ? await _practiceBackend() : null);
      if (b != null) {
        _backend = b;
        _caps = await b.open();
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
      await _replan();
      await _backend!.keepAwake(true);
      if (!mounted) return;
      setState(() => _phase = _plan == null ? CatchPhase.failed : CatchPhase.aim);
      if (_plan == null) _error = 'This pass is too low to frame.';
      final d = widget.debug;
      if (d != null && d.phase != CatchPhase.aim) await _debugRun(d);
    } on CaptureUnavailable catch (x) {
      if (!mounted) return;
      setState(() {
        _phase = CatchPhase.failed;
        _error = x.reason == 'denied'
            ? 'Camera access is off. Turn it on in Settings to photograph the pass.'
            : 'The camera didn\'t start. You can still watch it, or try a practice run.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = CatchPhase.failed;
        _error = 'The camera didn\'t start. You can still watch it, or try a practice run.';
      });
    }
  }

  Future<PracticeCapture> _practiceBackend() async {
    var catalog = ref.read(skyCatalogProvider).value;
    if (catalog == null) {
      try {
        catalog = await ref.read(skyCatalogProvider.future).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    return PracticeCapture(path: _path, magnitude: _mag, latDeg: _lat, lonDeg: _lon, catalog: catalog);
  }

  Future<void> _replan() async {
    final caps = _caps;
    if (caps == null) return;
    final darkness = ref.read(settingsProvider).value?.skyDarkness;
    final mid = e.peak;
    final sun = sunHorizontal(mid, _lat, _lon);
    final moon = moonHorizontal(mid, _lat, _lon);
    _plan = planCapture(
      path: _path,
      magnitude: _mag,
      caps: caps,
      siteSqm: darkness == null ? 19.8 : typicalSqm(darkness),
      sunAltDeg: sun.altitudeDeg,
      moonIllumination: moonIllumination(mid),
      moonAltDeg: moon.altitudeDeg,
      overrides: _overrides,
    );
    final plan = _plan;
    final b = _backend;
    if (plan == null || b == null) return;
    if (b is PracticeCapture) {
      b.configure(plan);
      final f = b.frameAt(plan.startAt);
      if (f != null) {
        final r = StackRunner.inline();
        await r.add(f);
        final pic = await r.picture();
        if (pic != null) _practiceView = await _toImage(pic);
      }
    } else {
      try {
        await b.useLens(plan.lens.id);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  /// Screenshots: stack the practice run up to [d.progress] here and now.
  Future<void> _debugRun(CatchItDebug d) async {
    final b = _backend, plan = _plan;
    if (b is! PracticeCapture || plan == null) return;
    final r = StackRunner.inline();
    _runner = r;
    final step = Duration(microseconds: (plan.exposure.shutterS * 1e6).round());
    final until = plan.startAt.add(plan.length * d.progress);
    for (var t = plan.startAt; t.isBefore(until); t = t.add(step)) {
      await r.add(b.frameAt(t)!);
    }
    final pic = await r.picture(maxLongPx: d.phase == CatchPhase.done ? 0 : 720);
    final img = pic == null ? null : await _toImage(pic);
    if (!mounted) return;
    setState(() {
      _phase = d.phase;
      if (d.phase == CatchPhase.done) {
        _result = img;
      } else {
        _live = img;
      }
    });
  }

  void _onTick() {
    if (!mounted) return;
    final plan = _plan;
    final now = _now;
    if (plan != null && widget.debug == null) {
      if (_phase == CatchPhase.aim && !_practice && !now.isBefore(plan.startAt) && now.isBefore(plan.stopAt)) {
        unawaited(_start());
      } else if (_phase == CatchPhase.capturing && !_practice && !now.isBefore(_skyShot ? _skyShotUntil! : plan.stopAt)) {
        unawaited(_finish());
      }
    }
    setState(() {});
  }

  /// The pass is on or about to be: the shutter catches it.
  bool get _passIsOn {
    final plan = _plan;
    if (plan == null) return false;
    final now = _now;
    return plan.startAt.difference(now) < const Duration(minutes: 2) && now.isBefore(plan.stopAt);
  }

  /// The shutter: the pass when it's on, otherwise the sky as it is now.
  Future<void> _shutter() async {
    if (_practice || _passIsOn) return _start();
    _skyShot = true;
    _skyShotUntil = _now.add(skyShotLength);
    await _start();
  }

  /// After a sky shot: back to aiming, still waiting for the pass.
  void _backToAim() {
    _runner?.dispose();
    setState(() {
      _runner = null;
      _live = null;
      _result = null;
      _startPose = null;
      _skyShot = false;
      _skyShotUntil = null;
      _phase = CatchPhase.aim;
    });
  }

  Future<void> _start() async {
    final plan = _plan, b = _backend;
    if (_phase != CatchPhase.aim || plan == null || b == null) return;
    _phase = CatchPhase.capturing;
    final r = _r;
    _heldTurns = _practice ? 0 : (r == null ? (plan.framing.landscape ? 1 : 0) : heldQuarterTurns(r) % 2 == 0 ? 0 : heldQuarterTurns(r));
    _startPose = _practice ? null : (r ?? levelPose(plan.framing.center, quarterTurns: _heldTurns));
    _runner = _practice ? StackRunner.inline() : await StackRunner.isolate();
    _frames = b.frames.listen(_onFrame, onDone: () {
      if (_phase == CatchPhase.capturing) unawaited(_finish());
    });
    unawaited(HapticFeedback.heavyImpact());
    if (mounted) setState(() {});
    try {
      await b.start(plan);
    } catch (_) {
      if (mounted) {
        setState(() {
          _phase = CatchPhase.failed;
          _error = 'The camera stopped. You can still watch it.';
        });
      }
    }
  }

  Future<void> _onFrame(CaptureFrame f) async {
    final r = _runner;
    if (r == null || _phase != CatchPhase.capturing) return;
    if (r.busy) return;
    _frameTurns = ((f.rotation ~/ 90) - _heldTurns) % 4;
    await r.add(f);
    final now = DateTime.now();
    if (_previewing || now.difference(_lastPreview).inMilliseconds < 900) return;
    _previewing = true;
    _lastPreview = now;
    try {
      final pic = await r.picture(quarterTurns: _frameTurns, maxLongPx: 720);
      if (pic != null) {
        final img = await _toImage(pic);
        if (mounted && _phase == CatchPhase.capturing) setState(() => _live = img);
      }
    } finally {
      _previewing = false;
    }
  }

  Future<void> _finish() async {
    if (_phase != CatchPhase.capturing) return;
    setState(() => _phase = CatchPhase.finishing);
    try {
      await _backend?.stop();
    } catch (_) {}
    await _frames?.cancel();
    _frames = null;
    final pic = await _runner?.picture(quarterTurns: _frameTurns);
    final img = pic == null ? null : await _toImage(pic);
    unawaited(HapticFeedback.heavyImpact());
    if (!mounted) return;
    setState(() {
      _result = img ?? _live;
      _phase = CatchPhase.done;
    });
  }

  static Future<ui.Image> _toImage(StackImage s) async {
    final buf = await ui.ImmutableBuffer.fromUint8List(s.rgba);
    final desc = ui.ImageDescriptor.raw(buf, width: s.width, height: s.height, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    buf.dispose();
    return frame.image;
  }

  // MARK: Keeping it

  String get _photoTitle => _skyShot ? 'The sky tonight' : eventTitle(e);
  DateTime get _photoTime => _skyShot ? (_skyShotUntil ?? _now).subtract(skyShotLength) : e.start;
  String get _caption => '$_photoTitle · ${fmtTime(_photoTime)}${_place == null ? '' : ' · $_place'}';

  /// The picture with its caption along the bottom, as a PNG.
  Future<List<int>?> _png() async {
    final img = _result;
    if (img == null) return null;
    final w = img.width.toDouble(), h = img.height.toDouble();
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawImage(img, Offset.zero, Paint());
    final band = h * 0.16;
    c.drawRect(
        Rect.fromLTWH(0, h - band, w, band),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, h - band), Offset(0, h), [const Color(0x00000000), const Color(0xB0000000)]));
    final unit = math.min(w, h) / 30;
    void text(String s, Offset at, double size, FontWeight weight, Color color, {bool right = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: display(size, weight: weight, color: color)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w * 0.7);
      tp.paint(c, right ? at - Offset(tp.width, 0) : at);
    }

    text(_photoTitle, Offset(unit, h - unit * 3.4), unit * 1.15, FontWeight.w700, Colors.white);
    text('${fmtDay(_photoTime)} · ${fmtTime(_photoTime)}${_place == null ? '' : ' · $_place'}', Offset(unit, h - unit * 1.9),
        unit * 0.8, FontWeight.w500, const Color(0xCCFFFFFF));
    text('LookUp', Offset(w - unit, h - unit * 1.9), unit * 0.8, FontWeight.w700, const Color(0xCCFFFFFF), right: true);
    final out = await rec.endRecording().toImage(img.width, img.height);
    final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<void> _keep() async {
    final bytes = await _png();
    if (bytes == null || !mounted) return;
    try {
      final name = await const PhotoStore().saveBytes(e.id, bytes);
      final store = ref.read(storeProvider);
      await store.addFeedback(SeenFeedback.forEvent(e, seen: true, place: _place));
      await store.setPhoto(e.id, name);
      ref.invalidate(skyLogProvider);
      setState(() => _saved = true);
      if (mounted) await showCaughtIt(context, e);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t save the picture.')));
    }
  }

  Future<void> _share() async {
    final bytes = await _png();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/lookup-catch-${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')], text: '$_caption, photographed with LookUp'));
  }

  // MARK: Pro sheet

  Future<void> _showPro() async {
    final caps = _caps, plan = _plan;
    if (caps == null || plan == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: LookUpColors.panel,
      builder: (context) => StatefulBuilder(builder: (context, set) {
        final p = _plan!;
        Future<void> pick(CaptureOverrides o) async {
          _overrides = o;
          await _replan();
          set(() {});
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

        if (!caps.manual) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Text(
                'This phone doesn\'t let apps set the shutter or ISO, so LookUp stacks its quick frames instead. '
                'The streak will be fainter than on phones that do.',
                style: TextStyle(color: LookUpColors.grey, height: 1.4)),
          );
        }
        const shutters = [1 / 8, 1 / 4, 1 / 2, 1.0, 1.5, 2.0];
        const isos = [200, 400, 800, 1600, 3200];
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Camera settings', style: display(22, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(p.detail, style: numeric(size: 13, color: LookUpColors.grey)),
              const SizedBox(height: 18),
              chips<double>('Shutter, each frame', [
                for (final s in shutters)
                  if (s >= caps.minShutterS && s <= caps.maxShutterS) (shutterLabel(s), s),
              ], p.exposure.shutterS, (s) => CaptureOverrides(shutterS: s, iso: _overrides.iso, lensId: _overrides.lensId)),
              chips<int>('ISO', [
                for (final i in isos)
                  if (i >= caps.minIso && i <= caps.maxIso) ('$i', i),
              ], p.exposure.iso, (i) => CaptureOverrides(shutterS: _overrides.shutterS, iso: i, lensId: _overrides.lensId)),
              if (caps.lenses.length > 1)
                chips<String>('Lens', [for (final l in caps.lenses.where((l) => l.kind != LensKind.tele)) (l.kind.label, l.id)],
                    p.lens.id, (id) => CaptureOverrides(shutterS: _overrides.shutterS, iso: _overrides.iso, lensId: id)),
              Text(
                'A longer shutter brightens the sky, not the streak: the satellite crosses each pixel in a blink. '
                'ISO brightens both. ${p.outlookWords}',
                style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: p.overridden ? () => pick(const CaptureOverrides()) : null,
                child: const Text('Back to automatic'),
              ),
            ]),
          ),
        );
      }),
    );
  }

  // MARK: Layout

  /// Which way the words face: with the phone, like a camera app.
  int get _contentTurns {
    if (_practice) return 0;
    if (_phase == CatchPhase.capturing || _phase == CatchPhase.finishing || _phase == CatchPhase.done) return _heldTurns;
    final r = _r ?? (_plan == null ? null : levelPose(_plan!.framing.center, quarterTurns: _plan!.framing.landscape ? 1 : 0));
    if (r == null) return 0;
    final t = heldQuarterTurns(r);
    return t == 2 ? 0 : t;
  }

  /// The live camera fills a box fixed to the phone (it turns with it).
  bool get _deviceMode => !_practice && (_phase == CatchPhase.opening || _phase == CatchPhase.aim);

  @override
  Widget build(BuildContext context) {
    final turns = _contentTurns;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, area) {
          // The camera's box in the phone's own frame: as wide as the
          // screen, at most 60% of its height.
          final aspect = _backend?.portraitAspect ?? 3 / 4;
          final bw = math.min(area.maxWidth, area.maxHeight * 0.5 * aspect);
          final device = Size(bw, bw / aspect);
          return Stack(children: [
            if (_deviceMode)
              Center(
                child: SizedBox.fromSize(
                  size: device,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(fit: StackFit.expand, children: [
                      const ColoredBox(color: Color(0xFF05070C)),
                      if (_backend?.preview() case final p?)
                        FittedBox(
                            fit: BoxFit.cover,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(width: device.width, height: device.height, child: p))
                      else if (_practiceView case final img?)
                        RawImage(image: img, fit: BoxFit.cover),
                      if (_plan != null) CustomPaint(painter: _aimPainter(device, turns)),
                      if (_plan != null && _phase == CatchPhase.aim) _pip(device),
                    ]),
                  ),
                ),
              ),
            Positioned.fill(
              child: RotatedBox(
                quarterTurns: turns,
                child: LayoutBuilder(builder: (context, c) {
                  final hole = _deviceMode ? (turns.isOdd ? Size(device.height, device.width) : device) : _holeFor(c);
                  return _chrome(context, c, hole);
                }),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  /// The picture's box when it's drawn upright with the words: the
  /// practice sky, the streak building, the result.
  Size _holeFor(BoxConstraints c) {
    final img = _result ?? _live ?? _practiceView;
    final aspect = img != null
        ? img.width / img.height
        : (_plan == null ? 3 / 4 : (_plan!.framing.widthFovDeg / _plan!.framing.heightFovDeg));
    final wide = c.maxWidth > c.maxHeight;
    final maxW = wide ? c.maxWidth * 0.62 : c.maxWidth - 24;
    final maxH = wide ? c.maxHeight - 24 : c.maxHeight * 0.5;
    var w = maxW, h = w / aspect;
    if (h > maxH) {
      h = maxH;
      w = h * aspect;
    }
    return Size(w, h);
  }

  CustomPainter _aimPainter(Size device, int turns) {
    final plan = _plan!;
    final r = _r ?? levelPose(plan.framing.center, quarterTurns: plan.framing.landscape ? 1 : 0);
    return _PathPainter(
      at: (d) {
        final p = projectToScreen(r, d,
            declinationDeg: _decl, previewHeightPx: device.height, verticalFovDeg: plan.lens.longFovDeg);
        return p == null ? null : Offset(p.x, p.y);
      },
      path: _path,
      now: _now,
      labelTurns: turns,
      appears: e.start,
    );
  }

  /// Pip on the spot to frame, the ring in the middle of the live picture:
  /// the same Pip as the finder, so the same blinks and taps.
  Widget _pip(Size device) {
    final plan = _plan!;
    final r = _r ?? levelPose(plan.framing.center, quarterTurns: plan.framing.landscape ? 1 : 0);
    final g = guide(cameraDirection(r, declinationDeg: _decl), plan.framing.center, toleranceDeg: 4);
    return PipAim(
      mode: PipMode.catchIt,
      target: projectToScreen(r, plan.framing.center,
          declinationDeg: _decl, previewHeightPx: device.height, verticalFovDeg: plan.lens.longFovDeg),
      toward: towardOnScreen(g),
      distanceDeg: g.distanceDeg,
      onTarget: g.onTarget,
      words: g.words,
      ringRadius: 26,
    );
  }

  Widget _chrome(BuildContext context, BoxConstraints c, Size hole) {
    final wide = c.maxWidth > c.maxHeight;
    final top = _topPanel(context);
    final bottom = _bottomPanel(context);
    final holeChild = SizedBox.fromSize(size: hole, child: _deviceMode ? null : _picture(hole));
    // The shutter sits in its own row, never scrolled away.
    final shutter = _shutterButton();
    if (wide) {
      return Row(children: [
        Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: SingleChildScrollView(child: top))),
        holeChild,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(children: [
              Expanded(child: SingleChildScrollView(child: bottom)),
              ?shutter,
            ]),
          ),
        ),
      ]);
    }
    return Column(children: [
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 8), child: Align(alignment: Alignment.bottomCenter, child: SingleChildScrollView(child: top)))),
      holeChild,
      // Same share of the height as the top, so the box stays centred over
      // the camera behind it.
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Column(children: [
            Expanded(child: SingleChildScrollView(child: bottom)),
            ?shutter,
          ]),
        ),
      ),
    ]);
  }

  /// The shutter, while aiming, with the practice run beside it.
  Widget? _shutterButton() {
    if (_phase != CatchPhase.aim || _plan == null) return null;
    final shutter = _ShutterButton(
      onPressed: _shutter,
      label: _practice
          ? 'Start the practice run'
          : _passIsOn
              ? 'Start catching it'
              : 'Long exposure now',
    );
    if (_practice) return shutter;
    const side = 76.0;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: side,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 14),
          CircleButton(
            tooltip: 'Practice run',
            icon: Icons.fast_forward_rounded,
            size: 46,
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => CatchItScreen(event: e, practice: true))),
          ),
          const SizedBox(height: 8),
          const Text('Practice', style: TextStyle(color: LookUpColors.grey, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ),
      Expanded(child: shutter),
      const SizedBox(width: side),
    ]);
  }

  /// The practice sky, the streak building or the finished picture.
  Widget _picture(Size hole) {
    final plan = _plan;
    final img = switch (_phase) {
      CatchPhase.done => _result ?? _live,
      CatchPhase.capturing || CatchPhase.finishing => _live ?? _practiceView,
      _ => _practiceView,
    };
    final overlay = plan == null || _phase == CatchPhase.done
        ? null
        : _PathPainter(
            at: _pictureMapper(hole),
            path: _path,
            now: _now,
            labelTurns: 0,
            appears: e.start,
            aheadOnly: _phase != CatchPhase.aim,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0xFF05070C)),
        if (img != null) RawImage(image: img, fit: BoxFit.cover),
        if (overlay != null) CustomPaint(painter: overlay),
        if (plan != null && _phase == CatchPhase.aim)
          if (_pictureMapper(hole)(plan.framing.center) case final t?)
            PipAim(
              mode: PipMode.catchIt,
              target: (x: t.dx, y: t.dy),
              toward: (x: 0, y: 0),
              distanceDeg: 0,
              onTarget: true,
              words: 'The spot to frame',
              ringRadius: 26,
            ),
        if (_phase == CatchPhase.finishing) const Center(child: CircularProgressIndicator()),
      ]),
    );
  }

  /// Sky → the upright picture's box (offset from its centre).
  Offset? Function(SkyDir) _pictureMapper(Size hole) {
    final plan = _plan!;
    final pose = _startPose;
    if (pose == null) {
      return (d) {
        final p = plan.framing.toPicture(d);
        return p == null ? null : Offset((p.x - 0.5) * hole.width, (p.y - 0.5) * hole.height);
      };
    }
    // Real capture: where the phone was actually pointing when it started.
    final long = math.max(hole.width, hole.height);
    return (d) {
      final p = projectToScreen(pose, d, declinationDeg: _decl, previewHeightPx: long, verticalFovDeg: plan.lens.longFovDeg);
      if (p == null) return null;
      return switch (_heldTurns % 4) {
        1 => Offset(p.y, -p.x),
        3 => Offset(-p.y, p.x),
        _ => Offset(p.x, p.y),
      };
    };
  }

  Widget _topPanel(BuildContext context) {
    final plan = _plan;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        CircleButton(tooltip: 'Close', icon: Icons.close_rounded, onPressed: () => Navigator.of(context).pop()),
        // Shrinks to fit when the phone is on its side and the panel is narrow.
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _practice
                  ? const Pill('Practice run', icon: Icons.fast_forward_rounded, color: LookUpColors.blue)
                  : const Text('Catch it', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: LookUpColors.grey)),
            ),
          ),
        ),
        CircleButton(
          tooltip: 'Camera settings',
          icon: Icons.tune_rounded,
          onPressed: plan != null && _phase == CatchPhase.aim ? _showPro : null,
        ),
      ]),
      const SizedBox(height: 14),
      Text(_headline, textAlign: TextAlign.center, style: display(26, weight: FontWeight.w700, height: 1.1)),
      const SizedBox(height: 6),
      Text(_subline, textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.grey, fontSize: 14.5, height: 1.35)),
    ]);
  }

  String get _headline => switch (_phase) {
        CatchPhase.opening => 'Getting the camera ready',
        CatchPhase.aim => _practice ? 'Try it before it\'s real' : eventTitle(e),
        CatchPhase.capturing => _skyShot ? 'Long exposure' : 'Catching it',
        CatchPhase.finishing => 'Putting it together',
        CatchPhase.done => _practice ? 'That\'s how it\'ll look' : (_skyShot ? 'Your sky right now' : 'You caught it'),
        CatchPhase.failed => 'No photo this time',
      };

  String get _subline {
    final plan = _plan;
    return switch (_phase) {
      CatchPhase.opening => 'One moment.',
      CatchPhase.aim when plan != null => _practice
          ? 'The real plan for ${fmtTime(e.start)}, in fast-forward over a made-up sky.'
          : '${plan.holdWords}. ${plan.aimWords}. ${plan.outlookWords}',
      CatchPhase.capturing => _skyShot
          ? 'Leave the phone where it is. The stars build up as it goes.'
          : 'Leave the phone where it is. The streak grows as it crosses.',
      CatchPhase.finishing => 'Stacking ${_runner?.frames ?? 0} frames into one.',
      CatchPhase.done => _practice
          ? 'A practice run: nothing was saved.'
          : _skyShot
              ? 'Tonight\'s settings, on the sky as it is now. The pass is at ${fmtTime(e.start)}.'
              : _caption,
      _ => _error ?? '',
    };
  }

  Widget _bottomPanel(BuildContext context) {
    final plan = _plan;
    final now = _now;
    final children = <Widget>[];
    switch (_phase) {
      case CatchPhase.aim when plan != null:
        final over = !now.isBefore(plan.stopAt);
        if (!_practice) {
          final (words, hint, ready) = _guidance(plan);
          children.add(Text(words,
              textAlign: TextAlign.center,
              style: display(22, weight: FontWeight.w700, color: ready ? LookUpColors.good : LookUpColors.white)));
          if (hint != null) {
            children.add(const SizedBox(height: 4));
            children.add(Text(hint, textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.grey, fontSize: 14)));
          }
          children.add(const SizedBox(height: 6));
          children.add(Text(
            over
                ? 'That pass is over.'
                : now.isBefore(plan.startAt)
                    ? 'For the pass, it starts by itself at ${fmtTime(plan.startAt)} (in ${fmtCountdown(plan.startAt.difference(now))}).'
                    : 'Starting…',
            textAlign: TextAlign.center,
            style: numeric(size: 13.5, color: LookUpColors.greyDim),
          ));
        }
      case CatchPhase.capturing || CatchPhase.finishing:
        final until = _skyShot ? _skyShotUntil : plan?.stopAt;
        final left = until == null ? Duration.zero : until.difference(now);
        children.add(Kicker(_skyShot ? 'Long exposure' : 'Catching it', color: LookUpColors.blue, live: true));
        children.add(const SizedBox(height: 6));
        children.add(Center(
            child: CountdownText(_phase == CatchPhase.finishing || left.isNegative ? 'nearly done' : '${fmtCountdown(left)} left', size: 40)));
        children.add(const SizedBox(height: 8));
        children.add(Text('${_runner?.frames ?? 0} frames so far',
            textAlign: TextAlign.center, style: numeric(size: 13, color: LookUpColors.grey)));
        children.add(const SizedBox(height: 14));
        if (_phase == CatchPhase.capturing) {
          children.add(OutlinedButton(onPressed: _finish, child: const Text('Stop and keep what it has')));
        }
      case CatchPhase.done:
        if (_practice) {
          children.add(Text(
              'The real one starts by itself at ${fmtTime(plan?.startAt ?? e.start)}. Prop the phone up a few minutes before.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: LookUpColors.grey, height: 1.4)));
          children.add(const SizedBox(height: 14));
          children.add(FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')));
        } else if (_skyShot) {
          children.add(FilledButton.icon(
              onPressed: _share, icon: const Icon(Icons.ios_share_rounded, size: 18), label: const Text('Share')));
          children.add(const SizedBox(height: 10));
          children.add(OutlinedButton(onPressed: _backToAim, child: const Text('Back to waiting for the pass')));
        } else {
          children.add(FilledButton.icon(
              onPressed: _saved ? null : _keep,
              icon: Icon(_saved ? Icons.check_rounded : Icons.bookmark_add_rounded),
              label: Text(_saved ? 'In your log' : 'Add to your log')));
          children.add(const SizedBox(height: 10));
          children.add(OutlinedButton.icon(
              onPressed: _share, icon: const Icon(Icons.ios_share_rounded, size: 18), label: const Text('Share')));
          children.add(TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')));
        }
      case CatchPhase.failed:
        children.add(FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                fullscreenDialog: true, builder: (_) => CatchItScreen(event: e, practice: true))),
            child: const Text('Try a practice run')));
        children.add(TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')));
      default:
        children.add(const Center(child: CircularProgressIndicator()));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }


  /// What to do next with the phone (a few words), a smaller hint under
  /// it, and whether it's all set.
  (String, String?, bool) _guidance(CapturePlan plan) {
    final r = _r;
    if (r == null) return (plan.aimWords, null, false);
    final g = guide(cameraDirection(r, declinationDeg: _decl), plan.framing.center, toleranceDeg: 4);
    if (!g.onTarget) return (g.words, 'Bring the firefly into the ring', false);
    final level = levelWords(tiltDeg(r, quarterTurns: _contentTurns));
    if (level != null) return (level, null, false);
    if (!isSteady(_recent)) return ('Hold it still', null, false);
    return ('All set. Leave it there', null, true);
  }
}

/// A camera shutter: a white disc in a ring, with what it'll do under it.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onPressed, required this.label});
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.mediumImpact();
            onPressed();
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 74,
              height: 74,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: LookUpColors.white, width: 3.5)),
              child: const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: LookUpColors.white)),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: LookUpColors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

/// The pass drawn over a picture: dashed where it will go, "Appears here",
/// the spot to aim at (the firefly) and the middle of the picture (the
/// ring).
/// [at] maps the sky to offsets from the box's centre.
class _PathPainter extends CustomPainter {
  _PathPainter({
    required this.at,
    required this.path,
    required this.now,
    required this.labelTurns,
    required this.appears,
    this.aheadOnly = false,
  });

  final Offset? Function(SkyDir) at;
  final List<PathPoint> path;
  final DateTime now;
  final int labelTurns;
  final DateTime appears;
  final bool aheadOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    Offset? p(SkyDir d) {
      final o = at(d);
      return o == null ? null : c + o;
    }

    final line = Paint()
      ..color = LookUpColors.blue.withValues(alpha: aheadOnly ? 0.5 : 0.9)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    Offset? first;
    var dash = 0.0;
    for (var i = 1; i < path.length; i++) {
      if (aheadOnly && path[i].t.isBefore(now)) continue;
      final a = p(path[i - 1].d), b = p(path[i].d);
      if (a == null || b == null || (b - a).distance > size.longestSide) continue;
      first ??= a;
      // Dashes: 8 on, 6 off, carried along the path.
      final len = (b - a).distance;
      var s = 0.0;
      while (s < len) {
        final phase = (dash + s) % 14;
        final run = phase < 8 ? math.min(8 - phase, len - s) : math.min(14 - phase, len - s);
        if (phase < 8) canvas.drawLine(a + (b - a) * (s / len), a + (b - a) * ((s + run) / len), line);
        s += run;
      }
      dash += len;
    }
    // Arrowheads every so often, pointing the way it goes.
    for (var i = 6; i < path.length; i += 12) {
      if (aheadOnly && path[i].t.isBefore(now)) continue;
      final a = p(path[i - 1].d), b = p(path[i].d);
      if (a == null || b == null || (b - a).distance < 0.5) continue;
      final dir = (b - a) / (b - a).distance;
      final n = Offset(-dir.dy, dir.dx);
      final tip = b;
      canvas.drawPath(
          Path()
            ..moveTo(tip.dx + dir.dx * 5, tip.dy + dir.dy * 5)
            ..lineTo(tip.dx - dir.dx * 5 + n.dx * 5, tip.dy - dir.dy * 5 + n.dy * 5)
            ..lineTo(tip.dx - dir.dx * 5 - n.dx * 5, tip.dy - dir.dy * 5 - n.dy * 5)
            ..close(),
          Paint()..color = LookUpColors.blue);
    }
    if (!aheadOnly && first != null && first.dx >= 0 && first.dy >= 0 && first.dx <= size.width && first.dy <= size.height) {
      canvas.drawCircle(first, 5, Paint()..color = Colors.white);
      _label(canvas, 'Appears here · ${fmtTime(appears)}', first, size);
    }
  }

  void _label(Canvas canvas, String s, Offset at, Size size) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: const TextStyle(
              fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white,
              shadows: [Shadow(blurRadius: 4, color: Colors.black)])),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(labelTurns * math.pi / 2);
    // Keep it inside the picture: above the point, nudged in from the edges.
    var dx = -tp.width / 2;
    final edge = labelTurns.isOdd ? size.height : size.width;
    final pos = labelTurns.isOdd ? at.dy : at.dx;
    if (pos + dx < 6) dx = 6 - pos;
    if (pos - dx > edge - 6 && pos + tp.width / 2 > edge - 6) dx = edge - 6 - pos - tp.width;
    tp.paint(canvas, Offset(dx, -tp.height - 10));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PathPainter o) => true;
}
