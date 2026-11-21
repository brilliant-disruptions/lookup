import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/orbit/omm.dart';

void main() {
  final good = (jsonDecode(File('test/fixtures/iss_omm.json').readAsStringSync()) as List).single as Map<String, Object?>;

  // A feed is somebody else's server: one row with a number missing must
  // not stop every pass being worked out (and so every alert).
  test('a record the orbit maths can\'t read is left out, and the rest are kept', () {
    final rows = [
      good,
      {...good}..remove('MEAN_MOTION'),
      {...good, 'MEAN_MOTION': 'fast'},
      {...good, 'MEAN_MOTION': 0},
      {...good, 'ECCENTRICITY': double.nan},
      {...good, 'EPOCH': 'yesterday'},
      'not a record',
      null,
    ];
    final read = OmmRecord.listFromJson(rows);
    expect(read, hasLength(1));
    expect(read.single.noradCatId, Norad.iss);
    expect(() => read.single.epoch, returnsNormally);
  });

  test('anything that isn\'t a list reads as no records', () {
    expect(OmmRecord.listFromJson({'error': 'busy'}), isEmpty);
    expect(OmmRecord.listFromJson(null), isEmpty);
  });
}
