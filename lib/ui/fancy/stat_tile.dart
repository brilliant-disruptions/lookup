import 'package:flutter/material.dart';

import '../theme.dart';

/// Dearly's StatTile: overline key, display-serif value, muted sub-line.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.k, required this.v, this.s, this.align = CrossAxisAlignment.start, this.valueColor});
  final String k;
  final String v;
  final String? s;
  final CrossAxisAlignment align;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(k.toUpperCase(),
            style: t.labelSmall?.copyWith(color: LookUpColors.greyDim, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(v, style: displaySerif(context, size: 26, weight: FontWeight.w600, color: valueColor ?? LookUpColors.white)),
        if (s != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(s!, style: monoData(context, size: 12, color: LookUpColors.grey)),
          ),
      ],
    );
  }
}
