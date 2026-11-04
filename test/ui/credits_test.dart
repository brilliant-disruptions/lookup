import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/credits_screen.dart';

void main() {
  test('NASA\'s Universe of Learning is credited as its policy asks', () {
    final pictures = credits.firstWhere((c) => c.what == 'Constellation pictures').who;
    expect(pictures, contains('Courtesy of NASA and NASA\'s Universe of Learning'));
    expect(pictures, contains('Stellarium'));
  });

  test('every outside source in the README is credited', () {
    final all = credits.map((c) => c.who).join(' ');
    for (final source in ['CelesTrak', 'NOAA Space Weather', 'Open-Meteo', 'Launch Library', 'd3-celestial', 'Natural Earth', 'Black Marble']) {
      expect(all, contains(source));
    }
  });

  testWidgets('the page lists them all', (t) async {
    t.view.physicalSize = const Size(1179, 6000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(home: CreditsScreen()));
    await t.pump();
    for (final c in credits) {
      expect(find.text(c.what), findsOneWidget);
    }
  });
}
