import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/tonight.dart';
import 'package:lookup/domain/sky/visibility.dart';
import 'package:lookup/ui/sky/sky_thing.dart';
import 'package:lookup/ui/sky/up_tonight.dart';
import 'package:lookup/ui/theme.dart';

final _now = DateTime.utc(2026, 10, 20, 2);

/// Seeable or not, up now or later tonight.
SkyThing _thing(String id, String name, {double mag = 0, bool seeable = true, bool up = true, String kind = 'Planet'}) {
  final verdict = Seeability.values.firstWhere((v) => v.yes == seeable);
  return SkyThing(
    id: id,
    name: name,
    kind: kind,
    position: (_) => Horizontal(270, up ? 40 : -10),
    mag: mag,
    finder: const {},
    sighting: SkySighting(
      best: _now.add(const Duration(hours: 3)),
      altDeg: 40,
      azDeg: 120,
      verdict: verdict,
      visibleFrom: up ? _now.subtract(const Duration(hours: 1)) : _now.add(const Duration(hours: 2)),
      visibleTo: _now.add(const Duration(hours: 5)),
    ),
  );
}

void main() {
  test('a short list: only what can be seen, what is up now first, never more than five', () {
    final best = tonightsBest(
      moon: _thing('moon', 'The Moon', mag: -12, up: false, kind: 'Moon'),
      planets: [
        _thing('planet:mars', 'Mars', mag: 1),
        _thing('planet:jupiter', 'Jupiter', mag: -2),
        _thing('planet:mercury', 'Mercury', mag: 0, seeable: false),
      ],
      showpieces: [for (var i = 0; i < 4; i++) _thing('show:$i', 'Show $i', mag: 4.0 + i, kind: 'Cluster')],
      constellations: [for (var i = 0; i < 4; i++) _thing('con:$i', 'Con $i', mag: 2, kind: 'Constellation')],
      now: _now,
    );
    expect(best.map((x) => x.id), ['planet:jupiter', 'planet:mars', 'show:0', 'show:1', 'moon'],
        reason: 'up now first (brightest planet leading), the Moon later tonight last; Mercury can\'t be seen');
    expect(upNow(best.first, _now), isTrue);
    expect(upNow(best.last, _now), isFalse);
  });

  testWidgets('Show me only on what is up now; the rest say when, and open their sheet', (t) async {
    final opened = <String>[], shown = <String>[];
    final things = [_thing('planet:jupiter', 'Jupiter', mag: -2), _thing('moon', 'The Moon', mag: -12, up: false, kind: 'Moon')];
    await t.pumpWidget(MaterialApp(
      theme: buildLookUpTheme(),
      home: Scaffold(
        body: ListView(children: [
          UpTonightCard(
            things: things,
            now: _now,
            clouds: 'Clear until 6:00 AM',
            onOpen: (x) => opened.add(x.id),
            onShow: (x) => shown.add(x.id),
          ),
        ]),
      ),
    ));
    // Closed to start with: one line, so the sky stays in view.
    expect(find.text('Jupiter and the Moon'), findsOneWidget);
    expect(find.text('1 up now'), findsOneWidget);
    expect(find.text('Clear until 6:00 AM'), findsOneWidget);
    expect(find.text('Show me'), findsNothing);
    final closed = t.getSize(find.byKey(const Key('up-tonight'))).height;
    expect(closed, lessThan(110));
    await t.tap(find.byKey(const Key('up-tonight-toggle')));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const Key('up-tonight'))).height, greaterThan(closed));
    expect(find.text('Show me'), findsOneWidget);
    expect(find.text('Up now, in the west'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing, reason: 'words, never degrees');
    await t.tap(find.text('Show me'));
    expect(shown, ['planet:jupiter']);
    await t.tap(find.text('The Moon'));
    expect(opened, ['moon']);
    // And it closes again.
    await t.tap(find.byKey(const Key('up-tonight-toggle')));
    await t.pumpAndSettle();
    expect(find.text('Show me'), findsNothing);
  });

  test('the closed card in a line', () {
    final j = _thing('planet:jupiter', 'Jupiter'), m = _thing('moon', 'The Moon', kind: 'Moon'), s = _thing('planet:saturn', 'Saturn');
    expect(UpTonightCard.summary(const []), 'Nothing well placed tonight');
    expect(UpTonightCard.summary([m]), 'The Moon');
    expect(UpTonightCard.summary([j, m]), 'Jupiter and the Moon');
    expect(UpTonightCard.summary([s, m, j, j, j]), 'Saturn, the Moon and 3 more');
  });

  testWidgets('a night with nothing well placed says so, and sells nothing', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildLookUpTheme(),
      home: Scaffold(body: UpTonightCard(things: const [], now: _now, onOpen: (_) {}, onShow: (_) {})),
    ));
    expect(find.text('Nothing well placed tonight'), findsOneWidget);
    expect(find.text('Show me'), findsNothing);
  });
}
