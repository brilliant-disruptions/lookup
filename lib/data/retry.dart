/// Retry transient network failures (connection resets, timeouts, 5xx/429)
/// with exponential backoff. Celestrak in particular resets connections
/// under load; one failed first fetch must not leave the app empty.
library;

import 'dart:async';

Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int attempts = 3,
  Duration initialDelay = const Duration(seconds: 2),
  Future<void> Function(Duration)? sleep,
}) async {
  final wait = sleep ?? Future<void>.delayed;
  var delay = initialDelay;
  for (var i = 1; ; i++) {
    try {
      return await fn();
    } catch (_) {
      if (i >= attempts) rethrow;
      await wait(delay);
      delay *= 2;
    }
  }
}
