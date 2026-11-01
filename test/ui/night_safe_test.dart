import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/state/night_state.dart';
import 'package:lookup/state/providers.dart';
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

Future<void> mount(WidgetTester t, DateTime at, {bool on = true, double? lat = 36.17}) async {
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          () => _Settings(LookUpSettings(latitude: lat, longitude: lat == null ? null : -86.78, onboarded: true, nightVision: on)),
        ),
        clockProvider.overrideWith((_) => Stream.value(at)),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: buildLookUpTheme(),
          builder: (context, child) => NightVision(enabled: ref.watch(nightVisionOnProvider), child: child!),
          home: const Scaffold(body: Text('Tonight')),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

bool red(WidgetTester t) => find.byType(ColorFiltered).evaluate().isNotEmpty;

void main() {
  testWidgets('after sunset the whole app is red, on every screen, with no button to press', (t) async {
    await mount(t, night);
    expect(red(t), isTrue);
  });

  testWidgets('by day it stays in true colours', (t) async {
    await mount(t, day);
    expect(red(t), isFalse);
  });

  testWidgets('switched off in Settings, night stays in true colours', (t) async {
    await mount(t, night, on: false);
    expect(red(t), isFalse);
  });

  testWidgets('with no location yet, it never guesses it\'s night', (t) async {
    await mount(t, night, lat: null);
    expect(red(t), isFalse);
  });
}
