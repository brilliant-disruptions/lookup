/// What the buttons on an alert do without opening the app (a background
/// isolate on both platforms), so everything here works from the store
/// alone. Only "Remind me" does anything here now: a sighting goes in the
/// Log only when it's caught with the camera, so the old "Saw it!" logs
/// nothing ("Catch it" opens the app instead).
library;

import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/local_store.dart';
import '../domain/models/sky_event.dart';
import '../domain/scheduling/alert_planner.dart';
import 'notification_service.dart';

/// Entry point for buttons pressed while the app isn't in the foreground.
@pragma('vm:entry-point')
Future<void> onAlertActionInBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  final notifications = NotificationService();
  await notifications.init();
  await handleAlertAction(
    actionId: r.actionId,
    eventId: r.payload,
    store: LocalStore(),
    notifications: notifications,
  );
}

enum AlertActionResult { reminderSet, nothing }

Future<AlertActionResult> handleAlertAction({
  required String? actionId,
  required String? eventId,
  required LocalStore store,
  required NotificationService notifications,
  DateTime? now,
}) async {
  if (eventId == null) return AlertActionResult.nothing;
  final event = await findStoredEvent(store, eventId);
  if (event == null) return AlertActionResult.nothing;
  switch (actionId) {
    case AlertAction.snooze:
      final reminder = AlertPlanner.snooze(event, now ?? DateTime.now(), miles: (await store.loadSettings()).usesMiles);
      if (reminder == null) return AlertActionResult.nothing;
      await notifications.schedule(reminder);
      return AlertActionResult.reminderSet;
    default:
      return AlertActionResult.nothing;
  }
}

Future<SkyEvent?> findStoredEvent(LocalStore store, String id) async {
  for (final e in [...await store.loadEvents(), ...await store.loadRecent()]) {
    if (e.id == id) return e;
  }
  return null;
}
