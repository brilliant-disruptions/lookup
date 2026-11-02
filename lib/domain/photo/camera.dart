/// What the phone's back cameras can do, as the native capture channel
/// reports it (android MainActivity's LookUpCapture, ios LookUpCapture.swift),
/// or a plain guess when the phone won't say. Pure Dart.
library;

import 'dart:math' as math;

enum LensKind {
  ultraWide('Ultra-wide'),
  wide('Main'),
  tele('Telephoto');

  const LensKind(this.label);
  final String label;

  /// From the lens's long-side field of view.
  static LensKind ofFov(double longFovDeg) => longFovDeg >= 90
      ? LensKind.ultraWide
      : longFovDeg < 45
          ? LensKind.tele
          : LensKind.wide;
}

/// One back camera. Fields of view are along the sensor's long and short
/// sides: the long side is the frame's width when the phone is on its side.
class CameraLens {
  const CameraLens({
    required this.id,
    required this.kind,
    required this.longFovDeg,
    required this.shortFovDeg,
    this.fNumber = 1.8,
  });

  /// The platform's camera id.
  final String id;
  final LensKind kind;
  final double longFovDeg, shortFovDeg;
  final double fNumber;

  /// Degrees per pixel along the long side, for a frame [longPx] wide.
  double pixelScaleDeg(int longPx) => longFovDeg / longPx;

  factory CameraLens.fromMap(Map<Object?, Object?> m) {
    final long = (m['longFov'] as num).toDouble();
    return CameraLens(
      id: '${m['id']}',
      kind: LensKind.ofFov(long),
      longFovDeg: long,
      shortFovDeg: (m['shortFov'] as num).toDouble(),
      fNumber: (m['f'] as num?)?.toDouble() ?? 1.8,
    );
  }

  @override
  String toString() => 'CameraLens($id ${kind.label} ${longFovDeg.toStringAsFixed(0)}°×${shortFovDeg.toStringAsFixed(0)}° f/$fNumber)';
}

class CameraCaps {
  const CameraCaps({
    required this.lenses,
    required this.manual,
    this.minShutterS = 1 / 8000,
    this.maxShutterS = 1 / 30,
    this.minIso = 50,
    this.maxIso = 3200,
  });

  /// Back cameras, main first.
  final List<CameraLens> lenses;

  /// True when apps may set shutter and ISO themselves (Android's
  /// MANUAL_SENSOR, AVFoundation's custom exposure).
  final bool manual;
  final double minShutterS, maxShutterS;
  final int minIso, maxIso;

  /// A typical main camera, auto exposure only: what the camera plugin gives.
  static const auto = CameraCaps(
    lenses: [CameraLens(id: '', kind: LensKind.wide, longFovDeg: 66, shortFovDeg: 52)],
    manual: false,
  );

  CameraLens get main => lenses.firstWhere((l) => l.kind == LensKind.wide, orElse: () => lenses.first);

  factory CameraCaps.fromMap(Map<Object?, Object?> m) {
    final lenses = [
      for (final l in (m['lenses'] as List? ?? const []))
        if (l is Map) CameraLens.fromMap(l),
    ]..sort((a, b) => _rank(a).compareTo(_rank(b)));
    if (lenses.isEmpty) return auto;
    return CameraCaps(
      lenses: lenses,
      manual: m['manual'] == true,
      minShutterS: (m['minShutterS'] as num?)?.toDouble() ?? auto.minShutterS,
      maxShutterS: (m['maxShutterS'] as num?)?.toDouble() ?? auto.maxShutterS,
      minIso: (m['minIso'] as num?)?.toInt() ?? auto.minIso,
      maxIso: (m['maxIso'] as num?)?.toInt() ?? auto.maxIso,
    );
  }
}

int _rank(CameraLens l) => switch (l.kind) { LensKind.wide => 0, LensKind.ultraWide => 1, LensKind.tele => 2 };

/// Field of view (degrees) of a [focalMm] lens across [sensorMm].
double fovDeg(double sensorMm, double focalMm) => 2 * math.atan(sensorMm / (2 * focalMm)) * 180 / math.pi;
