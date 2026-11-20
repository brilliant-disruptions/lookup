import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/photo/timelapse_plan.dart';
import 'package:lookup/services/capture/capture_backend.dart';
import 'package:lookup/services/capture/timelapse_encoder.dart';
import 'package:lookup/services/capture/timelapse_runner.dart';

class _Encoder implements VideoEncoder {
  _Encoder({this.can = true});
  final bool can;
  int frames = 0;
  int? rotation;
  bool ended = false, cancelled = false;

  @override
  Future<bool> begin({required String path, required int width, required int height, required int fps, int rotation = 0}) async {
    this.rotation = rotation;
    return can;
  }

  @override
  Future<int> add(CaptureFrame f) async => ++frames;

  @override
  Future<({String path, int frames, double seconds})?> end() async {
    ended = true;
    return (path: '/tmp/clip.mp4', frames: frames, seconds: frames / 30);
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

void main() {
  final t0 = DateTime.utc(2026, 10, 20, 23);
  // Waits 10 min, then records 30 min, one frame every 2 s.
  final plan = planTimelapse(start: t0.add(const Duration(minutes: 10)), end: t0.add(const Duration(minutes: 40)), shutterS: 1, targetClipS: 30);
  CaptureFrame frame(int level, {int x = 0}) {
    final y = Uint8List(8 * 6)..fillRange(0, 48, level);
    y[x] = 255;
    return CaptureFrame(width: 8, height: 6, y: y, rotation: 90);
  }

  test('waits for it to appear, keeps a frame each interval, then stops by itself', () async {
    final enc = _Encoder();
    final r = TimelapseRunner(plan: plan, encoder: enc, videoPath: '/tmp/clip.mp4');
    // Frames every second for the whole hour.
    for (var s = 0; s < 3600; s++) {
      await r.onFrame(frame(20, x: s % 48), t0.add(Duration(seconds: s)));
    }
    expect(plan.interval, const Duration(seconds: 2));
    expect(r.kept, 30 * 60 ~/ 2, reason: 'none before it appears, none after it has gone');
    final out = await r.finish();
    expect(enc.frames, r.kept);
    expect(enc.rotation, 90, reason: 'the clip plays upright');
    expect(out.videoPath, '/tmp/clip.mp4');
    expect(out.trail, isNotNull, reason: 'the trail picture, every time');
    expect(out.trail!.width, 6, reason: 'turned upright');
  });

  test('you can start it early and stop it whenever you like', () async {
    final enc = _Encoder();
    final r = TimelapseRunner(plan: plan, encoder: enc, videoPath: '/tmp/clip.mp4');
    expect(r.stage(t0), TimelapseStage.waiting);
    r.startNow(t0.add(const Duration(minutes: 1)));
    await r.onFrame(frame(20), t0.add(const Duration(minutes: 1)));
    expect(r.kept, 1);
    r.stopNow(t0.add(const Duration(minutes: 2)));
    await r.onFrame(frame(20), t0.add(const Duration(minutes: 3)));
    expect(r.kept, 1);
    expect(r.stage(t0.add(const Duration(minutes: 3))), TimelapseStage.done);
  });

  test('a phone with no video encoder still gets the trail picture', () async {
    final enc = _Encoder(can: false);
    final r = TimelapseRunner(plan: plan, encoder: enc, videoPath: '/tmp/clip.mp4');
    for (var s = 600; s < 700; s++) {
      await r.onFrame(frame(20, x: s % 48), t0.add(Duration(seconds: s)));
    }
    final out = await r.finish();
    expect(r.makingVideo, isFalse);
    expect(enc.ended, isFalse);
    expect(out.videoPath, isNull);
    expect(out.trail, isNotNull);
    expect(out.frames, 50);
  });

  test('cancel drops the clip', () async {
    final enc = _Encoder();
    final r = TimelapseRunner(plan: plan, encoder: enc, videoPath: '/tmp/clip.mp4');
    await r.onFrame(frame(20), t0.add(const Duration(minutes: 11)));
    await r.cancel();
    expect(enc.cancelled, isTrue);
  });
}
