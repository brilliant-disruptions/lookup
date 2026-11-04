/// When the phone should register for Seen near you wake-ups with the
/// relay, refresh that registration, or withdraw it. Pure rules; the
/// service (lib/services/push_service.dart) does the talking.
library;

import '../models/settings.dart';
import 'seen_nearby.dart';

/// What the phone last told the relay: its push address and the area
/// (the half-degree cell it was in).
typedef PushRecord = ({String token, String area, DateTime at});

/// The relay forgets a phone it hasn't heard from in 30 days; say hello
/// well before that.
const pushRenewEvery = Duration(days: 7);

enum PushStep { subscribe, unsubscribe, nothing }

/// The area a registration is for: the cell you're in. Moving to another
/// cell (a trip, the cabin) re-registers for the cells around there.
String pushArea(double lat, double lon) {
  final c = reportCell(lat, lon);
  return '${c.lat},${c.lon}';
}

/// Wake-ups are wanted only when Seen near you could alert here: the relay
/// is configured, the person turned it on, aurora alerts are on, and the
/// aurora shows here often enough for it to be offered.
bool pushWanted(LookUpSettings s, {required bool relayConfigured}) =>
    relayConfigured &&
    s.seenNearby &&
    s.auroraEnabled &&
    s.latitude != null &&
    s.longitude != null &&
    seenNearbyOffered(s.latitude!, s.longitude!);

PushStep pushStep({
  required bool wanted,
  required String? token,
  required String? area,
  required PushRecord? last,
  required DateTime now,
}) {
  if (!wanted) return last == null ? PushStep.nothing : PushStep.unsubscribe;
  if (token == null || area == null) return PushStep.nothing;
  if (last == null || last.token != token || last.area != area) return PushStep.subscribe;
  return now.difference(last.at) >= pushRenewEvery ? PushStep.subscribe : PushStep.nothing;
}
