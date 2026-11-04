/// "Add to calendar" for a friend, as a file: the same event the invite
/// link's /invite.ics serves (relay/src/ics.ts), for when there's no link
/// (no relay in this build, or it couldn't be reached). One event with a
/// reminder ten minutes before. Pure Dart.
library;

import 'dart:convert';

String _stamp(DateTime d) {
  final u = d.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// RFC 5545 text: backslash, semicolon, comma and newlines escaped.
String _text(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll(';', r'\;').replaceAll(',', r'\,').replaceAll(RegExp(r'\r?\n'), r'\n');

/// Lines over 75 octets continue on the next, indented by a space.
String _fold(String line) {
  if (utf8.encode(line).length <= 75) return line;
  final out = <String>[];
  var cur = StringBuffer();
  for (final ch in line.runes.map(String.fromCharCode)) {
    final limit = out.isEmpty ? 75 : 74;
    if (utf8.encode('$cur$ch').length > limit) {
      out.add(cur.toString());
      cur = StringBuffer();
    }
    cur.write(ch);
  }
  out.add(cur.toString());
  return out.join('\r\n ');
}

/// Honest words for the forecast, as the invite page says them.
String inviteCloudWords(int? clouds) {
  if (clouds == null) return '';
  if (clouds <= 25) return 'Clear skies forecast.';
  if (clouds <= 60) return 'Some cloud forecast: gaps are likely.';
  return 'Cloudy forecast: it may be hidden.';
}

String inviteIcs({
  required String uid,
  required String title,
  required DateTime start,
  required DateTime end,
  required String look,
  String? place,
  int? clouds,
  required DateTime now,
}) {
  final description = [look, inviteCloudWords(clouds), 'Sent with LookUp.'].where((s) => s.isNotEmpty).join('\n\n');
  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//LookUp//Invite//EN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:$uid@lookup-invite',
    'DTSTAMP:${_stamp(now)}',
    'DTSTART:${_stamp(start)}',
    'DTEND:${_stamp(end)}',
    'SUMMARY:${_text('$title: look up')}',
    'DESCRIPTION:${_text(description)}',
    if (place != null && place.isNotEmpty) 'LOCATION:${_text(place)}',
    'BEGIN:VALARM',
    'TRIGGER:-PT10M',
    'ACTION:DISPLAY',
    'DESCRIPTION:${_text('$title in 10 minutes. $look')}',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.map(_fold).join('\r\n')}\r\n';
}
