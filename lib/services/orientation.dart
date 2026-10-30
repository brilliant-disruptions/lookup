import 'package:flutter_rotation_sensor/flutter_rotation_sensor.dart';

/// The phone's fused rotation as a row-major device→world matrix (world:
/// x east, y magnetic north, z up), as `domain/finder/pointing.dart` reads
/// it. Null when the platform has no sensor; may throw if it fails to start.
Stream<List<double>>? deviceRotation() {
  if (!RotationSensor.isPlatformSupported) return null;
  RotationSensor.samplingPeriod = SensorInterval.uiInterval;
  RotationSensor.referenceFrame = ReferenceFrame.magneticNorth;
  RotationSensor.coordinateSystem = CoordinateSystem.device();
  return RotationSensor.orientationStream.map((e) {
    final m = e.rotationMatrix;
    return [m.a, m.b, m.c, m.d, m.e, m.f, m.g, m.h, m.i];
  });
}
