import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/lock_screen_catches.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 23);
  final event = SkyEvent(
    id: 'iss:20261021T2310Z',
    type: SkyEventType.iss,
    start: now.add(const Duration(minutes: 10)),
    peak: now.add(const Duration(minutes: 12)),
    end: now.add(const Duration(minutes: 14)),
    peakElevationDeg: 64,
    riseAzimuthDeg: 250,
    peakAzimuthDeg: 180,
    setAzimuthDeg: 90,
  );

  late LocalStore store;
  String? waiting;
  Future<int> import() => importLockScreenCatches(
        store: store,
        notifications: NotificationService(),
        read: () async => waiting,
        clear: () async => waiting = null,
      );

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = LocalStore(SharedPreferencesAsync());
    await store.saveEvents([event]);
    waiting = null;
  });

  // A sighting goes in the Log only when it's caught with the camera, so
  // the Lock Screen's list is cleared without logging anything.
  test('"Saw it" on the Lock Screen is cleared, and logs nothing without a picture', () async {
    waiting = jsonEncode([event.id, event.id]);
    expect(await import(), 0);
    expect(waiting, isNull, reason: 'cleared, so it is not looked at again');
    expect(await store.loadFeedback(), isEmpty);
  });

  test('nothing waiting, an unknown event or junk logs nothing', () async {
    expect(await import(), 0);
    waiting = jsonEncode(['iss:gone']);
    expect(await import(), 0);
    waiting = 'not json';
    expect(await import(), 0);
    expect(waiting, isNull, reason: 'junk is cleared too');
    expect(await store.loadFeedback(), isEmpty);
  });
}
