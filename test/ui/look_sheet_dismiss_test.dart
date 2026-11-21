import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/state/sky_state.dart';
import 'package:lookup/ui/look_sheet.dart';
import 'package:lookup/ui/theme.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.nerd);
  final bool nerd;
  @override
  Future<LookUpSettings> build() async => LookUpSettings(
      latitude: 36.17, longitude: -86.78, onboarded: true, firstBadgeShown: true, nerdMode: nerd);
}

final _start = DateTime.now().toUtc().add(const Duration(days: 2));
final _iss = SkyEvent(
  id: 'iss:1',
  type: SkyEventType.iss,
  start: _start,
  peak: _start.add(const Duration(minutes: 2)),
  end: _start.add(const Duration(minutes: 4)),
  peakElevationDeg: 64,
  riseAzimuthDeg: 247,
  peakAzimuthDeg: 175,
  setAzimuthDeg: 95,
  details: const {'brightness': 'brighter than any star'},
);

Future<void> _open(WidgetTester t, {required bool nerd}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [settingsProvider.overrideWith(() => _Settings(nerd)), tonightSkyProvider.overrideWith((_) async => null)],
    child: MaterialApp(
      theme: buildLookUpTheme(),
      home: Builder(
        builder: (c) => Scaffold(body: TextButton(onPressed: () => showLookSheet(c, _iss), child: const Text('open'))),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(LookSheet), findsOneWidget);
}

void main() {
  for (final nerd in [false, true]) {
    testWidgets('pulling the card down closes it (nerd mode: $nerd)', (t) async {
      await _open(t, nerd: nerd);
      await t.dragFrom(const Offset(195, 150), const Offset(0, 500));
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(LookSheet), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  }
}
