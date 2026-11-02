import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookup/data/aurora_reports_client.dart';
import 'package:lookup/domain/aurora/seen_nearby.dart';

void main() {
  test('a report carries only the half-degree cell, eye or camera, and the day\'s token', () async {
    late http.Request sent;
    final c = AuroraReportsClient(
      base: 'https://relay.test/',
      client: MockClient((r) async {
        sent = r;
        return http.Response('', 202);
      }),
    );
    expect(await c.report(latDeg: 55.9533, lonDeg: -3.1883, how: SeenHow.camera, reporter: 'abc123abc123abc123'), isTrue);
    expect(sent.url.toString(), 'https://relay.test/v1/report');
    final body = jsonDecode(sent.body) as Map;
    expect(body, {
      'cell': {'la': 55.75, 'lo': -3.25},
      'how': 'camera',
      'reporter': 'abc123abc123abc123',
    });
    expect(sent.body, isNot(contains('55.95')));
  });

  test('a repeat the relay refuses comes back false, not an error', () async {
    final c = AuroraReportsClient(base: 'https://relay.test', client: MockClient((_) async => http.Response('{}', 429)));
    expect(await c.report(latDeg: 55.95, lonDeg: -3.19, how: SeenHow.eye, reporter: 'abc123abc123abc123'), isFalse);
  });

  test('nearby asks for every cell in range and reads the reports back', () async {
    late Uri asked;
    final c = AuroraReportsClient(
      base: 'https://relay.test',
      client: MockClient((r) async {
        asked = r.url;
        return http.Response(
            jsonEncode({
              'now': '2026-11-02T22:00:00.000Z',
              'reports': [
                {'la': 55.75, 'lo': -4.25, 'at': '2026-11-02T21:57:00.000Z', 'how': 'eye', 'r': 'f00d'},
              ],
            }),
            200);
      }),
    );
    final got = await c.nearby(55.95, -3.19);
    expect(got.single.reporter, 'f00d');
    expect(got.single.how, SeenHow.eye);
    final cells = asked.queryParameters['cells']!.split(';');
    expect(cells.length, cellsNear(55.95, -3.19).length);
    expect(cells, contains('55.75,-3.25'));
  });
}
