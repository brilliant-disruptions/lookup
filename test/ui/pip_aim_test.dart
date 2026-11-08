import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/ui/pip/pip_aim.dart';

void main() {
  // A blink, a lock and an appearance must feel the same on the countdown,
  // the finder and Catch it: you learn the taps once, then trust them with
  // the phone held up and your eyes on the sky.
  testWidgets('the same moves buzz the same in every mode', (t) async {
    Future<List<String>> feel(PipMode mode) async {
      final buzz = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') buzz.add('${call.arguments}');
        return null;
      });
      Future<void> at({required double distance, required bool onTarget, bool appeared = true}) async {
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: PipAim(
              mode: mode,
              target: (x: distance, y: 0),
              toward: (x: 1, y: 0),
              distanceDeg: distance,
              onTarget: onTarget,
              appeared: appeared,
              words: 'Turn right',
            ),
          ),
        ));
        await t.pump(const Duration(seconds: 2));
      }

      await at(distance: 30, onTarget: false, appeared: false); // far: slow blinks
      await at(distance: 8, onTarget: false, appeared: false); // closer: faster
      await at(distance: 0, onTarget: true, appeared: false); // locked on
      await at(distance: 0, onTarget: true); // it comes up
      await t.pump(const Duration(milliseconds: 200));
      await at(distance: 20, onTarget: false); // lost it
      await at(distance: 0, onTarget: true); // and back
      await t.pumpWidget(const SizedBox());
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      return buzz;
    }

    final find = await feel(PipMode.find);
    expect(find, contains('HapticFeedbackType.heavyImpact'), reason: 'a lock taps');
    expect(find, contains('HapticFeedbackType.selectionClick'), reason: 'blinks tick');
    expect(await feel(PipMode.countdown), find);
    expect(await feel(PipMode.catchIt), find);
  });
}
