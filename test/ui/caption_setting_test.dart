import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/services/plus_service.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/paywall_sheet.dart';
import 'package:lookup/ui/settings_screen.dart';
import 'package:lookup/ui/theme.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.plus);
  final bool plus;
  @override
  Future<LookUpSettings> build() async => LookUpSettings(latitude: 36.17, longitude: -86.78, onboarded: true, isPlus: plus);
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

class _FakePlus implements PlusService {
  @override
  Future<List<PlusOffer>> offers() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

late ProviderContainer _c;

Future<void> _mount(WidgetTester t, {required bool plus}) async {
  t.view.physicalSize = const Size(1179, 2556);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  _c = ProviderContainer(overrides: [
    settingsProvider.overrideWith(() => _Settings(plus)),
    plusServiceProvider.overrideWithValue(_FakePlus()),
  ]);
  addTearDown(_c.dispose);
  await _c.read(settingsProvider.future);
  await t.pumpWidget(UncontrolledProviderScope(container: _c, child: MaterialApp(theme: buildLookUpTheme(), home: const SettingsScreen())));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty());

  testWidgets('free: the caption stays on, and turning it off asks for LookUp+', (t) async {
    await _mount(t, plus: false);
    expect(t.widget<Switch>(find.descendant(of: find.byKey(const Key('photo-caption')), matching: find.byType(Switch))).value, isTrue);
    t.widget<Switch>(find.descendant(of: find.byKey(const Key('photo-caption')), matching: find.byType(Switch))).onChanged!(false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(PaywallSheet), findsOneWidget);
    expect(_c.read(settingsProvider).value!.photoCaption, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('LookUp+: it turns off', (t) async {
    await _mount(t, plus: true);
    t.widget<Switch>(find.descendant(of: find.byKey(const Key('photo-caption')), matching: find.byType(Switch))).onChanged!(false);
    await t.pump();
    expect(_c.read(settingsProvider).value!.photoCaption, isFalse);
    expect(find.byType(PaywallSheet), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
