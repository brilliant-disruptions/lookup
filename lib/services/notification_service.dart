import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/models/sky_event.dart';
import '../domain/scheduling/alert_planner.dart';
import 'alert_art.dart';

/// Makes the picture for an alert, or null for none.
typedef AlertArtMaker = Future<String?> Function(PlannedAlert alert);

/// Buttons on an alert. "Find it" opens the app; the others run in the
/// background without opening it.
abstract final class AlertAction {
  static const find = 'find';
  static const snooze = 'snooze';
  static const seen = 'seen';
}

class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin, AlertArtMaker? art])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _art = art ?? AlertArt.fileFor;

  final FlutterLocalNotificationsPlugin _plugin;

  /// The "where to look" picture on pass heads-ups ([AlertArt]).
  final AlertArtMaker _art;
  static bool _tzReady = false;

  /// Android fixes a channel's sound when it's created, so the chime got a
  /// new channel; the old one is deleted on init.
  static const channelId = 'lookup_alerts_chime';
  static const _legacyChannelId = 'lookup_alerts';
  static const _chime = 'lookup_chime';

  static const _headsUpCategory = 'lookup_heads_up';
  static const _goNowCategory = 'lookup_go_now';

  static const _findAndroid =
      AndroidNotificationAction(AlertAction.find, 'Find it', showsUserInterface: true);
  static const _snoozeAndroid = AndroidNotificationAction(AlertAction.snooze, 'In 5 min');
  static const _seenAndroid = AndroidNotificationAction(AlertAction.seen, 'Saw it!');

  /// With [imagePath], the alert carries a picture: Android's expanded big
  /// picture (with [body] under it), iOS's attachment.
  static NotificationDetails detailsFor(
    AlertKind kind, {
    String? imagePath,
    String? title,
    String? body,
    DateTime? countdownTo,
    int? timeoutAfterMs,
    String? thread,
  }) {
    final withSnooze = kind == AlertKind.headsUp;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Sky alerts',
        channelDescription: 'ISS, Starlink and aurora heads-ups',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        sound: const RawResourceAndroidNotificationSound(_chime),
        actions: [_findAndroid, if (withSnooze) _snoozeAndroid, _seenAndroid],
        // Nothing private in a sky alert: show it in full on the lock screen,
        // even on phones that hide notification text there by default.
        visibility: NotificationVisibility.public,
        // A live countdown in the alert itself, ticking to the moment it appears.
        when: countdownTo?.millisecondsSinceEpoch,
        usesChronometer: countdownTo != null,
        chronometerCountDown: countdownTo != null,
        timeoutAfter: timeoutAfterMs,
        styleInformation: imagePath == null
            ? null
            : BigPictureStyleInformation(
                FilePathAndroidBitmap(imagePath),
                contentTitle: title,
                summaryText: body,
                hideExpandedLargeIcon: true,
              ),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBanner: true,
        sound: '$_chime.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
        categoryIdentifier: withSnooze ? _headsUpCategory : _goNowCategory,
        attachments: imagePath == null ? null : [DarwinNotificationAttachment(imagePath)],
        // One event's heads-up, reminder and go-now stack together.
        threadIdentifier: thread,
      ),
    );
  }

  /// Events that happen at a moment worth counting down to.
  static const countdownTypes = {
    SkyEventType.iss,
    SkyEventType.tiangong,
    SkyEventType.starlinkTrain,
    SkyEventType.rocketLaunch,
    SkyEventType.lunarEclipse,
  };

  /// How long an alert stays after its event ends, for the Saw it! button.
  static const linger = Duration(minutes: 20);

  /// [detailsFor] with what [a] itself implies: a countdown to the moment
  /// it appears (when that's still ahead at firing), clearing itself
  /// [linger] after the event ends, and grouped with its event's other alerts.
  static NotificationDetails detailsForAlert(PlannedAlert a, {String? imagePath}) {
    final e = a.event;
    final countdown = countdownTypes.contains(e.type) && e.start.isAfter(a.fireAt) ? e.start : null;
    final clearAt = e.end.add(linger).difference(a.fireAt).inMilliseconds;
    return detailsFor(
      a.kind,
      imagePath: imagePath,
      title: a.title,
      body: a.body,
      countdownTo: countdown,
      timeoutAfterMs: clearAt > 0 ? clearAt : null,
      thread: e.id,
    );
  }

  static final _categories = [
    for (final (id, snooze) in const [(_headsUpCategory, true), (_goNowCategory, false)])
      DarwinNotificationCategory(id, actions: [
        DarwinNotificationAction.plain(AlertAction.find, 'Find it',
            options: {DarwinNotificationActionOption.foreground}),
        if (snooze) DarwinNotificationAction.plain(AlertAction.snooze, 'Remind me in 5 min'),
        DarwinNotificationAction.plain(AlertAction.seen, 'Saw it!'),
      ]),
  ];

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

  /// [onResponse] runs on the main isolate for taps and "Find it";
  /// [onBackgroundResponse] (a top-level `vm:entry-point` function) handles
  /// the buttons that don't open the app.
  Future<void> init({
    void Function(NotificationResponse response)? onResponse,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundResponse,
  }) async {
    await ensureTimeZone();
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: _categories,
        ),
      ),
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
    );
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.deleteNotificationChannel(channelId: _legacyChannelId);
    } catch (_) {}
  }

  /// The alert that cold-started the app, if any.
  Future<NotificationResponse?> launchResponse() async {
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      return (d?.didNotificationLaunchApp ?? false) ? d!.notificationResponse : null;
    } catch (_) {
      return null;
    }
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

  /// Whether alerts can reach the user. Null when the platform can't say.
  Future<bool?> alertsEnabled() async {
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return (await ios.checkPermissions())?.isEnabled;
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.areNotificationsEnabled();
    } catch (_) {}
    return null;
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
      await schedule(a);
    }
    return keep;
  }

  Future<void> schedule(PlannedAlert a) async {
    await ensureTimeZone();
    // The picture is a nice-to-have: any trouble and the alert goes as text.
    String? image;
    try {
      image = await _art(a);
    } catch (_) {}
    Future<void> go(String? img) => _plugin.zonedSchedule(
          id: a.notificationId,
          title: a.title,
          body: a.body,
          scheduledDate: tz.TZDateTime.from(a.fireAt, tz.local),
          notificationDetails: detailsForAlert(a, imagePath: img),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: a.event.id,
        );
    if (image == null) return go(null);
    try {
      await go(image);
    } catch (_) {
      // A picture the platform won't take must never cost the alert itself.
      await go(null);
    }
  }

  /// [a], shown right away (the "Preview an alert" tap), with its picture
  /// when it has one, and as text if the picture is any trouble.
  Future<void> showAlertNow(PlannedAlert a) async {
    String? image;
    try {
      image = await _art(a);
    } catch (_) {}
    Future<void> go(String? img) => _plugin.show(
          id: a.notificationId,
          title: a.title,
          body: a.body,
          notificationDetails: detailsForAlert(a, imagePath: img),
          payload: a.event.id,
        );
    if (image == null) return go(null);
    try {
      await go(image);
    } catch (_) {
      await go(null);
    }
  }

  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
    AlertKind kind = AlertKind.headsUp,
  }) =>
      _plugin.show(id: id, title: title, body: body,
          notificationDetails: detailsFor(kind), payload: payload);

  Future<void> cancelAll() => _plugin.cancelAll();
}
