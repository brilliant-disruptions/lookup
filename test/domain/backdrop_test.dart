import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/astro.dart';
import 'package:lookup/domain/sky/backdrop.dart';

void main() {
  test('faces the equator: south from Nashville, north from Sydney', () {
    expect(backdropFacingAz(36.17), 180);
    expect(backdropFacingAz(-33.87), 0);
  });

  test('the middle of the view lands in the middle; higher is up', () {
    final c = backdropProject(const Horizontal(180, backdropCenterAlt), centerAz: 180)!;
    expect(c.x, closeTo(0, 1e-9));
    expect(c.y, closeTo(0, 1e-9));
    final zenith = backdropProject(const Horizontal(0, 90), centerAz: 180)!;
    expect(zenith.x, closeTo(0, 1e-9));
    expect(zenith.y, greaterThan(0));
    final low = backdropProject(const Horizontal(180, 10), centerAz: 180)!;
    expect(low.y, lessThan(0));
  });

  test('facing south, east is on the left and west on the right', () {
    expect(backdropProject(const Horizontal(135, 40), centerAz: 180)!.x, lessThan(0));
    expect(backdropProject(const Horizontal(225, 40), centerAz: 180)!.x, greaterThan(0));
    // Facing north it flips, as it does when you turn round.
    expect(backdropProject(const Horizontal(45, 40), centerAz: 0)!.x, greaterThan(0));
  });

  test('nothing below the horizon', () {
    expect(backdropProject(const Horizontal(180, -1), centerAz: 180), isNull);
  });
}
