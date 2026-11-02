import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/domain/sky/catalog.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/catch_it_screen.dart';

class _Settings extends SettingsNotifier {
  @override
  Future<LookUpSettings> build() async =>
      const LookUpSettings(latitude: 36.17, longitude: -86.78, placeName: 'Nashville', onboarded: true);
}

// A pass with no elements: Catch it draws an arc through rise, peak and set.
final _pass = SkyEvent(
  id: 'iss:catch',
  type: SkyEventType.iss,
  start: DateTime.utc(2026, 11, 3, 0, 5),
  peak: DateTime.utc(2026, 11, 3, 0, 7),
  end: DateTime.utc(2026, 11, 3, 0, 9),
  peakElevationDeg: 58,
  riseAzimuthDeg: 250,
  peakAzimuthDeg: 190,
  setAzimuthDeg: 100,
  details: const {'magnitude': -2.8},
);

Future<void> _settle(WidgetTester t, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the practice run plays the plan through to a picture, and saves nothing', (t) async {
    t.view.physicalSize = const Size(1179, 2556);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        skyCatalogProvider.overrideWith((_) async => SkyCatalog.fromJson(const {}, const {})),
      ],
      child: MaterialApp(home: CatchItScreen(event: _pass, practice: true)),
    ));
    await _settle(t);
    expect(find.text('Try it before it\'s real'), findsOneWidget);
    // Settings words only behind the detail line.
    expect(find.textContaining('ISO'), findsOneWidget);

    await t.tap(find.text('Start the practice run'));
    await t.pump();
    expect(find.text('Catching it'), findsWidgets);

    // The made-up pass runs in about 14 s.
    for (var i = 0; i < 40 && find.text('That\'s how it\'ll look').evaluate().isEmpty; i++) {
      await _settle(t, rounds: 5);
    }
    expect(find.text('That\'s how it\'ll look'), findsOneWidget);
    expect(find.text('A practice run: nothing was saved.'), findsOneWidget);
    expect(find.text('Add to your log'), findsNothing);
    expect(find.text('Share'), findsNothing);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
