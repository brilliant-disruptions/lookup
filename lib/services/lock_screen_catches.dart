/// "Saw it" on the Lock Screen: the Live Activity's button
/// (ios/LookUpWidgets/SawItIntent.swift) runs without the app and leaves the
/// event's id in the app group. A sighting now goes in the Log only when
/// it's caught with the camera, so the app just clears that list (on launch,
/// on resume and in the background refresh) and logs nothing from it. The
/// button itself becomes "Catch it", opening the camera, once the widget
/// extension is built on a Mac (docs/mac-checklist.md).
library;

import 'dart:io' show Platform;

import 'package:home_widget/home_widget.dart';

import '../data/local_store.dart';
import 'notification_service.dart';

/// The app-group key the Swift side appends to: a JSON list of event ids.
const lockScreenCatchesKey = 'saw_it_pending';

/// Clears the waiting list without logging any of it: a catch needs a
/// picture. Returns how many were logged, which is always 0 now.
Future<int> importLockScreenCatches({
  required LocalStore store,
  required NotificationService notifications,
  required Future<String?> Function() read,
  required Future<void> Function() clear,
}) async {
  final raw = await read();
  if (raw == null || raw.isEmpty) return 0;
  await clear();
  return 0;
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
