/// Remote push (Firebase Cloud Messaging) for "aurora now", sent by the
/// backend's aurora-watch function. Entirely optional: it only starts when
/// Firebase options are provided at build time (docs/backend.md), so builds
/// without Firebase run exactly as before.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class PushConfig {
  static const apiKey = String.fromEnvironment('LOOKUP_FIREBASE_API_KEY');
  static const appIdAndroid = String.fromEnvironment('LOOKUP_FIREBASE_APP_ID_ANDROID');
  static const appIdIos = String.fromEnvironment('LOOKUP_FIREBASE_APP_ID_IOS');
  static const senderId = String.fromEnvironment('LOOKUP_FIREBASE_SENDER_ID');
  static const projectId = String.fromEnvironment('LOOKUP_FIREBASE_PROJECT_ID');

  static bool get configured => apiKey.isNotEmpty && senderId.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions options() => FirebaseOptions(
        apiKey: apiKey,
        appId: defaultTargetPlatform == TargetPlatform.iOS ? appIdIos : appIdAndroid,
        messagingSenderId: senderId,
        projectId: projectId,
        iosBundleId: 'com.brilliantdisruptions.lookup',
      );
}

class PushService {
  PushService({this.onForegroundMessage});

  /// Show foreground pushes as a local notification (FCM doesn't on its own).
  final void Function(String title, String body, Map<String, dynamic> data)? onForegroundMessage;
  String? token;

  Future<String?> init() async {
    if (!PushConfig.configured) return null;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: PushConfig.options());
      final m = FirebaseMessaging.instance;
      // iOS asks permission through flutter_local_notifications already; this
      // only registers for remote delivery.
      await m.requestPermission(alert: true, sound: true, badge: false);
      // getToken/onTokenRefresh are deprecated in favour of register() +
      // onRegistered (Firebase Installation IDs). The backend sends with the
      // FCM HTTP v1 `message.token` field, which takes registration tokens;
      // switch both sides together when migrating.
      // ignore: deprecated_member_use
      token = await m.getToken();
      FirebaseMessaging.onMessage.listen((msg) {
        final n = msg.notification;
        if (n != null) onForegroundMessage?.call(n.title ?? 'LookUp', n.body ?? '', msg.data);
      });
      // ignore: deprecated_member_use
      m.onTokenRefresh.listen((t) => token = t);
      return token;
    } catch (e) {
      debugPrint('push disabled: $e');
      return null;
    }
  }
}
