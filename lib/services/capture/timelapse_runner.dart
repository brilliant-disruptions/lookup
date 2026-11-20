/// Runs a timelapse while the phone sits propped up: waits for the thing to
/// appear, keeps one frame every interval, hands it to the video encoder,
/// and stops by itself when it's gone (or when you stop it). Alongside the
/// video it always builds a trail picture (each pixel's brightest), which
/// is also what you get where the phone has no video encoder yet.
library;

import 'dart:typed_data';

import '../../domain/photo/frame_stack.dart';
import '../../domain/photo/shot_plan.dart' show StackKind;
import '../../domain/photo/timelapse_plan.dart';
import 'capture_backend.dart';
import 'stack_runner.dart' show StackImage;
import 'timelapse_encoder.dart';

class TimelapseResult {
  const TimelapseResult({required this.frames, this.videoPath, this.videoSeconds = 0, this.trail});

  /// Frames kept.
  final int frames;

  /// The clip, when the phone could make one.
  final String? videoPath;
  final double videoSeconds;

  /// Every kept frame's brightest, upright: the night in one picture.
  final StackImage? trail;
}

class TimelapseRunner {
  TimelapseRunner({required this.plan, required this.encoder, required this.videoPath});

  final TimelapsePlan plan;
  final VideoEncoder encoder;
  final String videoPath;

  DateTime? _startedEarly, _stoppedAt, _lastKept;
  int _kept = 0;
  int _rotation = 0;
  FrameStack? _trail;

  /// Null until the first frame: then whether video is being made.
  bool? _video;
  Future<void>? _pending;

  int get kept => _kept;
  bool? get makingVideo => _video;

  TimelapseStage stage(DateTime now) => timelapseStage(now, plan, startedEarly: _startedEarly, stoppedAt: _stoppedAt);

  /// Start now, without waiting for it to appear.
  void startNow(DateTime now) => _startedEarly ??= now.toUtc();

  /// Stop now; [finish] then makes the clip.
  void stopNow(DateTime now) => _stoppedAt ??= now.toUtc();

  /// A frame from the camera at [now]: kept if it's recording and a frame is
  /// due. Frames are handled one at a time, in order.
  Future<void> onFrame(CaptureFrame f, DateTime now) {
    if (stage(now) != TimelapseStage.recording || !keepTimelapseFrame(now, _lastKept, plan.interval)) return Future.value();
    _lastKept = now;
    final before = _pending ?? Future.value();
    return _pending = before.then((_) => _keep(f));
  }

  Future<void> _keep(CaptureFrame f) async {
    _rotation = f.rotation;
    _video ??= await encoder.begin(path: videoPath, width: f.width, height: f.height, fps: plan.fps, rotation: f.rotation);
    if (_video!) {
      try {
        await encoder.add(f);
      } catch (_) {
        _video = false; // keep going with the trail picture
      }
    }
    final t = _trail ??= FrameStack(StackKind.lighten, f.width, f.height);
    t.add(f.y, u: f.u, v: f.v);
    _kept++;
  }

  /// Finishes: the clip (if any) and the trail picture.
  Future<TimelapseResult> finish() async {
    await _pending;
    String? path;
    double seconds = 0;
    if (_video == true) {
      final r = await encoder.end();
      path = r?.path;
      seconds = r?.seconds ?? 0;
    }
    final img = _trail?.rgba(quarterTurns: _rotation ~/ 90);
    return TimelapseResult(
      frames: _kept,
      videoPath: path,
      videoSeconds: seconds,
      trail: img == null ? null : StackImage(Uint8List.fromList(img.rgba), img.width, img.height),
    );
  }

  /// Gives up: no clip, no picture.
  Future<void> cancel() async {
    await _pending;
    if (_video == true) await encoder.cancel();
  }
}
