/// "Preview an alert": a full ISS pass played back in ~25 seconds so people
/// can see the whole experience on a night when nothing is up.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/scheduling/alert_planner.dart';
import '../state/providers.dart';
import 'look_sheet.dart';

/// Real seconds of countdown before the pass starts.
const demoLeadSeconds = 8;

/// The 4-minute pass plays this many times faster than real time.
const demoSpeed = 16;

SkyEvent demoEvent(DateTime realStart) {
  final start = realStart.toUtc().add(const Duration(seconds: demoLeadSeconds));
  return SkyEvent(
    id: 'demo:iss',
    type: SkyEventType.iss,
    start: start,
    peak: start.add(const Duration(minutes: 2, seconds: 5)),
    end: start.add(const Duration(minutes: 4, seconds: 10)),
    peakElevationDeg: 64,
    riseAzimuthDeg: 247,
    peakAzimuthDeg: 175,
    setAzimuthDeg: 95,
    cloudCoverPercent: 5,
    details: const {'brightness': 'brighter than any star', 'demo': true},
  );
}

/// Simulated "now": real time until the pass starts, then [demoSpeed]×.
DateTime demoClock(DateTime realStart, DateTime realNow) {
  final elapsed = realNow.difference(realStart);
  const lead = Duration(seconds: demoLeadSeconds);
  if (elapsed <= lead) return realNow;
  final fast = (elapsed - lead) * demoSpeed;
  return realStart.add(lead).add(fast);
}

Future<void> showDemo(BuildContext context, WidgetRef ref) async {
  final realStart = DateTime.now();
  await ref.read(analyticsProvider).log('demo_played');
  final event = demoEvent(realStart);
  // The actual tap people get, so the preview includes the notification.
  try {
    await ref.read(notificationServiceProvider).showNow(
          id: 7,
          title: AlertPlanner.headsUpTitle(event, 10),
          body: AlertPlanner.headsUpBody(event),
          payload: event.id,
        );
  } catch (_) {
    // Notifications not permitted: the sheet still demonstrates the rest.
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ProviderScope(
      overrides: [
        clockProvider.overrideWith((_) => Stream.periodic(
              const Duration(milliseconds: 100),
              (_) => demoClock(realStart, DateTime.now()),
            )),
      ],
      child: LookSheet(event: event, demo: true),
    ),
  );
}
