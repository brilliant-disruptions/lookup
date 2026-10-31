import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/intro_scene.dart';
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
  });
}
