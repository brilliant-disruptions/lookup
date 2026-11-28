import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/data/towns_asset.dart';
import 'package:lookup/domain/places/town_search.dart';

final _index = TownIndex.fromRows([
  ['Nashville', '', 36.17, -86.78, 689447, 'Tennessee', 'United States'],
  ['Nashville', '', 35.97, -77.97, 5460, 'North Carolina', 'United States'],
  ['North Nashville', '', 36.2, -86.8, 9000, 'Tennessee', 'United States'],
  ['Nashua', '', 42.77, -71.47, 91000, 'New Hampshire', 'United States'],
  ['São Paulo', 'Sao Paulo', -23.55, -46.64, 12400232, 'São Paulo', 'Brazil'],
  ['Zürich', 'Zuerich', 47.37, 8.55, 415367, 'Zurich', 'Switzerland'],
  ['Saint-Étienne', 'Saint-Etienne', 45.43, 4.39, 171000, 'Auvergne-Rhone-Alpes', 'France'],
  ['Springfield', '', 37.22, -93.3, 170188, 'Missouri', 'United States'],
  ['Springfield', '', 39.8, -89.64, 114394, 'Illinois', 'United States'],
  ['Joshua Tree', '', 34.13, -116.31, 7414, 'California', 'United States'],
]);

List<String> _names(String q) => [for (final r in _index.search(q)) r.place.name];
List<String> _details(String q) => [for (final r in _index.search(q)) r.detail];

void main() {
  test('exact names first, then names that start with it, then a later word', () {
    expect(_names('nashville'), ['Nashville', 'Nashville', 'North Nashville']);
    expect(_details('Nashville').first, 'Tennessee, United States');
    expect(_names('nash'), ['Nashville', 'Nashua', 'Nashville', 'North Nashville']);
    expect(_names('tree'), ['Joshua Tree']);
    expect(_names('ree'), isEmpty);
  });

  test('accents, case and punctuation are ignored, both ways', () {
    expect(_names('sao paulo'), ['São Paulo']);
    expect(_names('SÃO'), ['São Paulo']);
    expect(_names('zurich'), ['Zürich']);
    expect(_names('zuerich'), ['Zürich']);
    expect(_names('saint etienne'), ['Saint-Étienne']);
    expect(_names('st'), isEmpty);
  });

  test('two Springfields are told apart, and a comma narrows by region', () {
    expect(_details('Springfield'), ['Missouri, United States', 'Illinois, United States']);
    expect(_details('springfield, ill'), ['Illinois, United States']);
    expect(_details('springfield, france'), isEmpty);
  });

  test('nothing for under two letters; at most the limit', () {
    expect(_index.search('n'), isEmpty);
    expect(_index.search('  '), isEmpty);
    expect(_index.search('n a', limit: 2), hasLength(lessThanOrEqualTo(2)));
    expect(_index.search('s', limit: 2), isEmpty);
  });

  // The bundled list: small towns are there (that's why it isn't
  // places.json), and the biggest town of a name comes first.
  test('the bundled towns find home, big and small', () {
    final towns = decodeTowns(File('assets/sky/towns.json.gz').readAsBytesSync());
    expect(towns.length, greaterThan(60000));
    final n = towns.search('Nashville').first;
    expect((n.place.name, n.detail), ('Nashville', 'Tennessee, United States'));
    expect(n.place.latitude, closeTo(36.17, 0.01));
    expect(towns.search('Joshua Tree').first.detail, 'California, United States');
    expect(towns.search('tromso').first.place.name, 'Tromsø');
    final s = towns.search('Springfield');
    expect(s.first.detail, 'Missouri, United States');
    expect(s.map((r) => r.detail).toSet().length, greaterThan(4));
    expect(towns.search('springfield, illinois').single.detail, 'Illinois, United States');
  });
}
