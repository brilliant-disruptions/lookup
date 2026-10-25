import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/shortcut_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  final start = DateTime.now().toUtc().add(const Duration(hours: 3));
  SkyEvent ev(String id, SkyEventType t, {Map<String, Object?> details = const {}, int? clouds}) => SkyEvent(
        id: id,
        type: t,
        start: start,
        peak: start.add(const Duration(minutes: 2)),
        end: start.add(const Duration(minutes: 5)),
        peakElevationDeg: 70,
        riseAzimuthDeg: 250,
        peakAzimuthDeg: 180,
        setAzimuthDeg: 90,
        cloudCoverPercent: clouds,
        details: details,
      );

  test('speaks direction words, never numbers', () {
    final s = spokenSummary(ev('iss:1', SkyEventType.iss));
    expect(s, startsWith('The space station passes over'));
    expect(s, contains('Look west-southwest'));
    expect(RegExp(r'\d+°').hasMatch(s), isFalse);
    expect(spokenSummary(ev('iss:2', SkyEventType.iss, clouds: 90)), endsWith('Clouds may get in the way.'));
  });

  test('payload skips things we never push and keeps times for the Swift side', () async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final prefs = SharedPreferencesAsync();
    await saveShortcutSummary([
      ev('aurora-outlook:1', SkyEventType.auroraOutlook),
      ev('transit-sun:1', SkyEventType.issTransit, details: {'body': 'Sun'}),
      ev('iss:1', SkyEventType.iss),
    ], prefs);
    final items = (jsonDecode((await prefs.getString(shortcutKey))!) as List).cast<Map>();
    expect(items, hasLength(1));
    expect(items.single['endMs'], start.add(const Duration(minutes: 5)).millisecondsSinceEpoch);
  });
}
