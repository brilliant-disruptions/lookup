import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/scheduling/alert_planner.dart';
import 'package:lookup/services/alert_art.dart';
import 'package:lookup/services/notification_service.dart';

/// Records what would be scheduled; can refuse alerts that carry a picture.
class _FakePlugin implements FlutterLocalNotificationsPlugin {
  _FakePlugin({this.refusePictures = false});
  final bool refusePictures;
  final scheduled = <NotificationDetails>[];
  final shown = <NotificationDetails>[];

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #zonedSchedule) {
      final d = i.namedArguments[#notificationDetails] as NotificationDetails;
      if (refusePictures && d.iOS?.attachments != null) return Future<void>.error(Exception('bad attachment'));
      scheduled.add(d);
      return Future<void>.value();
    }
    if (i.memberName == #show) {
      final d = i.namedArguments[#notificationDetails] as NotificationDetails;
      if (refusePictures && d.iOS?.attachments != null) return Future<void>.error(Exception('bad attachment'));
      shown.add(d);
      return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

final _start = DateTime.utc(2026, 11, 6, 3, 5);

SkyEvent _ev(SkyEventType type) => SkyEvent(
  id: '${type.name}:1',
  type: type,
  start: _start,
  peak: _start.add(const Duration(minutes: 2)),
  end: _start.add(const Duration(minutes: 4)),
  peakElevationDeg: 62,
  riseAzimuthDeg: 247,
  peakAzimuthDeg: 180,
  setAzimuthDeg: 95,
);

PlannedAlert _alert(SkyEventType type, {AlertKind kind = AlertKind.headsUp}) => PlannedAlert(
  notificationId: 7,
  event: _ev(type),
  fireAt: _start.subtract(const Duration(minutes: 10)),
  kind: kind,
  title: 'ISS flyover in 10 min',
  body: 'Brighter than any star, rising in the west-southwest.',
);

void main() {
  test('a pass heads-up carries its picture on both platforms', () async {
    final plugin = _FakePlugin();
    await NotificationService(plugin, (_) async => '/tmp/x.png').schedule(_alert(SkyEventType.iss));
    final d = plugin.scheduled.single;
    expect(d.iOS?.attachments?.single.filePath, '/tmp/x.png');
    final style = d.android?.styleInformation as BigPictureStyleInformation;
    expect((style.bigPicture as FilePathAndroidBitmap).data, '/tmp/x.png');
    expect(style.summaryText, startsWith('Brighter than any star'));
  });

  test('no picture, or a picture that fails to make, still schedules the alert as text', () async {
    for (final art in <AlertArtMaker>[(_) async => null, (_) async => throw Exception('no disk')]) {
      final plugin = _FakePlugin();
      await NotificationService(plugin, art).schedule(_alert(SkyEventType.iss));
      expect(plugin.scheduled.single.iOS?.attachments, isNull);
      expect(plugin.scheduled.single.android?.styleInformation, isNull);
    }
  });

  test('if the platform refuses the picture, the alert is scheduled without it', () async {
    final plugin = _FakePlugin(refusePictures: true);
    await NotificationService(plugin, (_) async => '/tmp/x.png').schedule(_alert(SkyEventType.iss));
    expect(plugin.scheduled, hasLength(1));
    expect(plugin.scheduled.single.iOS?.attachments, isNull);
  });

  test('the preview tap shows right away with its picture, falling back to text', () async {
    final ok = _FakePlugin();
    await NotificationService(ok, (_) async => '/tmp/x.png').showAlertNow(_alert(SkyEventType.iss));
    expect(ok.shown.single.iOS?.attachments?.single.filePath, '/tmp/x.png');
    final refused = _FakePlugin(refusePictures: true);
    await NotificationService(refused, (_) async => '/tmp/x.png').showAlertNow(_alert(SkyEventType.iss));
    expect(refused.shown.single.iOS?.attachments, isNull);
  });

  group('countdown and clean-up', () {
    test('a pass alert counts down to the moment it appears, shows on the lock screen and clears after', () {
      final a = _alert(SkyEventType.iss); // fires 10 min before a 4-min pass
      final android = NotificationService.detailsForAlert(a).android!;
      expect(android.usesChronometer, isTrue);
      expect(android.chronometerCountDown, isTrue);
      expect(android.when, _start.millisecondsSinceEpoch);
      expect(android.visibility, NotificationVisibility.public);
      // 10 min to go + 4 min pass + 20 min to press "Saw it!".
      expect(android.timeoutAfter, const Duration(minutes: 34).inMilliseconds);
      expect(NotificationService.detailsForAlert(a).iOS?.threadIdentifier, 'iss:1');
    });

    test('a long event gets no countdown, but still clears and groups', () {
      final android = NotificationService.detailsForAlert(_alert(SkyEventType.meteorShower)).android!;
      expect(android.usesChronometer, isFalse);
      expect(android.when, isNull);
      expect(android.timeoutAfter, isNotNull);
    });

    test('no countdown to a moment already past when it fires', () {
      final late = PlannedAlert(
        notificationId: 8,
        event: _ev(SkyEventType.iss),
        fireAt: _start.add(const Duration(seconds: 30)),
        kind: AlertKind.goNow,
        title: 't',
        body: 'b',
      );
      expect(NotificationService.detailsForAlert(late).android!.usesChronometer, isFalse);
    });

    test('scheduled alerts carry it', () async {
      final plugin = _FakePlugin();
      await NotificationService(plugin, (_) async => null).schedule(_alert(SkyEventType.iss));
      expect(plugin.scheduled.single.android!.usesChronometer, isTrue);
    });
  });

  test('only pass heads-ups get a picture', () {
    expect(AlertArt.wants(_alert(SkyEventType.iss)), isTrue);
    expect(AlertArt.wants(_alert(SkyEventType.starlinkTrain)), isTrue);
    expect(AlertArt.wants(_alert(SkyEventType.iss, kind: AlertKind.goNow)), isFalse);
    expect(AlertArt.wants(_alert(SkyEventType.meteorShower)), isFalse);
    expect(AlertArt.wants(_alert(SkyEventType.auroraNow)), isFalse);
  });

  testWidgets('paints a 2:1 PNG', (t) async {
    final bytes = await t.runAsync(() => AlertArt.png(_ev(SkyEventType.iss), startLabel: '9:05 PM'));
    expect(bytes, isNotNull);
    expect(bytes!.take(4), [0x89, 0x50, 0x4E, 0x47]); // ‰PNG
    // IHDR width and height.
    int be(int o) => (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];
    expect((be(16), be(20)), (AlertArt.width, AlertArt.height));
  });
}
