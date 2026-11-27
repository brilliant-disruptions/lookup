import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/relay_config.dart';
import 'services/alert_actions.dart';
import 'services/background.dart';
import 'services/push_service.dart';
import 'services/widget_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (relayMissingInRelease) {
    // tool/check_release_env.sh should have stopped this build. The app still
    // runs: with no clouds it says "No forecast", never "clear".
    developer.log('LOOKUP_RELAY_URL missing in a release build: no clouds, rare events or invites',
        name: 'lookup.relay', level: 1000);
  }
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
  await container.read(plusServiceProvider).start();
  await WidgetService.init();
  // A portrait app: every screen is laid out for a phone held upright, and
  // on its side the Week list had a finger's height to live in.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(UncontrolledProviderScope(
    container: container,
    child: const LookUpApp(),
  ));

  // Nothing on screen waits for these: set up after the first frame is asked for.
  try {
    await BackgroundScheduler.register();
  } catch (_) {
    // Background refresh is best effort (unsupported on some platforms).
  }
  // Seen near you wake-ups (iPhone): a nudge from the relay runs the usual
  // refresh, which decides for itself whether to alert. Not forced: anyone
  // can send the relay reports, so a nudge must not be a way to make every
  // phone nearby fetch its feeds early (the reports themselves are always
  // read fresh). Registration follows the settings: on, off, or a new area.
  await PushService.init(onWake: () => container.read(homeProvider.notifier).refresh());
  container.listen(settingsProvider, (_, next) {
    if (next.value case final s?) PushService.sync(s);
  }, fireImmediately: true);
}
