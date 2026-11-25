import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/events/year_ahead.dart';
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/year_ahead_screen.dart';

/// "This year": months in order, the seasons named for the place, and no
/// degree sign anywhere on it.
void main() {
  testWidgets('a year of big dates on a small phone, in words', (t) async {
    t.view.physicalSize = const Size(375, 667);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // Denver, from 25 Nov 2026.
    final year = yearAhead(now: DateTime.utc(2026, 11, 25, 18), latDeg: 39.74, lonDeg: -104.99);
    await t.pumpWidget(ProviderScope(
      overrides: [yearAheadProvider.overrideWith((ref) async => year)],
      child: MaterialApp(theme: buildLookUpTheme(), home: const YearAheadScreen()),
    ));
    await t.pumpAndSettle();
    expect(find.text('This year'), findsOneWidget);
    expect(find.text('December 2026'), findsOneWidget);
    expect(find.text('Supermoon rising'), findsWidgets);
    await t.scrollUntilVisible(find.byKey(const Key('year-season-decemberSolstice-2026')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Winter solstice'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
