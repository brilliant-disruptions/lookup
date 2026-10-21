import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/sky/direction.dart';

void main() {
  test('16-point compass words', () {
    expect(compassWord(0), 'north');
    expect(compassWord(359), 'north');
    expect(compassWord(11), 'north');
    expect(compassWord(12), 'north-northeast');
    expect(compassWord(90), 'east');
    expect(compassWord(247), 'west-southwest');
    expect(compassWord(-90), 'west');
    expect(compassAbbrev(247), 'WSW');
  });

  test('elevation bands', () {
    expect(elevationWord(5), 'low on the horizon');
    expect(elevationWord(30), 'about halfway up');
    expect(elevationWord(60), 'high in the sky');
    expect(elevationWord(80), 'straight overhead');
  });

  test('describeArc reads like a sentence', () {
    expect(
      describeArc(
          riseAzimuthDeg: 247,
          peakElevationDeg: 62,
          duration: const Duration(minutes: 4, seconds: 10)),
      'rising in the west-southwest, high in the sky at its best, 4 min',
    );
    expect(durationWord(const Duration(seconds: 90)), '90 sec');
  });
}
