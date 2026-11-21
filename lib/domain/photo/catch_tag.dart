/// What a caught picture says about itself, written into the file (XMP in a
/// PNG `iTXt` chunk) before it goes to Photos. Photos keeps the original
/// file, so the words travel with the picture: what it is, when, where, and
/// the sighting it belongs to. If the Log were ever lost, LookUp could read
/// its own album back and know each picture again.
///
/// Photos can't be searched by this (apps can't add tags Photos indexes);
/// the Log finds pictures by their Photos id. Pure Dart.
library;

import 'dart:convert';
import 'dart:typed_data';

class CatchTag {
  const CatchTag({required this.eventId, required this.title, required this.at, this.place});

  /// The sighting it belongs to (the Log's event id).
  final String eventId;

  /// What it is, in words ("Jupiter", "The space station").
  final String title;
  final DateTime at;
  final String? place;

  /// One line for Photos' caption-like fields and anyone reading the file.
  String get description => [title, if (place != null && place!.isNotEmpty) place!, 'caught with LookUp'].join(' · ');

  static const _ns = 'https://lookup.app/ns/catch/1.0/';

  String toXmp() {
    String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
    return '<?xpacket begin="﻿" id="W5M0MpCehiHzreSzNTczkc9d"?>'
        '<x:xmpmeta xmlns:x="adobe:ns:meta/">'
        '<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
        '<rdf:Description rdf:about=""'
        ' xmlns:dc="http://purl.org/dc/elements/1.1/"'
        ' xmlns:xmp="http://ns.adobe.com/xap/1.0/"'
        ' xmlns:lookup="$_ns"'
        ' xmp:CreatorTool="LookUp"'
        ' xmp:CreateDate="${at.toUtc().toIso8601String()}"'
        ' lookup:eventId="${esc(eventId)}"'
        ' lookup:title="${esc(title)}"'
        '${place == null ? '' : ' lookup:place="${esc(place!)}"'}>'
        '<dc:title><rdf:Alt><rdf:li xml:lang="x-default">${esc(title)}</rdf:li></rdf:Alt></dc:title>'
        '<dc:description><rdf:Alt><rdf:li xml:lang="x-default">${esc(description)}</rdf:li></rdf:Alt></dc:description>'
        '</rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>';
  }

  /// Reads a tag back from [xmp] written by [toXmp]; null if it isn't ours.
  static CatchTag? fromXmp(String xmp) {
    String? attr(String name) {
      final m = RegExp('lookup:$name="([^"]*)"').firstMatch(xmp);
      return m == null ? null : _unesc(m.group(1)!);
    }

    final id = attr('eventId'), title = attr('title');
    final at = RegExp('xmp:CreateDate="([^"]*)"').firstMatch(xmp)?.group(1);
    if (id == null || title == null || at == null) return null;
    final when = DateTime.tryParse(at);
    if (when == null) return null;
    return CatchTag(eventId: id, title: title, at: when.toUtc(), place: attr('place'));
  }

  static String _unesc(String s) =>
      s.replaceAll('&quot;', '"').replaceAll('&gt;', '>').replaceAll('&lt;', '<').replaceAll('&amp;', '&');
}

const _sig = [137, 80, 78, 71, 13, 10, 26, 10];
const _xmpKeyword = 'XML:com.adobe.xmp';

/// [png] with [tag] in an XMP `iTXt` chunk right after the header. Returns
/// [png] unchanged if it isn't a PNG.
Uint8List pngWithCatchTag(Uint8List png, CatchTag tag) {
  if (!_isPng(png) || png.length < 33) return png;
  // iTXt: keyword \0, compression flag 0, method 0, language "" \0, translated "" \0, text.
  final data = BytesBuilder()
    ..add(latin1.encode(_xmpKeyword))
    ..add(const [0, 0, 0, 0, 0])
    ..add(utf8.encode(tag.toXmp()));
  final chunk = _chunk('iTXt', data.toBytes());
  const afterHeader = 8 + 4 + 4 + 13 + 4; // signature, IHDR length, type, data, CRC
  return (BytesBuilder()
        ..add(png.sublist(0, afterHeader))
        ..add(chunk)
        ..add(png.sublist(afterHeader)))
      .toBytes();
}

/// The tag in a PNG written by [pngWithCatchTag], or null.
CatchTag? catchTagOf(Uint8List png) {
  if (!_isPng(png)) return null;
  var i = 8;
  final view = ByteData.sublistView(png);
  while (i + 8 <= png.length) {
    final len = view.getUint32(i);
    final type = latin1.decode(png.sublist(i + 4, i + 8));
    final start = i + 8, end = start + len;
    if (end + 4 > png.length) return null;
    if (type == 'iTXt') {
      final d = png.sublist(start, end);
      final k = d.indexOf(0);
      if (k > 0 && latin1.decode(d.sublist(0, k)) == _xmpKeyword) {
        // Skip compression flag and method, then the language and translated keyword.
        var p = k + 3;
        p = d.indexOf(0, p) + 1;
        p = d.indexOf(0, p) + 1;
        if (p > 0 && p <= d.length) return CatchTag.fromXmp(utf8.decode(d.sublist(p), allowMalformed: true));
      }
    }
    if (type == 'IEND') return null;
    i = end + 4;
  }
  return null;
}

bool _isPng(Uint8List b) {
  if (b.length < 8) return false;
  for (var i = 0; i < 8; i++) {
    if (b[i] != _sig[i]) return false;
  }
  return true;
}

Uint8List _chunk(String type, Uint8List data) {
  final t = latin1.encode(type);
  final out = ByteData(12 + data.length);
  out.setUint32(0, data.length);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(4, 8, t);
  bytes.setRange(8, 8 + data.length, data);
  out.setUint32(8 + data.length, pngCrc32([...t, ...data]));
  return bytes;
}

final _table = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  }
  return c;
});

/// The PNG chunk checksum (CRC-32), over a chunk's type and data.
int pngCrc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _table[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
