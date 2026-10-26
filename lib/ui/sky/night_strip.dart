import 'package:flutter/material.dart';

import '../../domain/sky/visibility.dart';
import '../format.dart';
import '../theme.dart';
import 'sky_thing.dart';

/// Tonight's clouds hour by hour across the dark hours, with the best
/// stretch lit up in blue. Taller, brighter bars mean clearer sky.
class NightStrip extends StatelessWidget {
  const NightStrip({super.key, required this.outlook, this.compact = false});
  final NightOutlook outlook;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final o = outlook;
    final bs = o.bestStart, be = o.bestEnd;
    return Semantics(
      label: '${outlookWords(o)}.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!compact)
          Text(outlookWords(o), style: displaySerif(context, size: 24, weight: FontWeight.w500)),
        if (!compact) const SizedBox(height: 10),
        if (o.hasForecast)
          SizedBox(
            height: compact ? 26 : 38,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final h in o.hours)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: FractionallySizedBox(
                      heightFactor: (1 - h.coverPercent / 100).clamp(0.12, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: bs != null && !h.time.isBefore(bs) && h.time.isBefore(be!)
                              ? LookUpColors.blue
                              : LookUpColors.grey.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        if (o.hasForecast) ...[
          const SizedBox(height: 6),
          Row(children: [
            Text(fmtTime(o.hours.first.time), style: monoData(context, size: 10.5, color: LookUpColors.greyDim)),
            const Spacer(),
            Text('taller = clearer', style: const TextStyle(fontSize: 10.5, color: LookUpColors.greyDim)),
            const Spacer(),
            Text(fmtTime(o.hours.last.time), style: monoData(context, size: 10.5, color: LookUpColors.greyDim)),
          ]),
        ],
      ]),
    );
  }
}
