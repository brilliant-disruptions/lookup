import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/state/night_state.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/night_vision_button.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.s);
  final LookUpSettings s;
  @override
  Future<LookUpSettings> build() async => s;
}

/// Nashville: 10 pm local is dark, 1 pm is not.
final night = DateTime.utc(2026, 11, 6, 4);
final day = DateTime.utc(2026, 11, 6, 19);

Future<void> mount(WidgetTester t, DateTime at, {bool auto = true}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          () => _Settings(LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, nightVisionAuto: auto)),
        ),
        clockProvider.overrideWith((_) => Stream.value(at)),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: buildLookUpTheme(),
          builder: (context, child) => NightVision(enabled: ref.watch(nightVisionOnProvider), child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const OutsideScreen(
                        child: Scaffold(body: Center(child: NightVisionButton())),
                      ),
                    ),
                  ),
                  child: const Text('Go outside'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pump();
}

bool red(WidgetTester t) => find.byType(ColorFiltered).evaluate().isNotEmpty;

Future<void> open(WidgetTester t) async {
  await t.tap(find.text('Go outside'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('after dark, an outside screen turns the app red by itself, and leaving turns it back', (t) async {
    await mount(t, night);
    expect(red(t), isFalse); // everyday screens stay as they are
    await open(t);
    expect(red(t), isTrue);
    expect(find.textContaining('It\'s dark out'), findsOneWidget); // says why, once
    Navigator.of(t.element(find.byType(NightVisionButton))).pop();
    await t.pumpAndSettle();
    expect(red(t), isFalse);
  });

  testWidgets('by day, or with the setting off, nothing changes', (t) async {
    await mount(t, day);
    await open(t);
    expect(red(t), isFalse);
  });

  testWidgets('with the setting off, nothing changes at night either', (t) async {
    await mount(t, night, auto: false);
    await open(t);
    expect(red(t), isFalse);
  });

  testWidgets('the eye on an outside screen decides for that visit only', (t) async {
    await mount(t, night);
    await open(t);
    await t.tap(find.byType(NightVisionButton));
    await t.pumpAndSettle();
    expect(red(t), isFalse); // they switched it off here
    Navigator.of(t.element(find.byType(NightVisionButton))).pop();
    await t.pumpAndSettle();
    await open(t);
    expect(red(t), isTrue); // a new visit starts fresh
  });
}
