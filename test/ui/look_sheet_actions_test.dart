import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/kit/kit.dart';
import 'package:lookup/ui/look_sheet.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.isPlus);
  final bool isPlus;
  @override
  Future<LookUpSettings> build() async =>
      LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, isPlus: isPlus, firstBadgeShown: true);
}

// Saturn, high in the south, well ahead.
final _start = DateTime.now().toUtc().add(const Duration(days: 2));
final _saturn = SkyEvent(
  id: 'planet:saturn:1',
  type: SkyEventType.planetHighlight,
  start: _start,
  peak: _start.add(const Duration(hours: 1)),
  end: _start.add(const Duration(hours: 3)),
  peakElevationDeg: 45,
  riseAzimuthDeg: 120,
  peakAzimuthDeg: 180,
  setAzimuthDeg: 240,
  details: const {'body': 'Saturn'},
);

Future<void> _mount(WidgetTester t, {required bool isPlus}) async {
  t.view.physicalSize = const Size(1179, 4000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [settingsProvider.overrideWith(() => _Settings(isPlus)), tonightSkyProvider.overrideWith((_) async => null)],
    child: MaterialApp(theme: buildLookUpTheme(), home: Scaffold(body: LookSheet(event: _saturn))),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('Pip itself is the way in: a card with Pip awake, not a plain button', (t) async {
    await _mount(t, isPlus: false);
    final card = find.byKey(const Key('pip-show-you'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Let Pip show you')), findsOneWidget);
    final pip = t.widget<PipMark>(find.descendant(of: card, matching: find.byType(PipMark)));
    expect(pip.asDot, isFalse, reason: 'the character, not the dot');
    expect(find.widgetWithText(FilledButton, 'Let Pip show you'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('touching the card squishes Pip before anything opens', (t) async {
    await _mount(t, isPlus: false);
    final card = find.byKey(const Key('pip-show-you'));
    PipMark pip() => t.widget<PipMark>(find.descendant(of: card, matching: find.byType(PipMark)));
    final before = pip().poke;
    final g = await t.startGesture(t.getCenter(card));
    await t.pump();
    expect(pip().poke, before + 1);
    final pressed = t.widget<AnimatedScale>(find.descendant(of: card, matching: find.byType(AnimatedScale)).first);
    expect(pressed.scale, lessThan(1), reason: 'it sinks under the finger');
    await g.cancel();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Photograph it and Invite sit in one row of tiles, with no Calendar', (t) async {
    await _mount(t, isPlus: false);
    final photo = find.byKey(const Key('photograph-it'));
    final invite = find.byKey(const Key('invite'));
    for (final f in [photo, invite]) {
      expect(f, findsOneWidget);
    }
    expect(t.getCenter(photo).dy, closeTo(t.getCenter(invite).dy, 0.5));
    expect(find.byKey(const Key('add-to-calendar')), findsNothing, reason: 'a calendar entry stands in for the alert');
    expect(find.text('Calendar'), findsNothing);
    expect(t.getSize(photo).height, closeTo(t.getSize(invite).height, 0.5), reason: 'the same size');
    expect(find.descendant(of: photo, matching: find.text('LookUp+')), findsNothing,
        reason: 'pictures are free (Pip\'s catch); a paid tag here reads as "you can\'t take pictures"');
    expect(find.byType(OutlinedButton), findsNothing, reason: 'no plain outlined buttons left');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('free: Photograph it goes straight to Pip\'s camera: no choice to tap through, no paywall', (t) async {
    await _mount(t, isPlus: false);
    await t.tap(find.byKey(const Key('photograph-it')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    // The live camera's own first step (no sky worked out in this test, so it asks for a place).
    expect(find.text('Set a location to see your sky.'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing, reason: 'no sheet in the way');
    expect(find.text('LookUp+'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('LookUp+: no tag either', (t) async {
    await _mount(t, isPlus: true);
    expect(find.descendant(of: find.byKey(const Key('photograph-it')), matching: find.text('LookUp+')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
