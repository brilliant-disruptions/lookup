import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/log/sighting.dart';
import 'package:lookup/domain/log/sky_log.dart';
import 'package:lookup/domain/models/settings.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/state/providers.dart';
import 'package:lookup/ui/review_prompt.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.start);
  final LookUpSettings start;
  @override
  Future<LookUpSettings> build() async => start;
  @override
  Future<void> edit(LookUpSettings Function(LookUpSettings) f) async => state = AsyncData(f(state.value!));
}

void main() {
  final now = DateTime.now().toUtc();
  SkyLog log(int n) => SkyLog.from([
        for (var i = 0; i < n; i++) Sighting(eventId: 'iss:$i', seen: true, at: now.subtract(Duration(days: i + 1)), type: SkyEventType.iss),
      ]);

  Future<(int, LookUpSettings)> run(LookUpSettings s, int catches) async {
    var asked = 0;
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith(() => _Settings(s)),
      skyLogProvider.overrideWith((_) async => log(catches)),
      reviewPromptProvider.overrideWithValue(() async => asked++),
    ]);
    addTearDown(c.dispose);
    await askForReviewIfDue(c);
    return (asked, (await c.read(settingsProvider.future)));
  }

  final settled = LookUpSettings(onboarded: true, onboardedAt: now.subtract(const Duration(days: 10)));

  test('due: asks once and remembers', () async {
    final (asked, s) = await run(settled, 4);
    expect(asked, 1);
    expect(s.reviewAsks, 1);
    expect(s.reviewAskedAt, isNotNull);
  });

  test('not due: asks nothing and changes nothing', () async {
    final (asked, s) = await run(settled, 2);
    expect((asked, s.reviewAsks), (0, 0));
  });
}
