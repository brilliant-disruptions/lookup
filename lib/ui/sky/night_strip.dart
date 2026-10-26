import 'package:flutter/material.dart';

import '../../domain/sky/visibility.dart';
import '../format.dart';
import '../theme.dart';
import 'sky_thing.dart';

/// Tonight's clouds hour by hour across the dark hours. Each bar is as tall
/// as the sky is clear; the best stretch is lit in blue and named below.
class NightStrip extends StatelessWidget {
  const NightStrip({super.key, required this.outlook, this.compact = false});
  final NightOutlook outlook;
  final bool compact;

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
