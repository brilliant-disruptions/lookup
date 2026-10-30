import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/share_card.dart';
import 'package:lookup/ui/sky_snapshot.dart';
import 'package:lookup/ui/theme.dart';

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

  // A real evening pass over Nashville, rising WSW and setting E.
  final t = DateTime.utc(2026, 10, 30, 3, 5);
  final pass = SkyEvent(
    id: 'iss:test',
    type: SkyEventType.iss,
    start: t,
    peak: t.add(const Duration(minutes: 2)),
    end: t.add(const Duration(minutes: 5)),
    peakElevationDeg: 64,
    riseAzimuthDeg: 247,
    peakAzimuthDeg: 180,
    setAzimuthDeg: 90,
    details: const {'brightness': 'brighter than any star', 'past': true},
  );

  Future<void> pump(WidgetTester t, LookUpSettings s) async {
    // The test font is far wider than Inter, so give the poster room to lay
    // out as it does on a phone at 300 pt.
    t.view.physicalSize = const Size(1600, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(s)),
        skyCatalogProvider.overrideWith((_) async => catalog),
      ],
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: Scaffold(body: Center(child: SizedBox(width: 640, child: ShareCard(event: pass, mode: ShareMode.sawIt, place: 'Nashville')))),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('with a location the poster is a snapshot of the real sky', (t) async {
    await pump(t, const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true));
    expect(find.byType(SkySnapshot), findsOneWidget);
    expect(find.text('I saw it'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('without one it keeps the stylised poster', (t) async {
    await pump(t, const LookUpSettings());
    expect(find.byType(SkySnapshot), findsNothing);
    expect(find.byType(Starfield), findsOneWidget);
  });
}
