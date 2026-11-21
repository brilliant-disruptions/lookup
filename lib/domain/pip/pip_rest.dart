/// When Pip, resting beside the tabs, is sleepy: while the Sun is up
/// (nothing to see yet) and during their quiet hours. Otherwise it's calm.
/// Pure.
library;

import '../models/settings.dart';
import '../sky/astro.dart' show sunHorizontal;

bool pipSleepy({required DateTime now, required LookUpSettings settings}) {
  final l = now.toLocal();
  if (settings.quietHours.contains(l.hour * 60 + l.minute)) return true;
  final lat = settings.latitude, lon = settings.longitude;
  if (lat == null || lon == null) return false;
  return sunHorizontal(now.toUtc(), lat, lon).altitudeDeg > 0;
}
