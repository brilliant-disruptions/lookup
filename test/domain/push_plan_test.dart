import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/aurora/push_plan.dart';
import 'package:lookup/domain/models/settings.dart';

void main() {
  final now = DateTime.utc(2026, 11, 4, 22);
  // Edinburgh: aurora country, so Seen near you is offered there.
  const edinburgh = LookUpSettings(latitude: 55.95, longitude: -3.19, seenNearby: true, auroraEnabled: true);
  // Nashville: too far south for it to be offered.
  const nashville = LookUpSettings(latitude: 36.17, longitude: -86.78, seenNearby: true, auroraEnabled: true);

  group('wanted only when Seen near you could alert here', () {
    test('switched on, aurora alerts on, offered here, relay configured', () {
      expect(pushWanted(edinburgh, relayConfigured: true), isTrue);
    });
    test('not without the relay, the switch, aurora alerts, or the aurora', () {
      expect(pushWanted(edinburgh, relayConfigured: false), isFalse);
      expect(pushWanted(edinburgh.copyWith(seenNearby: false), relayConfigured: true), isFalse);
      expect(pushWanted(edinburgh.copyWith(auroraEnabled: false), relayConfigured: true), isFalse);
      expect(pushWanted(nashville, relayConfigured: true), isFalse);
      expect(pushWanted(const LookUpSettings(seenNearby: true), relayConfigured: true), isFalse);
    });
  });

  group('when to talk to the relay', () {
    final area = pushArea(55.95, -3.19);
    PushRecord rec({String token = 'abc', String? at, Duration ago = Duration.zero}) =>
        (token: token, area: at ?? area, at: now.subtract(ago));

    test('first time: register', () {
      expect(pushStep(wanted: true, token: 'abc', area: area, last: null, now: now), PushStep.subscribe);
    });
    test('already registered for this address and area this week: nothing', () {
      expect(pushStep(wanted: true, token: 'abc', area: area, last: rec(ago: const Duration(days: 3)), now: now), PushStep.nothing);
    });
    test('a week on: renew, well before the relay forgets after 30 days', () {
      expect(pushStep(wanted: true, token: 'abc', area: area, last: rec(ago: pushRenewEvery), now: now), PushStep.subscribe);
    });
    test('a new push address from iOS, or a new area: register again', () {
      expect(pushStep(wanted: true, token: 'xyz', area: area, last: rec(), now: now), PushStep.subscribe);
      expect(pushStep(wanted: true, token: 'abc', area: pushArea(57.48, -4.22), last: rec(), now: now), PushStep.subscribe);
    });
    test('no push address (push not allowed): nothing', () {
      expect(pushStep(wanted: true, token: null, area: area, last: null, now: now), PushStep.nothing);
    });
    test('switched off: withdraw once, then nothing', () {
      expect(pushStep(wanted: false, token: 'abc', area: area, last: rec(), now: now), PushStep.unsubscribe);
      expect(pushStep(wanted: false, token: 'abc', area: area, last: null, now: now), PushStep.nothing);
    });
  });
}
