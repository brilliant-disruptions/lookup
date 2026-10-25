import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/services/alert_actions.dart';
import 'package:lookup/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FakeNotifications extends NotificationService {
  final scheduled = <PlannedAlert>[];
  @override
  Future<void> schedule(PlannedAlert a) async => scheduled.add(a);
}

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
    details: const {'magnitude': -3.1},
  );

  late LocalStore store;
  late _FakeNotifications notifications;
  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = LocalStore(SharedPreferencesAsync());
    notifications = _FakeNotifications();
    await store.saveEvents([event]);
  });

  test('"Saw it!" logs a sighting without opening the app', () async {
    final r = await handleAlertAction(
        actionId: AlertAction.seen, eventId: event.id, store: store, notifications: notifications, now: now);
    expect(r, AlertActionResult.logged);
    final f = (await store.loadFeedback()).single;
    expect(f.seen, isTrue);
    expect(f.type, SkyEventType.iss);
    expect(f.magnitude, -3.1);
  });

  test('"Remind me in 5 min" schedules one reminder', () async {
    final r = await handleAlertAction(
        actionId: AlertAction.snooze, eventId: event.id, store: store, notifications: notifications, now: now);
    expect(r, AlertActionResult.reminderSet);
    expect(notifications.scheduled.single.fireAt, now.add(const Duration(minutes: 5)));
  });

  test('unknown events and plain taps do nothing', () async {
    expect(
        await handleAlertAction(
            actionId: AlertAction.seen, eventId: 'iss:gone', store: store, notifications: notifications),
        AlertActionResult.nothing);
    expect(
        await handleAlertAction(actionId: null, eventId: event.id, store: store, notifications: notifications),
        AlertActionResult.nothing);
    expect(await store.loadFeedback(), isEmpty);
  });
}
