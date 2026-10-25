import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/alert_actions.dart';
import 'services/background.dart';
import 'services/widget_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  final notifications = container.read(notificationServiceProvider);
  void onAlert(NotificationResponse? r) {
    final id = r?.payload;
    if (id == null) return;
    container.read(alertTapProvider.notifier).set(AlertTap(id, action: r!.actionId));
  }

  await notifications.init(onResponse: onAlert, onBackgroundResponse: onAlertActionInBackground);
  // Opened by tapping an alert while the app wasn't running.
  onAlert(await notifications.launchResponse());
  try {
    await BackgroundScheduler.register();
  } catch (_) {
    // Background refresh is best effort (unsupported on some platforms).
  }
  await container.read(plusServiceProvider).start();
  await WidgetService.init();
  runApp(UncontrolledProviderScope(
    container: container,
    child: const LookUpApp(),
  ));
}
