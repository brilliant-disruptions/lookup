import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/pointing.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/photo/camera.dart';
import 'package:lookup/domain/photo/capture_plan.dart';
import 'package:lookup/domain/photo/exposure.dart';
import 'package:lookup/domain/photo/framing.dart';
import 'package:lookup/domain/photo/shot_plan.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/services/capture/capture_backend.dart';
import 'package:lookup/services/capture/timelapse_encoder.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/pip/pip_aim.dart';
import 'package:lookup/ui/pro_camera_screen.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.plus);
  final bool plus;
  @override
  Future<LookUpSettings> build() async =>
      LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, isPlus: plus, firstBadgeShown: true);
}

class _Camera extends CaptureBackend {
  final starts = <({String lens, Exposure? exposure})>[];
  final _out = StreamController<CaptureFrame>.broadcast();
  bool awake = false;

  static const caps = CameraCaps(
    lenses: [
      CameraLens(id: 'main', kind: LensKind.wide, longFovDeg: 66, shortFovDeg: 52, fNumber: 1.8),
      CameraLens(id: 'tele', kind: LensKind.tele, longFovDeg: 30, shortFovDeg: 23, fNumber: 2.8),
    ],
    manual: true,
    minShutterS: 1 / 8000,
    maxShutterS: 1,
    minIso: 32,
    maxIso: 3200,
  );

  void send(CaptureFrame f) => _out.add(f);

  @override
  Future<CameraCaps> open() async => caps;
  /// A real camera's preview fills whatever it's given, like a Texture.
  @override
  Widget? preview() => const ColoredBox(color: Color(0xFF0B1328), child: SizedBox.expand());
  @override
  Future<void> start(CapturePlan plan) async {}
  @override
  Future<void> startWith({required String lensId, Exposure? exposure}) async => starts.add((lens: lensId, exposure: exposure));
  @override
  Stream<CaptureFrame> get frames => _out.stream;
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> keepAwake(bool on) async => awake = on;
}

class _Encoder implements VideoEncoder {
  int frames = 0;
  @override
  Future<bool> begin({required String path, required int width, required int height, required int fps, int rotation = 0}) async => true;
  @override
  Future<int> add(CaptureFrame f) async => ++frames;
  @override
  Future<({String path, int frames, double seconds})?> end() async => null;
  @override
  Future<void> cancel() async {}
}

void main() {
  // The Moon, due south and a third of the way up.
  const moonAt = SkyDir(180, 30);
  final moon = ShotTarget(name: 'the Moon', subject: ShotSubject.moon, position: (_) => const Horizontal(180, 30));
  const w = 80, h = 60;

  CaptureFrame moonFrame(int level) {
    final y = Uint8List(w * h);
    for (var yy = 20; yy < 40; yy++) {
      for (var xx = 30; xx < 50; xx++) {
        y[yy * w + xx] = level;
      }
    }
    return CaptureFrame(width: w, height: h, y: y);
  }

  Future<({_Camera cam, StreamController<List<double>> rot})> open(WidgetTester t,
      {ShotTarget? target, ProMode mode = ProMode.photo, DateTime Function()? clock}) async {
    final cam = _Camera();
    final rot = StreamController<List<double>>.broadcast(sync: true);
    addTearDown(rot.close);
    await t.pumpWidget(ProviderScope(
      overrides: [settingsProvider.overrideWith(() => _Settings(true))],
      child: MaterialApp(
        home: ProCameraScreen(
          target: target ?? moon,
          mode: mode,
          backend: cam,
          encoder: _Encoder(),
          orientationStream: rot.stream,
          clock: clock,
          tempDir: '/tmp',
        ),
      ),
    ));
    await t.pump();
    await t.pump();
    return (cam: cam, rot: rot);
  }

  testWidgets('LookUp+ only: free gets the paywall', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [settingsProvider.overrideWith(() => _Settings(false))],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(onPressed: () => openProCamera(context, ref, moon), child: const Text('go')),
        ),
      ),
    ));
    await t.pump();
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('The Pro camera: the right settings'), findsOneWidget);
    expect(find.byType(ProCameraScreen), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the Moon: the zoom lens and a fast shutter go to the camera; numbers only in the detail line', (t) async {
    final c = await open(t);
    expect(c.cam.starts, isNotEmpty);
    expect(c.cam.starts.last.lens, 'tele');
    expect(c.cam.starts.last.exposure!.shutterS, lessThan(1 / 250));
    expect(c.cam.awake, isTrue, reason: 'the screen stays on');
    expect(find.textContaining('ISO'), findsOneWidget, reason: 'the one detail line');
    expect(find.textContaining('°'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('it waits for pointed, level and steady, with Pip leading the way', (t) async {
    final c = await open(t);
    expect(find.text('Take it anyway'), findsOneWidget);
    // Hold it, level, on the Moon, for a moment.
    for (var i = 0; i < 6; i++) {
      c.rot.add(levelPose(moonAt));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('pro-pip')), findsOneWidget);
    expect(t.widget<PipAim>(find.byKey(const Key('pro-pip'))).onTarget, isTrue);
    expect(find.text('Take it'), findsOneWidget);
    // Turned away: Pip says which way.
    c.rot.add(levelPose(const SkyDir(90, 30)));
    await t.pump();
    expect(find.text('Take it anyway'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a frame too bright: it says so and darkens the exposure itself', (t) async {
    final c = await open(t);
    final before = c.cam.starts.last.exposure!.shutterS;
    c.cam.send(moonFrame(255));
    await t.pump();
    await t.pump();
    expect(find.byKey(const Key('pro-advice')), findsOneWidget);
    expect(find.textContaining('Too bright'), findsOneWidget);
    expect(c.cam.starts.last.exposure!.shutterS, lessThan(before));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Take it: a self-timer, then frames counted into the picture', (t) async {
    final c = await open(t);
    await t.tap(find.byKey(const Key('pro-go')));
    await t.pump();
    expect(find.byKey(const Key('pro-countdown')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('pro-shooting')), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      c.cam.send(moonFrame(200));
      await t.pump();
    }
    await t.pump();
    expect(find.text('Frame 5 of 40'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('timelapse: where to stand the phone, then it records by itself', (t) async {
    var now = DateTime.now().toUtc();
    final c = await open(t, mode: ProMode.timelapse, clock: () => now);
    final words = t.widget<Text>(find.byKey(const Key('pro-words'))).data!;
    expect(words.toLowerCase(), contains('prop it up'));
    expect(words, contains('pointing south'));
    expect(words, contains('-second clip'));
    expect(words, isNot(contains('°')));
    expect(find.text('Start the timelapse'), findsOneWidget);
    expect(find.textContaining('a frame every'), findsOneWidget);
    await t.tap(find.byKey(const Key('pro-go')));
    await t.pump();
    await t.pump();
    // Already up, so it's recording; frames arrive and one per interval is kept.
    for (var i = 0; i < 4; i++) {
      c.cam.send(moonFrame(120));
      await t.pump();
      now = now.add(const Duration(minutes: 1));
    }
    await t.pump();
    expect(find.textContaining('Recording · 4 of about'), findsOneWidget);
    expect(find.byKey(const Key('pro-stop')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
