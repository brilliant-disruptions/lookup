import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/ui/sky/sky_panorama.dart';
import 'package:lookup/ui/sky/sky_thing.dart';
import 'package:lookup/ui/theme.dart';

SkyThing fixed(String id, String name, String kind, double az, double alt) => SkyThing(
      id: id,
      name: name,
      kind: kind,
      position: (_) => Horizontal(az, alt),
      mag: 0,
      finder: const {},
    );

void main() {
  final now = DateTime.utc(2026, 10, 28, 2, 30);

  group('bestFacing', () {
    test('turns toward the Moon and planets', () {
      final things = [
        fixed('moon', 'The Moon', 'Full Moon', 95, 20),
        fixed('planet:saturn', 'Saturn', 'Planet', 130, 30),
        fixed('planet:mars', 'Mars', 'Planet', 300, 10),
      ];
      expect(bestFacing(things, now), anyOf(90, 135));
    });

    test('ignores things below the horizon', () {
      final things = [
        fixed('moon', 'The Moon', 'Full Moon', 0, -10),
        fixed('planet:jupiter', 'Jupiter', 'Planet', 270, 40),
      ];
      expect(bestFacing(things, now), 270);
    });
  });

  group('SkyPanorama', () {
    Future<List<SkyThing>> pump(WidgetTester t, List<SkyThing> things) async {
      final tapped = <SkyThing>[];
      t.view.physicalSize = const Size(1179, 2556);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: buildLookUpTheme(),
        home: Scaffold(
          body: SkyPanorama(
            time: now,
            lat: 36.17,
            lon: -86.78,
            catalog: SkyCatalog.empty,
            things: things,
            onTap: tapped.add,
          ),
        ),
      ));
      return tapped;
    }

    testWidgets('starts facing the Moon, and dragging turns round', (t) async {
      await pump(t, [fixed('moon', 'The Moon', 'Full Moon', 90, 25)]);
      expect(find.text('Facing east'), findsOneWidget);

      // Drag the sky to the left: you turn to your right, toward the south.
      await t.drag(find.byKey(SkyPanorama.canvasKey), const Offset(-140, 0));
      await t.pumpAndSettle();
      expect(find.text('Facing east'), findsNothing);
      expect(find.textContaining('south'), findsOneWidget);
    });

    testWidgets('the arrows turn by an eighth of a circle', (t) async {
      await pump(t, [fixed('moon', 'The Moon', 'Full Moon', 180, 25)]);
      expect(find.text('Facing south'), findsOneWidget);
      await t.tap(find.byTooltip('Turn right'));
      await t.pumpAndSettle();
      expect(find.text('Facing southwest'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await t.tap(find.byTooltip('Turn left'));
        await t.pumpAndSettle();
      }
      expect(find.text('Facing southeast'), findsOneWidget);
    });

    testWidgets('tapping a planet opens it', (t) async {
      final saturn = fixed('planet:saturn', 'Saturn', 'Planet', 180, 45);
      final tapped = await pump(t, [saturn]);
      // Facing south with Saturn dead ahead: it sits mid-width, at 45° up.
      final box = t.getRect(find.byKey(SkyPanorama.canvasKey));
      const groundH = 64.0;
      final horizon = box.height - groundH;
      final y = horizon - 45 / 90 * (horizon - 18);
      await t.tapAt(Offset(box.center.dx, box.top + y));
      expect(tapped.map((x) => x.id), ['planet:saturn']);

      tapped.clear();
      await t.tapAt(Offset(box.center.dx, box.top + 20)); // empty sky
      expect(tapped, isEmpty);
    });
  });
}
