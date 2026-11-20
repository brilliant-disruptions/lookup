/// The video side of a timelapse: frames in, an .mp4 out, encoded by the
/// phone ("lookup/timelapse": android LookUpTimelapse.kt, ios
/// LookUpTimelapse.swift). Where the phone has no encoder yet (iPhone until
/// the Swift is in the Xcode target), [begin] says so and the timelapse
/// keeps its trail picture instead.
library;


import 'package:flutter/services.dart';

import 'capture_backend.dart';

abstract class VideoEncoder {
  /// Opens [path] for a clip of [width]×[height] frames at [fps], turned
  /// [rotation]° clockwise to be upright. False when this phone can't.
  Future<bool> begin({required String path, required int width, required int height, required int fps, int rotation = 0});

  /// Adds one frame (I420); the number written so far.
  Future<int> add(CaptureFrame f);

  /// Finishes the file. Null when nothing was recorded.
  Future<({String path, int frames, double seconds})?> end();

  /// Drops the clip and its file.
  Future<void> cancel();
}

class PlatformVideoEncoder implements VideoEncoder {
  const PlatformVideoEncoder();

  static const _ch = MethodChannel('lookup/timelapse');

  @override
  Future<bool> begin({required String path, required int width, required int height, required int fps, int rotation = 0}) async {
    try {
      await _ch.invokeMethod<void>('begin', {
        'path': path,
        // The encoder wants even sides.
        'width': width & ~1,
        'height': height & ~1,
        'fps': fps,
        'rotation': ((rotation % 360) + 360) % 360,
        'bitrate': 12000000,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<int> add(CaptureFrame f) async {
    final w = f.width & ~1, h = f.height & ~1;
    final cw = w ~/ 2, ch = h ~/ 2;
    Uint8List crop(Uint8List src, int srcW, int outW, int outH) {
      if (srcW == outW && src.length == outW * outH) return src;
      final out = Uint8List(outW * outH);
      for (var y = 0; y < outH; y++) {
        out.setRange(y * outW, y * outW + outW, src, y * srcW);
      }
      return out;
    }

    // A frame without colour is grey.
    final u = f.u ?? (Uint8List(cw * ch)..fillRange(0, cw * ch, 128));
    final v = f.v ?? (Uint8List(cw * ch)..fillRange(0, cw * ch, 128));
    final n = await _ch.invokeMethod<int>('add', {
      'y': crop(f.y, f.width, w, h),
      'u': crop(u, f.width ~/ 2, cw, ch),
      'v': crop(v, f.width ~/ 2, cw, ch),
    });
    return n ?? 0;
  }

  @override
  Future<({String path, int frames, double seconds})?> end() async {
    final m = await _ch.invokeMethod<Map<Object?, Object?>>('end');
    if (m == null || m['path'] == null) return null;
    return (path: '${m['path']}', frames: (m['frames'] as num?)?.toInt() ?? 0, seconds: (m['seconds'] as num?)?.toDouble() ?? 0);
  }

  @override
  Future<void> cancel() async {
    try {
      await _ch.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Nothing was open.
    }
  }
}
