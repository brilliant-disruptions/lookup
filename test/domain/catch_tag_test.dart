import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/photo/catch_tag.dart';

/// A real 2×1 PNG (one red pixel, one blue), made with Python's zlib.
final _png = Uint8List.fromList(const [
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 2, 0, 0, 0, 1, 8, 2, 0, 0, 0, 123, 64, 232, 221, //
  0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 0, 4, 255, 1, 7, 0, 1, 255, 226, 35, 158, 89, //
  0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
]);

/// The chunks of a PNG: (type, data, stored CRC).
List<(String, Uint8List, int)> chunks(Uint8List png) {
  final v = ByteData.sublistView(png);
  final out = <(String, Uint8List, int)>[];
  var i = 8;
  while (i < png.length) {
    final len = v.getUint32(i);
    out.add((latin1.decode(png.sublist(i + 4, i + 8)), png.sublist(i + 8, i + 8 + len), v.getUint32(i + 8 + len)));
    i += 12 + len;
  }
  return out;
}

void main() {
  final tag = CatchTag(eventId: 'planet-jupiter:2026-11-21', title: 'Jupiter', at: DateTime.utc(2026, 11, 21, 23, 4), place: 'Nashville & "Co" <TN>');

  test('the checksum matches a real PNG\'s', () {
    final (type, data, crc) = chunks(_png).first;
    expect(type, 'IHDR');
    expect(pngCrc32([...latin1.encode(type), ...data]), crc);
  });

  test('a caught picture carries what, when, where and its sighting, and reads back', () {
    final tagged = pngWithCatchTag(_png, tag);
    final back = catchTagOf(tagged)!;
    expect(back.eventId, tag.eventId);
    expect(back.title, 'Jupiter');
    expect(back.at, tag.at);
    expect(back.place, 'Nashville & "Co" <TN>', reason: 'escaped in the XML and back');
    expect(tag.description, 'Jupiter · Nashville & "Co" <TN> · caught with LookUp');
  });

  test('still a valid PNG: header first, the tag after it with a good checksum, the pixels untouched', () {
    final tagged = pngWithCatchTag(_png, tag);
    final c = chunks(tagged);
    expect([for (final x in c) x.$1], ['IHDR', 'iTXt', 'IDAT', 'IEND']);
    for (final (type, data, crc) in c) {
      expect(pngCrc32([...latin1.encode(type), ...data]), crc, reason: type);
    }
    expect(c[2].$2, chunks(_png)[1].$2);
    expect(latin1.decode(c[1].$2.sublist(0, 17)), 'XML:com.adobe.xmp', reason: 'where Photos and editors look for XMP');
  });

  test('anything else is left alone, and an untagged picture has no tag', () {
    final notPng = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(pngWithCatchTag(notPng, tag), same(notPng));
    expect(catchTagOf(_png), isNull);
    expect(catchTagOf(notPng), isNull);
  });
}
