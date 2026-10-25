import 'package:add_2_calendar/add_2_calendar.dart';

import '../domain/models/sky_event.dart';
import 'format.dart';
import 'look_sheet.dart';

/// Opens the system "new event" screen pre-filled; the user confirms there.
Future<bool> addToCalendar(SkyEvent e, {String? place}) async {
  // Calendars round to the minute; give sub-second transits a little room.
  final short = e.end.difference(e.start) < const Duration(minutes: 2);
  final start = short ? e.peak.subtract(const Duration(minutes: 1)) : e.start;
  final end = short ? e.peak.add(const Duration(minutes: 1)) : e.end;
  final when = e.type == SkyEventType.issTransit ? 'At ${fmtTimeSeconds(e.peak)}. ' : '';
  try {
    return await Add2Calendar.addEvent2Cal(Event(
      title: '${eventEmoji(e)} ${eventTitle(e)}',
      description: '$when${lookLine(e)}\n\nFrom LookUp.',
      location: place,
      startDate: start.toLocal(),
      endDate: end.toLocal(),
    ));
  } catch (_) {
    return false;
  }
}
