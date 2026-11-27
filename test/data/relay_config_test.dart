import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/relay_config.dart';

// Clouds come only through the relay. A release without one has no clouds,
// and unknown cloud lets alerts through unchecked: it must never ship.
void main() {
  test('only a release build with no relay is missing one', () {
    expect(relayMissing(release: true, url: ''), isTrue);
    expect(relayMissing(release: true, url: 'https://relay.example'), isFalse);
    expect(relayMissing(release: false, url: ''), isFalse, reason: 'debug and test builds may leave it out');
  });

  group('tool/check_release_env.sh', () {
    Future<int> check(String url) async {
      final r = await Process.run('sh', ['tool/check_release_env.sh'], environment: {'LOOKUP_RELAY_URL': url});
      return r.exitCode;
    }

    test('refuses an empty, plain-http or local relay; passes the real one', () async {
      expect(await check(''), isNot(0));
      expect(await check('http://lookup-relay.example'), isNot(0));
      expect(await check('https://localhost:8787'), isNot(0));
      expect(await check('https://relay.test'), isNot(0));
      expect(await check('https://lookup-relay.brilliant-disruptions.workers.dev'), 0);
    });

    test('every release build runs it and passes the relay in', () {
      final ci = File('.github/workflows/ci.yml').readAsStringSync();
      final apk = RegExp(r'flutter build apk --release[^\n]*').firstMatch(ci)!.group(0)!;
      expect(apk, contains('--dart-define=LOOKUP_RELAY_URL='));
      expect(ci.indexOf('tool/check_release_env.sh'), allOf(isNonNegative, lessThan(ci.indexOf(apk))));

      final xc = File('ios/ci_scripts/ci_post_clone.sh').readAsStringSync();
      final ios = xc.indexOf('flutter build ios');
      expect(xc.indexOf('tool/check_release_env.sh'), allOf(isNonNegative, lessThan(ios)));
      expect(xc.substring(ios), contains('--dart-define=LOOKUP_RELAY_URL='));
    });
  });
}
