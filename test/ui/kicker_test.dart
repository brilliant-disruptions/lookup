import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/kit/kit.dart';

void main() {
  // A pass just after midnight reads "Tomorrow morning · 12:09 AM": the longest
  // kicker the app writes. On a narrow phone with big text it must wrap, not
  // run off the edge (this broke the story test whenever CI ran late at night).
  testWidgets('a long kicker wraps in a narrow column', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 200,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Kicker('Tomorrow morning · 12:09 AM')]),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(find.text('Tomorrow morning · 12:09 AM'), findsOneWidget);
    expect(t.getSize(find.byType(Kicker)).height, greaterThan(20), reason: 'two lines, all of it still there');
  });

  // Kickers sit straight inside other Rows (the share card, Look up now); the
  // live one keeps its dot and its natural width there.
  testWidgets('a live kicker inside a row keeps its dot', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: Row(children: [Kicker('Get ready', live: true), Spacer()])),
    ));
    expect(t.takeException(), isNull);
    expect(find.text('Get ready'), findsOneWidget);
  });
}
