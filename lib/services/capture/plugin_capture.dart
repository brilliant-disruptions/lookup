/// Catch it on phones that won't let apps set the shutter: the camera
/// plugin's own preview frames (auto exposure, about 1/30 s each), shrunk
/// and stacked. Fainter than real long exposures, and the plan says so.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../../domain/photo/camera.dart';
import '../../domain/photo/capture_plan.dart';
import 'capture_backend.dart';

class PluginCapture extends CaptureBackend {
  CameraController? _c;
  final _out = StreamController<CaptureFrame>.broadcast();
  bool _busy = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Frames are shrunk to this on their long side: quick frames are noisy
  /// anyway, and it keeps up ten a second.
  static const longPx = 960;

  @override
  Future<CameraCaps> open() async {
    try {
      final cams = await availableCameras();
      final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull;
      if (back == null) throw const CaptureUnavailable('No back camera on this device');
      final c = CameraController(back, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420);
      await c.initialize();
      _c = c;
      try {
        // A little brighter than the camera thinks: it's metering a dark sky.
        final max = await c.getMaxExposureOffset();
        await c.setExposureOffset(math.min(1.0, max));
      } catch (_) {}
      return CameraCaps.auto;
    } on CameraException catch (e) {
      throw CaptureUnavailable(e.code.contains('Denied') ? 'denied' : 'The camera didn\'t start');
    }
  }

  @override
  double get portraitAspect {
    final s = _c?.value.previewSize;
    return s == null ? 3 / 4 : s.height / s.width;
  }

  @override
  Widget? preview() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return null;
    return CameraPreview(c);
  }

  @override
  Future<void> start(CapturePlan plan) async {
    final c = _c;
    if (c == null) return;
    try {
      await c.setFocusMode(FocusMode.locked);
    } catch (_) {}
    final rotation = c.description.sensorOrientation;
    await c.startImageStream((img) {
      final now = DateTime.now();
      if (_busy || now.difference(_last).inMilliseconds < 100) return;
      _busy = true;
      _last = now;
      try {
        final f = _convert(img, rotation);
        if (f != null) _out.add(f);
      } finally {
        _busy = false;
      }
    });
  }

  CaptureFrame? _convert(CameraImage img, int rotation) {
    final step = math.max(1, (math.max(img.width, img.height) / longPx).ceil());
    final w = (img.width ~/ step) & ~1, h = (img.height ~/ step) & ~1;
    if (w < 2 || h < 2) return null;
    final y = Uint8List(w * h);
    final u = Uint8List((w ~/ 2) * (h ~/ 2)), v = Uint8List((w ~/ 2) * (h ~/ 2));
    if (img.format.group == ImageFormatGroup.bgra8888) {
      final p = img.planes.first;
      final b = p.bytes, rs = p.bytesPerRow;
      for (var row = 0; row < h; row++) {
        for (var col = 0; col < w; col++) {
          final i = row * step * rs + col * step * 4;
          final bb = b[i], g = b[i + 1], r = b[i + 2];
          final l = 0.299 * r + 0.587 * g + 0.114 * bb;
          y[row * w + col] = l.round().clamp(0, 255);
          if (row.isEven && col.isEven) {
            final ci = (row ~/ 2) * (w ~/ 2) + col ~/ 2;
            u[ci] = (128 + 0.564 * (bb - l)).round().clamp(0, 255);
            v[ci] = (128 + 0.713 * (r - l)).round().clamp(0, 255);
          }
        }
      }
    } else if (img.planes.length >= 3) {
      final py = img.planes[0], pu = img.planes[1], pv = img.planes[2];
      final ups = pu.bytesPerPixel ?? 1, vps = pv.bytesPerPixel ?? 1;
      for (var row = 0; row < h; row++) {
        final base = row * step * py.bytesPerRow;
        for (var col = 0; col < w; col++) {
          y[row * w + col] = py.bytes[base + col * step];
        }
      }
      for (var row = 0; row < h ~/ 2; row++) {
        for (var col = 0; col < w ~/ 2; col++) {
          final ci = row * (w ~/ 2) + col;
          final ui = row * step * pu.bytesPerRow + col * step * ups;
          final vi = row * step * pv.bytesPerRow + col * step * vps;
          if (ui < pu.bytes.length) u[ci] = pu.bytes[ui];
          if (vi < pv.bytes.length) v[ci] = pv.bytes[vi];
        }
      }
    } else {
      return null;
    }
    return CaptureFrame(width: w, height: h, y: y, u: u, v: v, rotation: rotation);
  }

  @override
  Stream<CaptureFrame> get frames => _out.stream;

  @override
  Future<void> stop() async {
    final c = _c;
    if (c != null && c.value.isStreamingImages) await c.stopImageStream();
  }

  @override
  Future<void> close() async {
    await stop();
    final c = _c;
    _c = null;
    await c?.dispose();
    await _out.close();
  }
}
