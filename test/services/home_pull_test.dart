import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:lookup/services/refresh_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A refresh that takes as long as the test says (a slow or throttled network).
class _SlowRefresh extends RefreshService {
  _SlowRefresh() : super(store: LocalStore(), notifications: NotificationService());
  final done = Completer<RefreshReport>();
  final forced = <bool>[];
  @override
  Future<RefreshReport> run({bool force = false, bool allowLocationPrompt = false}) {
    forced.add(force);
    return done.future;
  }
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  // The pull-to-refresh spinner stays until pull() completes; a refresh that
  // waits on every source's retries kept it spinning for minutes.
  testWidgets('a slow refresh stops the spinner, then still lands', (t) async {
    final slow = _SlowRefresh();
    final c = ProviderContainer(overrides: [refreshServiceProvider.overrideWithValue(slow)]);
    addTearDown(c.dispose);
    await c.read(homeProvider.future);

    var stopped = false;
    unawaited(c.read(homeProvider.notifier).pull().then((_) => stopped = true));
    await t.pump(HomeNotifier.pullLimit - const Duration(seconds: 1));
    expect(stopped, isFalse, reason: 'a quick refresh should still be waited for');
    await t.pump(const Duration(seconds: 2));
    expect(stopped, isTrue, reason: 'the spinner must not outlast pullLimit');

    slow.done.complete(RefreshReport(events: const [], plan: const [], errors: ['clouds: late']));
    await t.pump();
    expect(c.read(homeProvider).value!.errors, ['clouds: late'],
        reason: 'the refresh keeps going after the spinner stops');
  });

  // A forced fetch skips every cache: each pull re-downloaded Celestrak
  // (~4.7 MB of Starlink) against its once-a-day rule, and repeat downloads
  // within 2 h are refused and retried, which made pulls slow.
  testWidgets('a pull only fetches what is stale', (t) async {
    final slow = _SlowRefresh();
    final c = ProviderContainer(overrides: [refreshServiceProvider.overrideWithValue(slow)]);
    addTearDown(c.dispose);
    await c.read(homeProvider.future);

    unawaited(c.read(homeProvider.notifier).pull());
    await t.pump(HomeNotifier.pullLimit);
    expect(slow.forced, [false]);
  });
}
