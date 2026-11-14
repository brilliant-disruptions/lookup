import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lookup/data/invite_client.dart';
import 'package:lookup/domain/models/sky_event.dart';
import 'package:lookup/ui/share_card.dart';

/// The relay's checks (relay/src/invite.ts): what it accepts as words, and
/// what it turns away as a link, an address or a phone number. The same
/// patterns as `linkish` there; keep the two in step.
final _relayText = RegExp(r"^[\p{L}\p{N} .,;:'’()°%\-–—!?&/+]+$", unicode: true);
const _digit = r'\p{Nd}';
const _sep = r'[ .()/+\-–—]';
final _date = RegExp(
    '(?<!$_digit)(?:$_digit{4}[-/.]$_digit{1,2}[-/.]$_digit{1,2}|$_digit{1,2}[-/.]$_digit{1,2}[-/.]$_digit{4})(?!$_digit)',
    unicode: true);
final _numbers = RegExp('$_digit(?:$_sep*$_digit)*', unicode: true);
final _decimal = RegExp('^$_digit+\\.$_digit+\$', unicode: true);
int _digits(String s) => RegExp(_digit, unicode: true).allMatches(s).length;

bool _relayLinkish(String s) =>
    RegExp(r'://|www\.', caseSensitive: false).hasMatch(s) ||
    RegExp(r'\.\p{L}{2}', unicode: true).hasMatch(s) ||
    RegExp('$_digit{1,3}(?:\\.$_digit{1,3}){3}', unicode: true).hasMatch(s) ||
    _numbers
        .allMatches(s)
        .map((m) => m[0]!)
        .any((run) => !_decimal.hasMatch(run) && _digits(run.replaceAll(_date, ' ')) >= 7);

SkyEvent _ev(SkyEventType type, {Map<String, Object?> details = const {}}) {
  final start = DateTime.utc(2026, 11, 3, 3, 5);
  return SkyEvent(
    id: '${type.name}:1',
    type: type,
    start: start,
    peak: start.add(const Duration(minutes: 2)),
    end: start.add(const Duration(minutes: 4)),
    peakElevationDeg: 60,
    riseAzimuthDeg: 247,
    peakAzimuthDeg: 180,
    setAzimuthDeg: 95,
    cloudCoverPercent: 12,
    details: details,
  );
}

void main() {
  test('sends the invite\'s fields and picture, and hands back the link', () async {
    late Map<String, Object?> sent;
    final c = InviteClient(
      base: 'https://relay.test/',
      client: MockClient((r) async {
        expect(r.url.toString(), 'https://relay.test/v1/invites');
        sent = (jsonDecode(r.body) as Map).cast<String, Object?>();
        return http.Response(jsonEncode({'url': 'https://lookup.app/n/abcdefghij', 'code': 'abcdefghij'}), 201);
      }),
    );
    final link = await c.create(inviteFields(_ev(SkyEventType.iss), 'Nashville'), image: [1, 2, 3]);
    expect(link.toString(), 'https://lookup.app/n/abcdefghij');
    expect(sent['type'], 'iss');
    expect(sent['title'], 'ISS flyover');
    expect(sent['face'], 'west-southwest');
    expect(sent['place'], 'Nashville');
    expect(sent['clouds'], 12);
    expect(sent['image'], base64Encode([1, 2, 3]));
    expect(sent['start'], '2026-11-03T03:05:00.000Z');
  });

  test('no link when the relay says no, is down, or isn\'t set up: the poster goes instead', () async {
    final no = InviteClient(base: 'https://relay.test', client: MockClient((_) async => http.Response('{}', 400)));
    expect(await no.create(inviteFields(_ev(SkyEventType.iss), null)), isNull);
    final down = InviteClient(base: 'https://relay.test', client: MockClient((_) async => throw http.ClientException('offline')));
    expect(await down.create(inviteFields(_ev(SkyEventType.iss), null)), isNull);
    expect(await InviteClient(base: '').create(const {}), isNull);
  });

  test('every kind of event\'s words pass the relay\'s checks', () {
    final events = [
      for (final t in SkyEventType.values) _ev(t),
      _ev(SkyEventType.solarEclipse, details: {'kind': 'total', 'obscuration': 1.0, 'label': 'Total solar eclipse'}),
      _ev(SkyEventType.solarEclipse, details: {'kind': 'nearPath', 'obscuration': 0.98}),
      _ev(SkyEventType.planetPairing, details: {'label': 'Moon and Jupiter', 'separation': 2.4, 'bodies': ['Moon', 'Jupiter']}),
      _ev(SkyEventType.meteorShower, details: {'shower': 'Leonids', 'perHour': 15}),
      _ev(SkyEventType.issTransit, details: {'body': 'Moon', 'crossingMs': 820}),
      _ev(SkyEventType.comet, details: {'name': 'Comet NEOWISE', 'note': 'Low in the northwest after dusk; binoculars show the tail.'}),
      _ev(SkyEventType.nova, details: {'name': 'RS Ophiuchi', 'note': 'A recurrent nova in Ophiuchus, fading over a few weeks.'}),
    ];
    for (final e in events) {
      final f = inviteFields(e, 'St. John’s');
      for (final key in ['title', 'look', 'face', 'place']) {
        final v = f[key] as String?;
        if (v == null) continue;
        expect(_relayText.hasMatch(v), isTrue, reason: '${e.type.name} $key: $v');
        expect(_relayLinkish(v), isFalse, reason: '${e.type.name} $key: $v');
      }
      expect((f['look'] as String).length, lessThanOrEqualTo(700), reason: e.type.name);
      expect((f['title'] as String).length, lessThanOrEqualTo(60), reason: e.type.name);
    }
  });

  test('place names are kept to what the page accepts', () {
    expect(invitePlace('Nashville'), 'Nashville');
    expect(invitePlace('St. John’s, NL'), 'St. John’s, NL');
    expect(invitePlace('Home 🏡 <b>'), 'Home b');
    expect(invitePlace('🏡'), isNull);
    expect(invitePlace(null), isNull);
    expect(invitePlace('x' * 60)!.length, 48);
  });

  test('a place name never reads as a web address to the page', () {
    expect(invitePlace('St.Kilda'), 'St. Kilda');
    expect(invitePlace('Mt.Hood lookout'), 'Mt. Hood lookout');
    expect(invitePlace('Washington, D.C.'), 'Washington, D.C.');
    expect(invitePlace('Mile 23.5'), 'Mile 23.5');
    for (final name in ['St.Kilda', 'Mt.Hood lookout', 'my.dark.site', 'Home 2026-11-03', 'Lat 51.47781', 'Dark site 44.12345, -71.23456']) {
      final sent = invitePlace(name)!;
      expect(_relayText.hasMatch(sent), isTrue, reason: sent);
      expect(_relayLinkish(sent), isFalse, reason: sent);
    }
  });

  test('the copy of the relay\'s rules here turns away what the relay does', () {
    for (final lure in [
      'Visit http://spam.example',
      'Free prizes at www.example.com',
      'Claim your free telescope at telescope-prize.shop/claim before it starts!',
      'See goo.gl/abc',
      'Prizes at example.com这里',
      'Open 1.2.3.4/x',
      'Call +1 (900) 555-0100 before it starts',
      'Call 555-0100',
      'Home 2026-11-03 555 0100',
    ]) {
      expect(_relayLinkish(lure), isTrue, reason: lure);
    }
    for (final fine in [
      'St. John’s, NL',
      'Meet 2026-11-03 21:05. Look 12° above the horizon at 9.30 p.m., magnitude -3.9.',
      'Use eclipse glasses (ISO 12312-2) until the Sun is fully covered.',
      'Comet C/2026 O1',
    ]) {
      expect(_relayLinkish(fine), isFalse, reason: fine);
    }
  });
}
