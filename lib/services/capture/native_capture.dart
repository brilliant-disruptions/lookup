/// LookUp's own camera channel ("lookup/capture"): manual shutter and ISO,
/// focus at infinity, frames as YUV. Android: LookUpCapture.kt. iOS:
/// LookUpCapture.swift. Where the channel is missing or the camera won't
/// allow manual exposure this throws [CaptureUnavailable] and the camera
/// plugin takes over.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../domain/photo/camera.dart';
import '../../domain/photo/capture_plan.dart';
import 'capture_backend.dart';

class NativeCapture extends CaptureBackend {
  static const _methods = MethodChannel('lookup/capture');
  static const _frames = EventChannel('lookup/capture/frames');

  int? _texture;
  int _sensorOrientation = 90;
  double _aspect = 3 / 4;
  String? _lens;
  Stream<CaptureFrame>? _stream;

  @override
  Future<CameraCaps> open() async {
    final Map<Object?, Object?> raw;
    try {
      raw = (await _methods.invokeMethod<Map<Object?, Object?>>('capabilities')) ?? const {};
    } on MissingPluginException {
      throw const CaptureUnavailable('No native capture on this platform yet');
    }
    final caps = CameraCaps.fromMap(raw);
    if (!caps.manual) throw const CaptureUnavailable('This camera doesn\'t allow manual exposure');
    await _openLens(caps.main.id);
    return caps;
  }

  Future<void> _openLens(String id) async {
    final Map<Object?, Object?> r;
    try {
      r = (await _methods.invokeMethod<Map<Object?, Object?>>('open', {'lensId': id})) ?? const {};
    } on PlatformException catch (e) {
      throw CaptureUnavailable(e.code == 'CameraAccessDenied' ? 'denied' : (e.message ?? 'The camera didn\'t start'));
    }
    _texture = (r['textureId'] as num?)?.toInt();
    _sensorOrientation = (r['sensorOrientation'] as num?)?.toInt() ?? 90;
    final w = (r['width'] as num?)?.toDouble() ?? 4, h = (r['height'] as num?)?.toDouble() ?? 3;
    // The buffer is in the sensor's orientation; upright it's turned.
    _aspect = (_sensorOrientation ~/ 90).isOdd ? h / w : w / h;
    _lens = id;
  }

  @override
  Future<void> useLens(String id) async {
    if (id == _lens || id.isEmpty) return;
    await _openLens(id);
  }

  @override
  double get portraitAspect => _aspect;

  @override
  Widget? preview() {
    final t = _texture;
    if (t == null) return null;
    return RotatedBox(
      quarterTurns: _sensorOrientation ~/ 90,
      child: Texture(textureId: t),
    );
  }

  @override
  Future<void> start(CapturePlan plan) async {
    await useLens(plan.lens.id);
    await _methods.invokeMethod<void>('start', {
      if (plan.manual) 'shutterS': plan.exposure.shutterS,
      if (plan.manual) 'iso': plan.exposure.iso,
      'longPx': captureLongPx,
    });
  }

  @override
  Stream<CaptureFrame> get frames => _stream ??= _frames.receiveBroadcastStream().map((e) {
        final m = e as Map;
        return CaptureFrame(
          width: (m['w'] as num).toInt(),
          height: (m['h'] as num).toInt(),
          y: m['y'] as Uint8List,
          u: m['u'] as Uint8List?,
          v: m['v'] as Uint8List?,
          rotation: (m['rotation'] as num?)?.toInt() ?? _sensorOrientation,
        );
      });

  @override
  Future<void> stop() => _methods.invokeMethod<void>('stop');

  @override
  Future<void> close() async {
    await keepAwake(false);
    await _methods.invokeMethod<void>('close');
    _texture = null;
  }

  @override
  Future<void> keepAwake(bool on) async {
    try {
      await _methods.invokeMethod<void>('keepAwake', {'on': on});
    } on MissingPluginException {
      // Nothing to do.
    }
  }
}
