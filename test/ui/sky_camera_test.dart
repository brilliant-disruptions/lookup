import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/pip/pip_aim.dart';
import 'package:lookup/ui/sky/sky_camera_screen.dart';
import 'package:lookup/ui/sky/sky_thing.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);
}

class _Nerd extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, nerdMode: true);
}

/// New to the sky camera; edits stay in memory.
class _New extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true);

  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

class _Home extends HomeNotifier {
  _Home(this.events);
  final List<SkyEvent> events;
  @override
  Future<HomeData> build() async => HomeData(events: events, aurora: null, lastRefresh: DateTime.now(), errors: const []);
  @override
  Future<void> refresh({bool force = false, bool quick = false}) async {}
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
    expect(find.text('That\'s Saturn. Tap Pip to catch it!'), findsOneWidget);

    c.add(east);
    await t.pump();
    // Facing east, Saturn is to the right and a little up: Pip says so.
    expect(find.text('Turn right, tilt up a little for Saturn'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  // Pip guides: it leaves the shutter, flies out over the sky to what it's
  // leading you to, and lands on it, as the plain light, in the middle.
  testWidgets('Pip flies out of the shutter to guide, and lands on it as the dot', (t) async {
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
    c.add(east);
    await t.pump();
    final pip = find.byKey(const Key('sky-pip'));
    final out = t.widget<PipAim>(pip);
    expect(out.onTarget, isFalse);
    expect(out.words, contains('Saturn'));
    expect(out.ring, isFalse, reason: 'nothing on screen but Pip');
    expect(out.launchFrom!.y, greaterThan(200), reason: 'sets off from the shutter at the foot');
    expect(out.toward.x, greaterThan(0), reason: 'Saturn is to the right');
    expect(find.byKey(const Key('pip-on-target')), findsNothing);
    expect(find.byType(PipMark), findsNothing, reason: 'Pip is out guiding, not sitting in the shutter');

    c.add(south);
    await t.pump();
    final on = t.widget<PipAim>(pip);
    expect(on.onTarget, isTrue, reason: 'Saturn is in the middle');
    expect(find.bySemanticsLabel('Catch Saturn'), findsWidgets);
    expect(find.byKey(const Key('pip-on-target')), findsOneWidget, reason: 'tap Pip itself to catch it');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('"Pip, find something else" leads to the next thing', (t) async {
    final c = StreamController<List<double>>(sync: true);
    addTearDown(c.close);
    final jupiter = SkyThing(
      id: 'planet:jupiter',
      name: 'Jupiter',
      kind: 'Planet',
      position: (_) => const Horizontal(100, 30),
      mag: -2.6,
      finder: const {'planet': 'Jupiter'},
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        clockProvider.overrideWith((_) => Stream.value(now)),
        skyCatalogProvider.overrideWith((_) async => SkyCatalog.empty),
      ],
      child: MaterialApp(
        home: SkyCameraScreen(things: [saturn, jupiter], tracks: const [], orientationStream: c.stream, camera: false),
      ),
    ));
    await t.pump();
    c.add(south);
    await t.pump();
    // The brighter planet first.
    expect(t.widget<PipAim>(find.byKey(const Key('sky-pip'))).words, endsWith('for Jupiter'));
    await t.tap(find.byKey(const Key('find-something-else')));
    await t.pump();
    expect(t.widget<PipAim>(find.byKey(const Key('sky-pip'))).words, endsWith('for Saturn'));
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

  testWidgets('the next sight counts down in the top right', (t) async {
    final pass = SkyEvent(
      id: 'iss:1',
      type: SkyEventType.iss,
      start: now.add(const Duration(minutes: 12)),
      peak: now.add(const Duration(minutes: 15)),
      end: now.add(const Duration(minutes: 18)),
      peakElevationDeg: 60,
      riseAzimuthDeg: 250,
      peakAzimuthDeg: 180,
      setAzimuthDeg: 90,
    );
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        clockProvider.overrideWith((_) => Stream.value(now)),
        skyCatalogProvider.overrideWith((_) async => SkyCatalog.empty),
        homeProvider.overrideWith(() => _Home([pass])),
      ],
      child: MaterialApp(
        home: SkyCameraScreen(things: [saturn], tracks: const [], orientationStream: const Stream.empty(), camera: false),
      ),
    ));
    await t.pump();
    await t.pump();
    final chip = find.byKey(const Key('camera-countdown'));
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.text('12m 00s')), findsOneWidget);
    final box = t.getRect(chip);
    final screen = t.getRect(find.byType(SkyCameraScreen));
    expect(box.right, greaterThan(screen.width * 0.85), reason: 'top right');
    expect(box.top, lessThan(screen.height * 0.15));
    await t.pumpWidget(const SizedBox());
  });

  // A catch needs a picture: with the camera off, tapping Pip turns it on
  // and logs nothing.
  testWidgets('tapping Pip on the target with the camera off turns it on rather than logging', (t) async {
    final c = StreamController<List<double>>(sync: true);
    addTearDown(c.close);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        clockProvider.overrideWith((_) => Stream.value(now)),
        skyCatalogProvider.overrideWith((_) async => SkyCatalog.empty),
        homeProvider.overrideWith(() => _Home(const [])),
      ],
      child: MaterialApp(
        home: SkyCameraScreen(things: [saturn], tracks: const [], orientationStream: c.stream, camera: false),
      ),
    ));
    await t.pump();
    c.add(south);
    await t.pump();
    expect(find.byTooltip('Show camera'), findsOneWidget);
    await t.tap(find.byKey(const Key('pip-on-target')));
    await t.pump();
    expect(find.textContaining('Camera on'), findsOneWidget);
    expect(find.byTooltip('Hide camera'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  // Words on the main path; the numbers only for someone who asked for them.
  testWidgets('nerd mode adds exact numbers; off (the default) there is no degree sign anywhere', (t) async {
    Future<void> open(SettingsNotifier Function() settings) async {
      final c = StreamController<List<double>>(sync: true);
      addTearDown(c.close);
      await t.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith(settings),
          clockProvider.overrideWith((_) => Stream.value(now)),
          skyCatalogProvider.overrideWith((_) async => SkyCatalog.empty),
          homeProvider.overrideWith(() => _Home(const [])),
        ],
        child: MaterialApp(
          home: SkyCameraScreen(things: [saturn], tracks: const [], orientationStream: c.stream, camera: false),
        ),
      ));
      await t.pump();
      c.add(east);
      await t.pump();
    }

    expect(const LookUpSettings().nerdMode, isFalse);
    await open(_Settings.new);
    expect(find.byKey(const Key('nerd-numbers')), findsNothing);
    expect(find.textContaining('°'), findsNothing);
    await t.pumpWidget(const SizedBox());

    await open(_Nerd.new);
    expect(find.byKey(const Key('nerd-numbers')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Az \d+\.\d° · Alt')), findsOneWidget);
    expect(find.textContaining('Turn right'), findsOneWidget, reason: 'the words stay');
    await t.pumpWidget(const SizedBox());
  });
}
