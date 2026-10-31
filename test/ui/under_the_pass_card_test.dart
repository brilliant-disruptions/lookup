import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/passes/pass_predictor.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/caught_it_screen.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 51.5, longitude: -0.12, onboarded: true, isPlus: true);
}

class _Home extends HomeNotifier {
  @override
  Future<HomeData> build() async => HomeData(events: const [], aurora: null, lastRefresh: DateTime.now().toUtc(), errors: const []);
  @override
  Future<void> refresh({bool force = false}) async {}
}

void main() {
  testWidgets('a real pass over London says who else was under it', (t) async {
    t.view.physicalSize = const Size(1179, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final iss = OmmRecord.listFromJson(jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync())).single;
    final pass = PassPredictor(latitude: 51.5, longitude: -0.12)
        .predict(
          record: iss,
          type: SkyEventType.iss,
          from: DateTime.utc(2026, 10, 20, 16),
          to: DateTime.utc(2026, 10, 22),
          minPeakElevationDeg: 10,
        )
        .first;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          homeProvider.overrideWith(_Home.new),
          skyLogProvider.overrideWith(
            (_) async => SkyLog.from([Sighting(eventId: pass.id, seen: true, at: pass.end, type: SkyEventType.iss)]),
          ),
          alertsEnabledProvider.overrideWith((_) async => true),
        ],
        child: MaterialApp(
          theme: buildLookUpTheme(),
          home: CaughtItScreen(event: pass, animate: false),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('You weren\'t alone'), findsOneWidget);
    expect(find.textContaining('million people'), findsOneWidget);
    expect(find.textContaining('Paris'), findsOneWidget);
  });
}
