/// The practice run: the real plan for a real pass, played in fast-forward
/// over a made-up sky (domain/photo/practice_sky.dart) with the stars for
/// your place and time. Nothing it makes is saved or shared as a photo.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/photo/camera.dart';
import '../../domain/photo/capture_plan.dart';
import '../../domain/photo/framing.dart';
import '../../domain/photo/practice_sky.dart';
import '../../domain/sky/catalog.dart';
import 'capture_backend.dart';

/// A phone with a main and an ultra-wide camera and manual exposure: the
/// full Catch it, whatever phone this is.
const practiceCaps = CameraCaps(
  lenses: [
    CameraLens(id: 'main', kind: LensKind.wide, longFovDeg: 69, shortFovDeg: 54, fNumber: 1.8),
    CameraLens(id: 'ultra', kind: LensKind.ultraWide, longFovDeg: 108, shortFovDeg: 88, fNumber: 2.2),
  ],
  manual: true,
  minShutterS: 1 / 8000,
  maxShutterS: 2,
  minIso: 50,
  maxIso: 6400,
);

class PracticeCapture extends CaptureBackend {
  PracticeCapture({
    required this.path,
    required this.magnitude,
    required this.latDeg,
    required this.lonDeg,
    this.catalog,
    this.runSeconds = 14,
    this.width = 540,
  });

  final List<PathPoint> path;
  final double magnitude;
  final double latDeg, lonDeg;
  final SkyCatalog? catalog;

  /// How long the whole pass takes in the practice run.
  final double runSeconds;
  final int width;

  PracticeSky? _sky;
  CapturePlan? _plan;
  final _out = StreamController<CaptureFrame>.broadcast();
  Timer? _timer;
  DateTime? _simNow;
  Widget? _preview;

  PracticeSky? get sky => _sky;

  @override
  bool get isPractice => true;

  @override
  Future<CameraCaps> open() async => practiceCaps;

  /// Builds the made-up sky for [plan]; the preview shows its first frame.
  void configure(CapturePlan plan, {Widget? preview}) {
    _plan = plan;
    _sky = PracticeSky(
      framing: plan.framing,
      path: path,
      magnitude: magnitude,
      exposure: plan.exposure,
      sqm: plan.sqm,
      latDeg: latDeg,
      lonDeg: lonDeg,
      catalog: catalog,
      width: width,
    );
    _simNow = plan.startAt;
    _preview = preview;
  }

  set previewWidget(Widget? w) => _preview = w;

  @override
  double get portraitAspect {
    final s = _sky;
    return s == null ? 3 / 4 : s.width / s.height;
  }

  @override
  Widget? preview() => _preview;

  @override
  DateTime now() => _simNow ?? DateTime.now().toUtc();

  /// One frame at [t], for previews and screenshots.
  CaptureFrame? frameAt(DateTime t) {
    final s = _sky;
    if (s == null) return null;
    final f = s.frameAt(t);
    return CaptureFrame(width: s.width, height: s.height, y: f.y, u: f.u, v: f.v);
  }

  @override
  Future<void> start(CapturePlan plan) async {
    final s = _sky;
    if (s == null) return;
    final shutter = Duration(microseconds: (plan.exposure.shutterS * 1e6).round());
    final frames = plan.frames;
    final tick = Duration(microseconds: (runSeconds * 1e6 / frames).round().clamp(30000, 400000));
    var t = plan.startAt;
    _simNow = t;
    _timer = Timer.periodic(tick, (timer) {
      if (!t.isBefore(plan.stopAt)) {
        timer.cancel();
        _out.close();
        return;
      }
      final f = s.frameAt(t);
      _out.add(CaptureFrame(width: s.width, height: s.height, y: f.y, u: f.u, v: f.v));
      t = t.add(shutter);
      _simNow = t;
    });
  }

  /// True once the run has played to the end.
  bool get finished => _out.isClosed;

  @override
  Stream<CaptureFrame> get frames => _out.stream;

  @override
  Future<void> stop() async {
    _timer?.cancel();
    if (!_out.isClosed) await _out.close();
  }

  @override
  Future<void> close() => stop();

  CapturePlan? get plan => _plan;
}
