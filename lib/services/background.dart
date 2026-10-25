/// Background refresh: Android WorkManager periodic job; iOS BGAppRefresh.
/// Both are best effort — the 48 h local alert plan is what guarantees taps.
library;

import 'package:workmanager/workmanager.dart';

import '../data/local_store.dart';
import 'notification_service.dart';
import 'refresh_service.dart';
import 'shortcut_summary.dart';
import 'widget_service.dart';

const backgroundTaskId = 'com.brilliantdisruptions.lookup.refresh';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final notifications = NotificationService();
      await notifications.init();
      await WidgetService.init();
      final service = RefreshService(
        store: LocalStore(),
        notifications: notifications,
        // Keep the home-screen widget and Siri's answer fresh too.
        onRefreshed: (settings, events) async {
          await const WidgetService().update(events);
          await saveShortcutSummary(events);
        },
      );
      await service.run();
    } catch (_) {
      // Returning true avoids exponential backoff for transient failures;
      // the next scheduled run tries again with the cache intact.
    }
    return true;
  });
}

class BackgroundScheduler {
  static Future<void> register() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      backgroundTaskId,
      backgroundTaskId,
      frequency: const Duration(hours: 6),
      initialDelay: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
