import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/scheduling/alert_planner.dart';

class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static bool _tzReady = false;

  static const channelId = 'lookup_alerts';

  static const _android = AndroidNotificationDetails(
    channelId,
    'Sky alerts',
    channelDescription: 'ISS, Starlink and aurora heads-ups',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );
  static const _darwin = DarwinNotificationDetails(
    presentAlert: true,
    presentSound: true,
    presentBanner: true,
    interruptionLevel: InterruptionLevel.timeSensitive,
  );
  static const _details = NotificationDetails(android: _android, iOS: _darwin);

  /// Local time zone for scheduling. Safe to call repeatedly.
  static Future<void> ensureTimeZone() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    _tzReady = true;
  }

  /// Offset the domain layer uses for quiet hours and "night" bucketing.
  static int utcOffsetMinutes() => DateTime.now().timeZoneOffset.inMinutes;

  Future<void> init({void Function(String? payload)? onTap}) async {
    await ensureTimeZone();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );
  }

  Future<bool> requestPermission() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true, badge: false) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  /// Replace the scheduled set with [plan]: cancels ids no longer planned,
  /// (re)schedules every planned alert. Ids are stable so this is idempotent.
  Future<Set<int>> applyPlan(List<PlannedAlert> plan, Set<int> previous) async {
    await ensureTimeZone();
    final keep = {for (final a in plan) a.notificationId};
    for (final id in previous.difference(keep)) {
      await _plugin.cancel(id: id);
    }
    for (final a in plan) {
      await _plugin.zonedSchedule(
        id: a.notificationId,
        title: a.title,
        body: a.body,
        scheduledDate: tz.TZDateTime.from(a.fireAt, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: a.event.id,
      );
    }
    return keep;
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) =>
      _plugin.show(id: id, title: title, body: body,
          notificationDetails: _details, payload: payload);

  Future<void> cancelAll() => _plugin.cancelAll();
}
