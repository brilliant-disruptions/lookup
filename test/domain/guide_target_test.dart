import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/guide_target.dart';

void main() {
  const moon = GuideCandidate(id: 'moon', kind: 'moon', mag: -12, altitudeDeg: 30);
  const saturn = GuideCandidate(id: 'planet:saturn', kind: 'planet', mag: 0.6, altitudeDeg: 24);
  const jupiter = GuideCandidate(id: 'planet:jupiter', kind: 'planet', mag: -2.6, altitudeDeg: 12);
  const m45 = GuideCandidate(id: 'show:m45', kind: 'showpiece', mag: 1.6, altitudeDeg: 40);
  const lowVenus = GuideCandidate(id: 'planet:venus', kind: 'planet', mag: -4.2, altitudeDeg: 2);
  const iss = GuideCandidate(id: 'iss:1', kind: 'pass', mag: -3, altitudeDeg: 3, live: true);

  test('Pip leads to the brightest planet before the Moon: the Moon finds itself', () {
    expect(guideTarget([moon, saturn, jupiter, m45])!.id, 'planet:jupiter');
    expect(guideOrder([moon, saturn, jupiter, m45]).map((c) => c.id),
        ['planet:jupiter', 'planet:saturn', 'moon', 'show:m45']);
  });

  test('something going over now comes first, even just risen', () {
    expect(guideTarget([moon, saturn, iss])!.id, 'iss:1');
  });

  test('never leads you to something in the trees', () {
    expect(guideTarget([lowVenus, m45])!.id, 'show:m45');
    expect(guideTarget([lowVenus]), isNull);
  });

  test('keeps your pick while it is up, and "something else" steps round', () {
    expect(guideTarget([moon, saturn, jupiter], chosen: 'moon')!.id, 'moon');
    expect(guideTarget([saturn, jupiter], chosen: 'moon')!.id, 'planet:jupiter', reason: 'the Moon has set');
    expect(nextGuideTarget([moon, saturn, jupiter], 'planet:jupiter')!.id, 'planet:saturn');
    expect(nextGuideTarget([moon, saturn, jupiter], 'moon')!.id, 'planet:jupiter', reason: 'wraps round');
    expect(nextGuideTarget(const [], null), isNull);
  });
}
