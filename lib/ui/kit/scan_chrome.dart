/// The words around every screen you hold up to the sky (the finder, the
/// sky camera, Catch it), so they all read the same: close on the left, what
/// you're looking at in the middle, one control on the right; at most one
/// hint under that, shown once; and one line of direction words at the foot.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'controls.dart';

const _shade = [Shadow(blurRadius: 8, color: Colors.black)];

/// The middle of [ScanTopBar]: grey, one line.
const scanTitleStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: LookUpColors.grey, shadows: _shade);

class ScanTopBar extends StatelessWidget {
  const ScanTopBar({super.key, required this.title, required this.trailing});

  /// Usually [scanTitle]; any small widget that fits on one line.
  final Widget title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Row(children: [
        CircleButton(tooltip: 'Close', icon: Icons.close_rounded, onPressed: () => Navigator.of(context).pop()),
        // Between the buttons, trimmed rather than overflowing on a small phone with big text.
        Expanded(child: Center(child: title)),
        trailing,
      ]);
}

Widget scanTitle(String text) =>
    Text(text, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: scanTitleStyle);

/// The one-time hint under the top bar.
class ScanHint extends StatelessWidget {
  const ScanHint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: LookUpColors.grey, fontSize: 15, height: 1.35, shadows: _shade)),
      );
}

/// The direction words at the foot: "Look NE, halfway up".
class ScanLine extends StatelessWidget {
  const ScanLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Text(text, textAlign: TextAlign.center, style: display(22, weight: FontWeight.w700).copyWith(shadows: _shade)),
      );
}
