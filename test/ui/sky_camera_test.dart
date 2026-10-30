import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/sky/sky_camera_screen.dart';
import 'package:lookup/ui/sky/sky_thing.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
}

void main() {
  final now = DateTime.utc(2026, 10, 25, 3);
  final saturn = SkyThing(
    id: 'planet:saturn',
    name: 'Saturn',
    kind: 'Planet',
    position: (_) => const Horizontal(180, 8),
    mag: 0.6,
    finder: const {'planet': 'Saturn'},
  );
  // Upright, back camera facing magnetic south: device x→west, y→up, z→north.
  const south = [-1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0];
  const east = [0.0, 0.0, -1.0, -1.0, 0.0, 0.0, 0.0, 1.0, 0.0];

  testWidgets('names what the camera is pointing at', (t) async {
    final c = StreamController<List<double>>(sync: true);
    addTearDown(c.close);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        clockProvider.overrideWith((_) => Stream.value(now)),
        skyCatalogProvider.overrideWith((_) async => SkyCatalog.empty),
      ],
      child: MaterialApp(
        home: SkyCameraScreen(things: [saturn], tracks: const [], orientationStream: c.stream, camera: false),
      ),
    ));
    await t.pump();
    expect(find.text('Hold your phone up to the sky'), findsOneWidget);

    c.add(south);
    await t.pump();
    expect(find.text('That\'s Saturn'), findsOneWidget);

    c.add(east);
    await t.pump();
    expect(find.textContaining('Looking east'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
