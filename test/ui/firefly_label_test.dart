import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/pip/pip_aim.dart';

void main() {
  // Seen on a phone: "Rocket launch at twiligh" running off the right edge.
  testWidgets('the label beside Pip stays on screen near the edges', (t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    for (final x in [-180.0, 180.0]) {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PipAim(
            mode: PipMode.find,
            target: (x: x, y: 0),
            toward: (x: x.sign, y: 0),
            distanceDeg: 0,
            onTarget: true,
            words: "You're looking right at it",
            label: 'Rocket launch at twilight',
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 100));
      final r = t.getRect(find.text('Rocket launch at twilight'));
      expect(r.left, greaterThanOrEqualTo(0), reason: 'x=$x');
      expect(r.right, lessThanOrEqualTo(393), reason: 'x=$x');
    }
    await t.pumpWidget(const SizedBox());
  });
}
