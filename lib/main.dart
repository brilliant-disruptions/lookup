import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/background.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  final notifications = container.read(notificationServiceProvider);
  await notifications.init(
    onTap: (payload) => container.read(tappedEventIdProvider.notifier).set(payload),
  );
  try {
    await BackgroundScheduler.register();
  } catch (_) {
    // Background refresh is best effort (unsupported on some platforms).
  }
  runApp(UncontrolledProviderScope(
    container: container,
    child: const LookUpApp(),
  ));
}
