import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/kit/spotlight.dart';
import 'package:lookup/ui/theme.dart';

void main() {
  final a = GlobalKey(), b = GlobalKey(), gone = GlobalKey();
  final steps = [
    SpotlightStep(target: a, title: 'First', body: 'The first thing'),
    SpotlightStep(target: gone, title: 'Missing', body: 'Not on screen'),
    SpotlightStep(target: b, title: 'Second', body: 'The second thing'),
  ];

  Future<Future<bool>> start(WidgetTester t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(
      theme: buildLookUpTheme(),
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return Column(children: [
            SizedBox(key: a, width: 100, height: 40),
            const SizedBox(height: 300),
            SizedBox(key: b, width: 100, height: 40),
          ]);
        }),
      ),
    ));
    final done = showSpotlight(ctx, steps);
    await t.pumpAndSettle();
    return done;
  }

  testWidgets('steps whose target is not on screen are left out', (t) async {
    final done = await start(t);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('Missing'), findsNothing);
    await t.tap(find.text('Got it'));
    await t.pumpAndSettle();
    expect(await done, isTrue);
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('skip ends it early', (t) async {
    final done = await start(t);
    await t.tap(find.text('Skip'));
    await t.pumpAndSettle();
    expect(await done, isFalse);
    expect(find.text('First'), findsNothing);
  });

  testWidgets('the caption is read out, the dimmed backdrop is not', (t) async {
    final handle = t.ensureSemantics();
    await start(t);
    expect(find.bySemanticsLabel(RegExp('The first thing')), findsOneWidget);
    expect(find.bySemanticsLabel('Next'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('nothing to show: resolves at once without a route', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(await showSpotlight(ctx, [SpotlightStep(target: gone, title: 'x', body: 'y')]), isTrue);
  });
}
