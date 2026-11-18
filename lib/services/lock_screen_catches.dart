/// "Saw it" on the Lock Screen: the Live Activity's button
/// (ios/LookUpWidgets/SawItIntent.swift) runs without the app, so it leaves
/// the event's id in the app group, and the app files it in the Log the next
/// time it runs (on launch, on resume and in the background refresh).
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:home_widget/home_widget.dart';

import '../data/local_store.dart';
import 'alert_actions.dart';
import 'notification_service.dart';

/// The app-group key the Swift side appends to: a JSON list of event ids.
const lockScreenCatchesKey = 'saw_it_pending';

/// Logs each waiting catch once, as "Saw it!" from an alert would, then
/// clears the list. Returns how many were logged. Unknown ids (an event
/// that has since dropped out of the store) are dropped quietly.
Future<int> importLockScreenCatches({
  required LocalStore store,
  required NotificationService notifications,
  required Future<String?> Function() read,
  required Future<void> Function() clear,
}) async {
  final raw = await read();
  if (raw == null || raw.isEmpty) return 0;
  final ids = <String>{};
  try {
    ids.addAll((jsonDecode(raw) as List).whereType<String>());
  } catch (_) {
    // Not a list we wrote: nothing to log, and don't trip on it again.
  }
  await clear();
  var logged = 0;
  for (final id in ids) {
    final r = await handleAlertAction(actionId: AlertAction.seen, eventId: id, store: store, notifications: notifications);
    if (r == AlertActionResult.logged) logged++;
  }
  return logged;
}

/// [importLockScreenCatches] against the real app group (iPhone only).
Future<int> importLockScreenCatchesFromAppGroup(LocalStore store, NotificationService notifications) async {
  try {
    if (!Platform.isIOS) return 0;
  } catch (_) {
    return 0;
  }
  try {
    return await importLockScreenCatches(
      store: store,
      notifications: notifications,
      read: () => HomeWidget.getWidgetData<String>(lockScreenCatchesKey),
      clear: () async {
        await HomeWidget.saveWidgetData<String>(lockScreenCatchesKey, null);
      },
    );
  } catch (_) {
    return 0;
  }
}
