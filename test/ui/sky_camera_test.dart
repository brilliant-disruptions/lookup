import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/sky/sky_camera_screen.dart';
import 'package:lookup/ui/sky/sky_thing.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
}

/// New to the sky camera; edits stay in memory.
class _New extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);

  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
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

  // Every screen you hold up to the sky has Pip in it and reads the same, so
  // the sky camera can't be the one without.
  testWidgets('Pip is there, and settles on what the camera is pointing at', (t) async {
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
    expect(find.byType(ScanTopBar), findsOneWidget);
    expect(t.widget<PipMark>(find.byType(PipMark)).state, PipState.idle);
    c.add(south);
    await t.pump();
    expect(t.widget<PipMark>(find.byType(PipMark)).state, PipState.resting, reason: 'Saturn is in the middle');
    c.add(east);
    await t.pump();
    expect(t.widget<PipMark>(find.byType(PipMark)).state, PipState.idle);
    await t.pumpWidget(const SizedBox());
  });

  // Guidance is said once, not every time: after the first visit the screen
  // is just the sky, Pip and the direction words.
  testWidgets('the cloud and figure-8 hint shows the first time only', (t) async {
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith(_New.new),
      clockProvider.overrideWith((_) => Stream.value(now)),
      skyCatalogProvider.overrideWith((_) async => SkyCatalog.empty),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    Widget screen() => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: SkyCameraScreen(things: [saturn], tracks: const [], orientationStream: const Stream.empty(), camera: false),
          ),
        );
    await t.pumpWidget(screen());
    await t.pump();
    expect(find.byType(ScanHint), findsOneWidget);
    expect(container.read(settingsProvider).value!.skyCameraCoached, isTrue);

    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(screen());
    await t.pump();
    expect(find.byType(ScanHint), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
