import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
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
}
