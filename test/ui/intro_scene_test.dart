import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/ui/intro_scene.dart';
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/theme.dart';

Widget _host({bool reduceMotion = false}) => MaterialApp(
  theme: buildLookUpTheme(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: const Scaffold(body: SizedBox(height: 340, child: IntroScene())),
  ),
);

void main() {
  testWidgets('loops the station, a Starlink train and an aurora, each with its tap', (t) async {
    await t.pumpWidget(_host());
    await t.pump(const Duration(seconds: 3));
    expect(find.bySemanticsLabel(RegExp('ISS flyover in 10 min')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 5500));
    expect(find.bySemanticsLabel(RegExp('Starlink train in 10 min')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 5500));
    expect(find.bySemanticsLabel(RegExp('Aurora now')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 5500));
    expect(find.bySemanticsLabel(RegExp('ISS flyover in 10 min')), findsOneWidget); // and round again
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with reduced motion it holds the station mid-pass', (t) async {
    await t.pumpWidget(_host(reduceMotion: true));
    await t.pump(const Duration(seconds: 20));
    expect(find.bySemanticsLabel(RegExp('ISS flyover in 10 min')), findsOneWidget);
    expect(t.hasRunningAnimations, isFalse);
    expect(t.binding.transientCallbackCount, 0, reason: 'Pip holds still too');
    // Pip waits where the station rose, not mid-flight.
    final box = t.getRect(find.byType(IntroScene));
    final rise = introRisePoint(SkyEventType.iss, box.size);
    expect(t.getCenter(find.byType(PipMark)), box.topLeft + rise);
    expect(t.widget<PipMark>(find.byType(PipMark)).state, PipState.resting);
  });

  // Pip gets there first: it is on the rise point before each sight comes
  // up, so the intro teaches "look where Pip is".
  testWidgets('Pip reaches each rise point before the sight rises', (t) async {
    await t.pumpWidget(_host());
    final box = t.getRect(find.byType(IntroScene));
    for (final (i, type) in [SkyEventType.iss, SkyEventType.starlinkTrain, SkyEventType.auroraNow].indexed) {
      // 0.095 of the way into each 5.5 s scene: landed, nothing risen yet (rise starts at 0.1).
      await t.pump(Duration(milliseconds: i == 0 ? 523 : 5500));
      expect(t.getCenter(find.byType(PipMark)), box.topLeft + introRisePoint(type, box.size), reason: '$type');
    }
    await t.pumpWidget(const SizedBox());
  });
}
