import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/theme.dart';

/// A light tint, as in a dim room with How red nudged down.
const _tint = 0.3;

void main() {
  test('darkest setting is exactly the deep-red filter: no green or blue light at all', () {
    expect(nightVisionMatrixAt(1), nightVisionMatrix);
    for (final i in [5, 6, 7, 8, 10, 11, 12, 13]) {
      expect(nightVisionMatrixAt(1)[i], 0, reason: 'entry $i');
    }
  });

  test('a light tint shifts toward red but keeps colours recognisable', () {
    final m = nightVisionMatrixAt(_tint);
    // Green and blue are cut...
    expect(m[6], lessThan(1));
    expect(m[12], lessThan(1));
    // ...but colours are still recognisable.
    expect(m[6], greaterThan(0.5));
    // Alpha untouched at any strength.
    expect(m.sublist(15), [0, 0, 0, 1, 0]);
    // And strength 0 would be the true colours.
    expect(nightVisionMatrixAt(0), [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);
  });

  testWidgets('a new light reading eases the filter instead of jumping', (t) async {
    Widget at(double s) => NightVision(enabled: true, strength: s, child: const SizedBox());
    List<double> matrix() =>
        (t.widget<ColorFiltered>(find.byType(ColorFiltered)).colorFilter.toString())
            .split(RegExp(r'[\[\]]'))[1]
            .split(', ')
            .map(double.parse)
            .toList();
    await t.pumpWidget(at(1));
    expect(matrix()[6], 0);
    await t.pumpWidget(at(_tint));
    await t.pump(const Duration(seconds: 1));
    expect(matrix()[6], inExclusiveRange(0, 1 - _tint));
    await t.pump(const Duration(seconds: 2));
    expect(matrix()[6], closeTo(1 - _tint, 1e-9));
  });

  testWidgets('turning red on or off keeps the app where it is', (t) async {
    Widget at(bool on) => MaterialApp(home: NightVision(enabled: on, strength: 1, child: const _Counter()));
    await t.pumpWidget(at(false));
    await t.tap(find.byType(_Counter));
    await t.pump();
    expect(find.text('1'), findsOneWidget);
    await t.pumpWidget(at(true)); // sunset
    await t.pump(const Duration(seconds: 3));
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(find.text('1'), findsOneWidget, reason: 'not rebuilt from scratch');
    await t.pumpWidget(at(false)); // switched off
    await t.pump(const Duration(seconds: 3));
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.text('1'), findsOneWidget);
  });
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var n = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: () => setState(() => n++), child: Text('$n', textDirection: TextDirection.ltr));
}
