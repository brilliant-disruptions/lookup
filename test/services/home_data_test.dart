import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/state/providers.dart';

void main() {
  test('no location is its own state, not "offline"', () {
    const d = HomeData(events: [], aurora: null, lastRefresh: null, errors: ['no location']);
    expect(d.needsLocation, isTrue);
    expect(d.noData, isFalse);
  });

  test('a failed first download is offline', () {
    const d = HomeData(events: [], aurora: null, lastRefresh: null, errors: ['iss: SocketException']);
    expect(d.needsLocation, isFalse);
    expect(d.noData, isTrue);
  });
}
