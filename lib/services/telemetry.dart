/// Crash reporting (Sentry), enabled only when a DSN is provided:
///   --dart-define=LOOKUP_SENTRY_DSN=https://...
/// No DSN, no SDK init, no network.
library;

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

const sentryDsn = String.fromEnvironment('LOOKUP_SENTRY_DSN');

Future<void> runWithTelemetry(FutureOr<void> Function() appRunner) async {
  if (sentryDsn.isEmpty) {
    await appRunner();
    return;
  }
  await SentryFlutter.init(
    (o) {
      o.dsn = sentryDsn;
      o.tracesSampleRate = 0.1;
      o.sendDefaultPii = false; // no IPs, no user ids
      o.attachScreenshot = false;
    },
    appRunner: appRunner,
  );
}
