import 'package:geolocator/geolocator.dart';

import '../domain/models/settings.dart';

typedef LatLon = ({double lat, double lon});

class LocationService {
  const LocationService();

  Future<bool> requestPermission() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  /// A coarse fix is plenty: pass geometry barely changes over 10 km.
  Future<LatLon?> resolve(LookUpSettings s, {bool allowPrompt = false}) async {
    if (s.locationMode == LocationMode.pinned && s.hasLocation) {
      return (lat: s.latitude!, lon: s.longitude!);
    }
    try {
      final ok = allowPrompt
          ? await requestPermission()
          : switch (await Geolocator.checkPermission()) {
              LocationPermission.always || LocationPermission.whileInUse => true,
              _ => false,
            };
      if (ok) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null &&
            DateTime.now().difference(last.timestamp) < const Duration(hours: 6)) {
          return (lat: last.latitude, lon: last.longitude);
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 20),
          ),
        );
        return (lat: pos.latitude, lon: pos.longitude);
      }
    } catch (_) {
      // fall through to whatever we had
    }
    return s.hasLocation ? (lat: s.latitude!, lon: s.longitude!) : null;
  }
}
