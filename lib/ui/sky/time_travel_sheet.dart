/// Go to any night from 3000 BC to 3000 AD: a famous one, or a date typed
/// the way it was written at the time (Julian before 1582, BC years).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/sky/calendar.dart';
import '../../domain/sky/history.dart';
import '../kit/kit.dart';
import '../theme.dart';

/// The earliest and latest moments the sky map goes to.
final skyTimeFirst = utcFromJulianDay(julianDay(-2999, 1, 1));
final skyTimeLast = utcFromJulianDay(julianDay(3000, 12, 31));

/// Where a visit takes the map: a famous night, or a moment at home.
typedef TimeTravel = ({FamousNight? night, DateTime utc});

Future<TimeTravel?> showTimeTravelSheet(BuildContext context, {required DateTime at, required double lonDeg}) =>
    showModalBottomSheet<TimeTravel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TimeTravelSheet(at: at.toUtc(), lonDeg: lonDeg),
    );

class _TimeTravelSheet extends StatefulWidget {
  const _TimeTravelSheet({required this.at, required this.lonDeg});
  final DateTime at;
  final double lonDeg;
  @override
  State<_TimeTravelSheet> createState() => _TimeTravelSheetState();
}

class _TimeTravelSheetState extends State<_TimeTravelSheet> {
  late final TextEditingController _year;
  late bool _bc;
  late int _month, _day, _hour;

  @override
  void initState() {
    super.initState();
    // Start from where the map is, in the calendar and clock of the time.
    final l = widget.at.toLocal(), h = localMeanTime(widget.at, widget.lonDeg);
    final (int y, int m, int d, int hour) =
        widget.at.year >= 1900 ? (l.year, l.month, l.day, l.hour) : (h.year, h.month, h.day, h.hour);
    _bc = y <= 0;
    _year = TextEditingController(text: '${_bc ? 1 - y : y}');
    _month = m;
    _day = d;
    _hour = hour;
  }

  @override
  void dispose() {
    _year.dispose();
    super.dispose();
  }

  /// Astronomical year (0 = 1 BC), or null when it isn't a number.
  int? get _astroYear {
    final y = int.tryParse(_year.text.trim());
    if (y == null || y < 1) return null;
    return _bc ? 1 - y : y;
  }

  String? get _problem {
    final y = _astroYear;
    if (y == null) return 'Type a year';
    if (y < -2999 || y > 3000) return 'The map goes from 3000 BC to 3000 AD';
    if (isMissingDate(y, _month, _day)) return 'Oct 5–14, 1582 never happened: the calendar skipped them';
    return null;
  }

  DateTime _moment() {
    final y = _astroYear!;
    final day = _day.clamp(1, daysInMonth(y, _month));
    // From 1900 your own clock; before, the Sun's (local mean time).
    return y >= 1900
        ? DateTime(y, _month, day, _hour).toUtc()
        : utcFromLocalMeanTime(y, _month, day, _hour.toDouble(), widget.lonDeg);
  }

  Widget _dropdown(String label, int value, List<DropdownMenuItem<int>> items, ValueChanged<int> onChanged) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            items: items,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final y = _astroYear;
    final days = y == null ? 31 : daysInMonth(y, _month);
    final problem = _problem;
    String hourLabel(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Go to any night', style: display(26, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('From the pyramids to the year 3000.', style: TextStyle(color: LookUpColors.grey)),
            const SizedBox(height: 18),
            const Kicker('Famous nights'),
            const SizedBox(height: 8),
            GroupedList(children: [
              for (final n in famousNights)
                ListRow(
                  title: n.title,
                  subtitle: '${n.place} · ${HistoricDate.fromJulianDay(julianDay(n.year, n.month, n.day)).dateLabel}',
                  subtitleLines: 1,
                  onTap: () => Navigator.of(context).pop<TimeTravel>((night: n, utc: n.utc)),
                ),
            ]),
            const SizedBox(height: 24),
            const Kicker('Or pick a date'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: const InputDecoration(labelText: 'Year', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('AD')), ButtonSegment(value: true, label: Text('BC'))],
                selected: {_bc},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _bc = v.first),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 3,
                child: _dropdown('Month', _month, [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(months[m - 1]))],
                    (v) => setState(() => _month = v)),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _dropdown('Day', _day.clamp(1, days), [for (var d = 1; d <= days; d++) DropdownMenuItem(value: d, child: Text('$d'))],
                    (v) => setState(() => _day = v)),
              ),
            ]),
            const SizedBox(height: 12),
            _dropdown('Time', _hour, [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text(hourLabel(h)))],
                (v) => setState(() => _hour = v)),
            const SizedBox(height: 10),
            Text(
              problem ??
                  'Dates before 15 October 1582 are Julian, as written at the time. '
                      'Before 1900 the time is local time by the Sun.',
              style: TextStyle(color: problem == null ? LookUpColors.greyDim : LookUpColors.warn, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: problem != null ? null : () => Navigator.of(context).pop<TimeTravel>((night: null, utc: _moment())),
              child: const Text('Go'),
            ),
          ]),
        ),
      ),
    );
  }
}
