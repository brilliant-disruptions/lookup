/// Where Catch it's frames come from. Three cameras behind one shape:
///
///  * [NativeCapture] (native_capture.dart): LookUp's own channel to
///    Camera2 / AVFoundation, with the shutter and ISO the plan chose. Used
///    whenever the phone allows manual exposure.
///  * [PluginCapture] (plugin_capture.dart): the camera plugin's quick
///    auto-exposure frames, for phones that don't (and for iOS until
///    LookUpCapture.swift is in the Runner target).
///  * [PracticeCapture] (practice_capture.dart): a made-up sky running the
///    real plan in fast-forward, for trying it out and for screenshots.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../domain/photo/camera.dart';
import '../../domain/photo/capture_plan.dart';

/// One frame: luma at full size, chroma at half, and how far it must turn
/// clockwise (degrees) to be upright with the phone held upright.
class CaptureFrame {
  const CaptureFrame({required this.width, required this.height, required this.y, this.u, this.v, this.rotation = 0});
  final int width, height;
  final Uint8List y;
  final Uint8List? u, v;
  final int rotation;
}

abstract class CaptureBackend {
  /// Starts the camera for aiming; what it can do.
  Future<CameraCaps> open();

  /// Switches to another back camera (after the plan picks one).
  Future<void> useLens(String id) async {}

  /// The live view, upright with the phone upright, filling its box. Null
  /// while there's nothing to show yet.
  Widget? preview();

  /// Width ÷ height of the frames with the phone upright.
  double get portraitAspect => 3 / 4;

  /// Starts sending frames, exposed as [plan] says (when it can).
  Future<void> start(CapturePlan plan);

  Stream<CaptureFrame> get frames;

  /// Stops the frames; the preview carries on.
  Future<void> stop();

  Future<void> close();

  /// Keep the screen on while the phone sits propped up.
  Future<void> keepAwake(bool on) async {}

  /// The time as this camera sees it: real time, or the practice run's.
  DateTime now() => DateTime.now().toUtc();

  bool get isPractice => false;
}

/// The camera can't do what was asked; try the next one.
class CaptureUnavailable implements Exception {
  const CaptureUnavailable(this.reason);
  final String reason;
  @override
  String toString() => 'CaptureUnavailable: $reason';
}
