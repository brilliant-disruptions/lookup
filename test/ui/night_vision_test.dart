import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/sky/night_vision.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/night_vision_button.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async => const LookUpSettings();

  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

void main() {
  testWidgets('one tap turns night vision on and off', (t) async {
    final container = ProviderContainer(overrides: [settingsProvider.overrideWith(_Settings.new)]);
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLookUpTheme(),
        home: const Scaffold(body: Center(child: NightVisionButton())),
      ),
    ));
    await t.pump();
    bool on() => container.read(settingsProvider).value!.nightVision;
    expect(on(), isFalse);
    expect(t.getSemantics(find.byType(NightVisionButton)), matchesSemantics(
      label: 'Night vision on',
      isButton: true,
      hasToggledState: true,
      isToggled: false,
      hasTapAction: true,
    ));

    await t.tap(find.byType(NightVisionButton));
    await t.pump();
    expect(on(), isTrue);
    expect(find.textContaining('red light keeps your eyes'), findsOneWidget);
    expect(find.byTooltip('Night vision off'), findsOneWidget);

    await t.tap(find.byType(NightVisionButton));
    await t.pump();
    expect(on(), isFalse);
  });

  test('darkest setting is exactly the deep-red filter: no green or blue light at all', () {
    expect(nightVisionMatrixAt(1), nightVisionMatrix);
    for (final i in [5, 6, 7, 8, 10, 11, 12, 13]) {
      expect(nightVisionMatrixAt(1)[i], 0, reason: 'entry $i');
    }
  });

  test('in a lit room it still shifts toward red, it does not just switch off', () {
    final m = nightVisionMatrixAt(minRedStrength);
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
    await t.pumpWidget(at(minRedStrength));
    await t.pump(const Duration(seconds: 1));
    expect(matrix()[6], inExclusiveRange(0, 1 - minRedStrength));
    await t.pump(const Duration(seconds: 2));
    expect(matrix()[6], closeTo(1 - minRedStrength, 1e-9));
  });
}
