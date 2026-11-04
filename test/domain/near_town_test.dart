import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/plan/near_town.dart';
import 'package:lookup/domain/satellites/under_the_pass.dart' show Place;

void main() {
  const towns = [
    Place('Nashville', 36.17, -86.78, 1000000),
    Place('Knoxville', 35.97, -83.94, 400000),
  ];

  test('a place in town is "In" it', () {
    expect(nearTown(36.1659, -86.7844, towns, miles: true), 'In Nashville');
  });

  test('out of town: how far and which way from the nearest one', () {
    // Gatlinburg-ish, in the Smokies.
    expect(nearTown(35.61, -83.49, towns, miles: true), '35 miles southeast of Knoxville');
    expect(nearTown(35.61, -83.49, towns, miles: false), '55 km southeast of Knoxville');
  });

  test('far from any town: nothing, rather than a meaningless landmark', () {
    expect(nearTown(44.0, -110.6, towns, miles: true), isNull);
  });
}
