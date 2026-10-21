import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/orbit/omm.dart';
import 'package:lookup/domain/starlink/train_detector.dart';

void main() {
  late List<OmmRecord> records;
  setUpAll(() {
    final raw = File('test/fixtures/starlink_sample.json').readAsStringSync();
    records = OmmRecord.listFromJson(jsonDecode(raw));
  });

  test('fixture parses and groups by launch', () {
    expect(records.length, 24);
    expect(records.first.launchKey, '2026-232');
    expect(records.first.period.inMinutes, inInclusiveRange(89, 92));
  });

  test('only train-phase launches are detected, newest first', () {
    final groups = TrainDetector.detect(records);
    expect(groups.map((g) => g.launchKey), ['2026-232', '2026-219']);
    expect(groups.first.isTight, isTrue);
    expect(groups.first.label, 'Starlink train');
    expect(groups[1].isTight, isFalse);
    expect(groups[1].label, 'Starlink string');
    expect(groups.first.count, 8);
    expect(groups.first.representative.objectName, startsWith('STARLINK'));
  });

  test('spread is a circular range', () {
    final g = TrainDetector.detect(records).first;
    expect(g.spreadDeg, inInclusiveRange(0, 360));
    expect(g.spreadDuration.inMinutes, inInclusiveRange(0, 92));
  });

  test('groups smaller than five or non-Starlink are ignored', () {
    final iss = OmmRecord.listFromJson(
        jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync()));
    expect(TrainDetector.detect(iss), isEmpty);
    expect(TrainDetector.detect(records.take(3)), isEmpty);
  });
}
