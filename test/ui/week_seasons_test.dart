import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/plan/week_view.dart';
import 'package:lookup/domain/sky/seasons.dart';
import 'package:lookup/ui/theme.dart';
import 'package:lookup/ui/week_views.dart';

/// Equinoxes and solstices on the Week tab: a mark on the day's label and a
/// line under the bars, named for the hemisphere, never a marker on a bar.
void main() {
  test('the solstice falls on its own local day, and only that one', () {
    // 21 Dec 2026 20:50 UTC: the 21st in Denver and in London.
    final nights = weekNights(const [], DateTime(2026, 12, 18, 12));
    final marked = [for (final n in nights) if (n.season != null) n];
    expect(marked.length, 1);
    expect(marked.single.date, DateTime(2026, 12, 21));
    expect(marked.single.season!.mark, SeasonMark.decemberSolstice);
    expect(marked.single.events, isEmpty, reason: 'a date, not a sight');
  });

  Future<void> pump(WidgetTester t, double lat) async {
    t.view.physicalSize = const Size(375, 667);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final now = DateTime(2026, 12, 18, 12);
    final weeks = glanceWeeks(const [], const [], now);
    await t.pumpWidget(MaterialApp(
      theme: buildLookUpTheme(),
      home: Scaffold(
        body: GlancePage(
          weeks: weeks,
          night: dayOf(now),
          pick: null,
          isPlus: false,
          onNight: (_) {},
          onPick: (_) {},
          bottomPadding: 0,
          latDeg: lat,
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('north: winter solstice, the longest night, on a small phone', (t) async {
    await pump(t, 39.74);
    expect(find.byKey(const Key('season-mark-decemberSolstice')), findsOneWidget);
    expect(find.byKey(const Key('season-decemberSolstice')), findsOneWidget);
    expect(find.textContaining('Winter solstice'), findsOneWidget);
    expect(find.textContaining('longest night'), findsOneWidget);
    expect(find.textContaining('°'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('south: the same day is the summer solstice', (t) async {
    await pump(t, -33.87);
    expect(find.textContaining('Summer solstice'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
