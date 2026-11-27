import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookup/data/clouds_client.dart';
import 'package:lookup/domain/privacy/rough_place.dart';

final _now = DateTime.utc(2026, 11, 27, 20, 7);

String _body({String fetched = '2026-11-27T19:50:00.000Z'}) => jsonEncode({
      'issued': '2026-11-27T19:40:12Z',
      'fetched': fetched,
      'steps': [
        {'t': '2026-11-27T20:00:00Z', 'hours': 1, 'cloud': 12.5, 'fog': 0, 'precipMm': 0, 'precipProb': 2},
        {'t': '2026-11-27T21:00:00Z', 'hours': 1, 'cloud': 88, 'fog': 64.2, 'precipMm': 0.6, 'precipProb': 71},
      ],
    });

void main() {
  test('a coordinate is rounded to two places: about a kilometre', () {
    expect(roughCoord(36.16589), 36.17);
    expect(roughCoord(-86.78444), -86.78);
    expect(roughCoord(-0.004), 0);
    expect(roughCoord(51.5), 51.5);
  });

  // Info.plist and the privacy page promise only a rough place leaves the
  // phone, and MET's terms want clouds through our relay, never from phones.
  test('asks the relay, never MET, with the rough place and an app name', () async {
    late http.Request asked;
    final c = CloudsClient(
      base: 'https://relay.test/',
      now: () => _now,
      client: MockClient((r) async {
        asked = r;
        return http.Response(_body(), 200);
      }),
    );
    final f = await c.fetch(36.16589, -86.78444);
    expect(asked.url.toString(), 'https://relay.test/v1/clouds?lat=36.17&lon=-86.78');
    expect(asked.url.toString(), isNot(contains('36.165')));
    expect(asked.url.host, isNot(contains('met.no')));
    expect(asked.headers['User-Agent'], 'LookUp/1.0');
    expect(f.latitude, 36.16589);
    expect(f.fetchedAt, DateTime.utc(2026, 11, 27, 19, 50));
    expect(f.coverAt(DateTime.utc(2026, 11, 27, 21)), 88);
    expect(f.sampleAt(DateTime.utc(2026, 11, 27, 21))!.wet, isTrue);
    expect(f.sampleAt(DateTime.utc(2026, 11, 27, 21))!.foggy, isTrue);
  });

  test('a stale copy reads as old: fetched is the relay\'s, never later than now', () async {
    final c = CloudsClient(
      base: 'https://relay.test',
      now: () => _now,
      client: MockClient((r) async => http.Response(_body(fetched: '2026-11-28T00:00:00Z'), 200)),
    );
    expect((await c.fetch(1, 1)).fetchedAt, _now);
  });

  test('no relay in this build: an error, never an empty (clear) forecast', () async {
    var calls = 0;
    final c = CloudsClient(base: '', client: MockClient((r) async => http.Response(_body(), 200).also(() => calls++)));
    await expectLater(c.fetch(1, 1), throwsA(isA<CloudsUnavailable>()));
    expect(calls, 0);
  });

  test('paused or refused: no retry; a forecast with no steps is an error', () async {
    for (final status in [400, 429, 503]) {
      var calls = 0;
      final c = CloudsClient(
        base: 'https://relay.test',
        client: MockClient((r) async {
          calls++;
          return http.Response('{"error":"x"}', status);
        }),
      );
      await expectLater(c.fetch(1, 1), throwsA(isA<CloudsUnavailable>()), reason: '$status');
      expect(calls, 1, reason: '$status');
    }
    final empty = CloudsClient(
      base: 'https://relay.test',
      client: MockClient((r) async => http.Response('{"fetched":"2026-11-27T19:50:00Z","steps":[]}', 200)),
    );
    await expectLater(empty.fetch(1, 1), throwsA(isA<CloudsUnavailable>()));
  });
}

extension on http.Response {
  http.Response also(void Function() f) {
    f();
    return this;
  }
}
