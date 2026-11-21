/// Keeps the screen on while Pip is showing the way: a phone that dims and
/// locks ten minutes into waiting for a pass has lost the thing they came
/// out for. Uses the capture channel's own switch (ios/Runner/
/// LookUpCapture.swift, android LookUpCapture.kt); quiet where that isn't
/// there (tests, an older native build).
library;

import 'package:flutter/services.dart';

const _capture = MethodChannel('lookup/capture');

Future<void> keepScreenAwake(bool on) async {
  try {
    await _capture.invokeMethod<void>('keepAwake', {'on': on});
  } on MissingPluginException {
    // Nothing to keep awake here.
  } on PlatformException {
    // The screen sleeping is never worth an error.
  }
}
