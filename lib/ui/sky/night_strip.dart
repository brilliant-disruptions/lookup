import 'package:flutter/material.dart';

import '../../domain/sky/visibility.dart';
import '../format.dart';
import '../theme.dart';
import 'sky_thing.dart';

/// Tonight's clouds hour by hour across the dark hours. Each bar is as tall
/// as the sky is clear; the best stretch is lit in blue and named below.
class NightStrip extends StatelessWidget {
  const NightStrip({super.key, required this.outlook, this.compact = false, this.marks = const []});
  final NightOutlook outlook;
  final bool compact;

  /// Tonight's things at their times: a coloured tick and a short label
  /// above the bars ("ISS 10:17 PM").
  final List<({DateTime at, Color color, String label})> marks;

  @override
  Widget build(BuildContext context) {
    final o = outlook;
    final bs = o.bestStart, be = o.bestEnd;
    bool best(DateTime t) => bs != null && !t.isBefore(bs) && t.isBefore(be!);
    final label = numeric(size: 12, color: LookUpColors.greyDim);
    return Semantics(
      label: '${outlookWords(o)}.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!compact) ...[
          Text(outlookWords(o), style: display(22, weight: FontWeight.w600)),
          const SizedBox(height: 14),
        ],
        if (o.hasForecast) ...[
          if (marks.isNotEmpty) _Marks(marks: marks, from: o.hours.first.time, hours: o.hours.length),
          SizedBox(
            height: compact ? 34 : 52,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final h in o.hours)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FractionallySizedBox(
                      heightFactor: (1 - h.coverPercent / 100).clamp(0.14, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: best(h.time)
                              ? const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFF8CC0FF), LookUpColors.blue],
                                )
                              : null,
                          color: best(h.time) ? null : const Color(0x24FFFFFF),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text(fmtTime(o.hours.first.time), style: label),
            Expanded(
              child: bs == null
                  ? const SizedBox.shrink()
                  : Text('Clearest ${fmtTime(bs)}–${fmtTime(be!)}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: numeric(size: 12, weight: FontWeight.w600, color: LookUpColors.blue)),
            ),
            Text(fmtTime(o.hours.last.time), style: label),
          ]),
        ],
      ]),
    );
  }
}

/// Labelled ticks over the strip, placed by time across its hours. A label
/// that would collide with the one before steps up a row.
class _Marks extends StatelessWidget {
  const _Marks({required this.marks, required this.from, required this.hours});
  final List<({DateTime at, Color color, String label})> marks;
  final DateTime from;
  final int hours;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final span = Duration(hours: hours).inSeconds;
        final placed = <(double, int)>[];
        final children = <Widget>[];
        for (final m in [...marks]..sort((a, b) => a.at.compareTo(b.at))) {
          final f = m.at.difference(from).inSeconds / span;
          if (f < 0 || f > 1) continue;
          final x = f * w;
          final row = placed.any((p) => (p.$1 - x).abs() < 72 && p.$2 == 0) ? 1 : 0;
          placed.add((x, row));
          final top = row == 0 ? 18.0 : 0.0;
          children
            ..add(Positioned(left: x - 1, top: top + 16, bottom: 0, child: Container(width: 2, color: m.color)))
            ..add(Positioned(
              left: (x - 60).clamp(0.0, w - 120),
              width: 120,
              top: top,
              child: Text(
                m.label,
                textAlign: x < 60 ? TextAlign.left : (x > w - 60 ? TextAlign.right : TextAlign.center),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: m.color),
              ),
            ));
        }
        return SizedBox(height: 40, child: Stack(clipBehavior: Clip.none, children: children));
      });
}
