/// Seen near you wake-ups: the relay nudges a sleeping phone when enough
/// people nearby say they can see the aurora, and the phone then runs its
/// usual refresh, which decides for itself whether to alert
/// (docs/seen-near-you.md). The push carries no text and no data.
///
/// iPhone only for now: iOS gives the push address over `lookup/push`
/// (ios/Runner/AppDelegate.swift). Android needs Firebase, still to come.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../data/aurora_reports_client.dart';
import '../data/local_store.dart';
import '../domain/aurora/push_plan.dart';
import '../domain/models/settings.dart';

class PushService {
  static const _channel = MethodChannel('lookup/push');

  /// Runs one refresh when a wake-up arrives. Set by [init].
  static Future<void> Function()? _onWake;

  /// Listens for wake-ups and tells iOS that Dart is ready for them (one
  /// may be waiting: a wake-up can be what launched the app).
  static Future<void> init({required Future<void> Function() onWake}) async {
    if (!Platform.isIOS) return;
    _onWake = onWake;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'wake') return null;
      try {
        await _onWake?.call();
      } catch (_) {
        // Best effort: the next wake-up or scheduled refresh tries again.
      }
      return null;
    });
    try {
      await _channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // An older native build without the channel.
    }
  }

  /// Registers with the relay, renews, or withdraws, as [pushStep] says.
  /// Quiet on failure: wake-ups are a bonus over the scheduled refresh.
  static Future<void> sync(LookUpSettings s, {LocalStore? store, AuroraReportsClient? client}) async {
    if (!Platform.isIOS) return;
    final st = store ?? LocalStore();
    final last = await st.loadPushRecord();
    final wanted = pushWanted(s, relayConfigured: relayConfigured);
    if (!wanted && last == null) return;
    final relay = client ?? AuroraReportsClient();
    try {
      final address = wanted ? await _address() : null;
      final area = wanted ? pushArea(s.latitude!, s.longitude!) : null;
      final now = DateTime.now().toUtc();
      switch (pushStep(wanted: wanted, token: address?.token, area: area, last: last, now: now)) {
        case PushStep.subscribe:
          await relay.subscribe(
              token: address!.token, apple: true, latDeg: s.latitude!, lonDeg: s.longitude!, sandbox: address.sandbox);
          await st.savePushRecord((token: address.token, area: area!, at: now));
        case PushStep.unsubscribe:
          await relay.unsubscribe(last!.token);
          await st.savePushRecord(null);
        case PushStep.nothing:
          break;
      }
    } catch (_) {
      // No push permission, no network or the relay is down: try next time.
    }
  }

  /// The phone's push address from iOS, and whether it's the development
  /// (sandbox) service. Null when push isn't available to this build.
  static Future<({String token, bool sandbox})?> _address() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('register').timeout(const Duration(seconds: 20));
      final token = r?['token'];
      if (token is! String || token.isEmpty) return null;
      return (token: token, sandbox: r?['sandbox'] == true);
    } on PlatformException {
      return null; // e.g. the Push Notifications capability isn't in this build yet
    } on MissingPluginException {
      return null;
    }
  }
}
