import 'package:flutter/material.dart';

import '../theme.dart';

/// Dearly's ceremonial rule ("— ◆ —"), with an optional tracked label.
class OrnamentRule extends StatelessWidget {
  const OrnamentRule({super.key, this.label, this.color = LookUpColors.greyDim, this.accent = LookUpColors.blue});
  final String? label;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Container(height: 1, color: color.withValues(alpha: 0.6)));
    final diamond = Transform.rotate(
      angle: 0.785398,
      child: Container(width: 5, height: 5, color: accent),
    );
    return Row(children: [
      line,
      const SizedBox(width: 10),
      diamond,
      if (label != null) ...[
        const SizedBox(width: 10),
        Text(
          label!.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color, fontSize: 11, letterSpacing: 2.6, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 10),
        diamond,
      ],
      const SizedBox(width: 10),
      line,
    ]);
  }
}
