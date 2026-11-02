import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookup/data/aurora_reports_client.dart';
import 'package:lookup/data/local_store.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/widgets/seen_it_row.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 55.95, longitude: -3.19, onboarded: true);
}

SkyEvent _aurora(DateTime start) => SkyEvent(
      id: 'aurora-outlook:x',
      type: SkyEventType.auroraOutlook,
      start: start,
      peak: start.add(const Duration(hours: 2)),
      end: start.add(const Duration(hours: 6)),
      peakElevationDeg: 15,
      riseAzimuthDeg: 0,
      peakAzimuthDeg: 0,
      setAzimuthDeg: 0,
    );

void main() {
  final night = DateTime.utc(2026, 11, 2, 22);

  test('offered on an aurora, at night, where the feature runs, with a relay', () {
    final e = _aurora(night.subtract(const Duration(hours: 1)));
    expect(showSeenItRow(e, lat: 55.95, lon: -3.19, now: night, configured: true), isTrue);
    expect(showSeenItRow(e, lat: 55.95, lon: -3.19, now: night, configured: false), isFalse, reason: 'no relay in this build');
    expect(showSeenItRow(e, lat: 55.95, lon: -3.19, now: DateTime.utc(2026, 11, 2, 13), configured: true), isFalse, reason: 'daylight');
    expect(showSeenItRow(e, lat: 40.42, lon: -3.70, now: night, configured: true), isFalse, reason: 'Madrid: not offered');
    expect(showSeenItRow(e, lat: 55.95, lon: -3.19, now: night.add(const Duration(hours: 8)), configured: true), isFalse, reason: 'over');
    final pass = SkyEvent(
        id: 'iss:1', type: SkyEventType.iss, start: night, peak: night, end: night.add(const Duration(minutes: 4)),
        peakElevationDeg: 50, riseAzimuthDeg: 0, peakAzimuthDeg: 0, setAzimuthDeg: 0);
    expect(showSeenItRow(pass, lat: 55.95, lon: -3.19, now: night, configured: true), isFalse);
  });

  testWidgets('the first tap asks before anything is sent; "Not now" sends nothing', (t) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    var sent = 0;
    final client = AuroraReportsClient(base: 'https://relay.test', client: MockClient((_) async {
      sent++;
      return http.Response('', 202);
    }));
    await t.pumpWidget(ProviderScope(
      overrides: [settingsProvider.overrideWith(_Settings.new), storeProvider.overrideWithValue(LocalStore())],
      child: MaterialApp(home: Scaffold(body: SeenItRow(client: client))),
    ));
    await t.pump();
    await t.tap(find.text('Yes, by eye'));
    await t.pumpAndSettle();
    expect(find.text('Tell people nearby?'), findsOneWidget);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(sent, 0);

    await t.tap(find.text('Yes, by eye'));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn on and send'));
    await t.pumpAndSettle();
    expect(sent, 1);
    expect(find.text('Thanks. People near you will hear about it.'), findsOneWidget);
  });
}
