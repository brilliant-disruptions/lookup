import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'pip_mark.dart';

/// Something didn't load. Said kindly, in words (never the error itself,
/// which means nothing to the person holding the phone), with a way to try
/// again.
class LoadTrouble extends StatelessWidget {
  const LoadTrouble({super.key, required this.onRetry, this.what = 'That didn\'t load.'});
  final VoidCallback onRetry;
  final String what;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const PipMark(size: 56, mood: PipMood.sorry),
            const SizedBox(height: 12),
            Text(what, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Nothing is lost. Try again in a moment.',
                textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey, height: 1.4)),
            const SizedBox(height: 14),
            FilledButton.tonal(key: const Key('load-retry'), onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}
