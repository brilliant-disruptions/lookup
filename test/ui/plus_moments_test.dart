import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/places_screen.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.s);
  final LookUpSettings s;
  @override
  Future<LookUpSettings> build() async => s;
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

class _Plus implements PlusService {
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  final now = DateTime.now().toUtc();
  SkyLog seen(int n) => SkyLog.from([
        for (var i = 0; i < n; i++)
          Sighting(eventId: 'iss:$i', seen: true, at: now.subtract(Duration(days: i + 1)), type: SkyEventType.iss),
      ]);

  Future<ProviderContainer> pump(WidgetTester t, LookUpSettings s, Widget child, {int sightings = 0}) async {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Settings(s)),
      skyLogProvider.overrideWith((_) async => seen(sightings)),
      plusServiceProvider.overrideWithValue(_Plus()),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildLookUpTheme(), home: Scaffold(body: Center(child: child))),
    ));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('after a sighting: offered to someone really using it, once', (t) async {
    final c = await pump(t, LookUpSettings(firstOpenedAt: now.subtract(const Duration(days: 1))), const PlusAfterSighting(),
        sightings: 3);
    expect(find.textContaining('Starlink trains, aurora and your favourites'), findsOneWidget);
    expect(c.read(settingsProvider).value!.lastPlusAskAt, isNotNull);
    await t.tap(find.textContaining('Starlink trains, aurora'));
    await t.pumpAndSettle();
    expect(find.textContaining('You\'ve seen 3 things with LookUp'), findsOneWidget);
  });

  testWidgets('after a sighting: nothing on day one, or with LookUp+', (t) async {
    await pump(t, LookUpSettings(firstOpenedAt: now), const PlusAfterSighting(), sightings: 1);
    expect(find.textContaining('Starlink trains, aurora'), findsNothing);
    await pump(t, LookUpSettings(firstOpenedAt: now.subtract(const Duration(days: 30)), isPlus: true), const PlusAfterSighting(),
        sightings: 9);
    expect(find.textContaining('Starlink trains, aurora'), findsNothing);
  });

  testWidgets('a second saved place offers LookUp+ instead of saving', (t) async {
    const home = SavedPlace(name: 'Home', latitude: 36.17, longitude: -86.78);
    const cabin = SavedPlace(name: 'Cabin', latitude: 35.61, longitude: -83.49);
    late bool allowed;
    await pump(
      t,
      const LookUpSettings(places: [home]),
      Builder(builder: (context) {
        return TextButton(
          onPressed: () => allowed = canSaveOrOffer(context, const LookUpSettings(places: [home]), cabin),
          child: const Text('Save cabin'),
        );
      }),
    );
    await t.tap(find.text('Save cabin'));
    await t.pumpAndSettle();
    expect(allowed, isFalse);
    expect(find.textContaining('Save as many places as you like'), findsOneWidget);
  });
}
