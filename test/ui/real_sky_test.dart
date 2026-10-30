import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/real_sky.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.s);
  final LookUpSettings s;
  @override
  Future<LookUpSettings> build() async => s;
}

void main() {
  late SkyCatalog catalog;
  setUpAll(() {
    Map<String, Object?> read(String f) => jsonDecode(File('assets/sky/$f').readAsStringSync()) as Map<String, Object?>;
    catalog = SkyCatalog.fromJson(read('stars.json'), read('constellations.json'), read('proper_motion.json'));
  });

  Future<void> pump(WidgetTester t, LookUpSettings s) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(s)),
        skyCatalogProvider.overrideWith((_) async => catalog),
        clockProvider.overrideWith((_) => Stream.value(DateTime.utc(2026, 10, 30, 3))),
      ],
      child: const MaterialApp(home: Scaffold(body: SkyBackdrop(child: SizedBox.expand()))),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('with a location, the backdrop is the real sky', (t) async {
    await pump(t, const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true));
    expect(find.byType(RealSky), findsOneWidget);
    expect(find.byType(Starfield), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('before there is one, it falls back to a scatter of stars', (t) async {
    await pump(t, const LookUpSettings());
    expect(find.byType(Starfield), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
