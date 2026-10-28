import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'kit/kit.dart';

/// What the spotlight tour lights up. Each key sits on one widget.
abstract final class TourKeys {
  static final next = GlobalKey(debugLabel: 'tour:next');
  static final skyTab = GlobalKey(debugLabel: 'tour:sky');
  static final weekTab = GlobalKey(debugLabel: 'tour:week');
  static final nightVision = GlobalKey(debugLabel: 'tour:night-vision');
  static final place = GlobalKey(debugLabel: 'tour:place');
}

final tourSteps = [
  SpotlightStep(
    target: TourKeys.next,
    title: 'The next thing worth stepping out for',
    body:
        'When something good is coming over, it\'s here with a countdown. We tap you a few minutes before, '
        'with which way to face. Tap the card to see where to look.',
  ),
  SpotlightStep(
    target: TourKeys.skyTab,
    radius: 27,
    title: 'Everything up there now',
    body:
        'Your horizon, live. Drag to turn round, tap a planet or star to see when it\'s best, '
        'and tap the heart to follow it.',
  ),
  SpotlightStep(
    target: TourKeys.weekTab,
    radius: 27,
    title: 'Plan ahead',
    body: 'What\'s coming this week, any night in the next two, and where it\'s clearer or darker tonight.',
  ),
  SpotlightStep(
    target: TourKeys.nightVision,
    radius: 30,
    title: 'Red light for outside',
    body: 'One tap turns the screen red, so your eyes stay used to the dark.',
  ),
  SpotlightStep(
    target: TourKeys.place,
    title: 'Where we\'re watching',
    body: 'We follow your phone. Tap here to pick a saved place instead: home, a cabin, a trip.',
  ),
];

/// Asks the home shell to show the tour (from Settings, which sits on top
/// of it). Each request bumps the count.
class TourRequest extends Notifier<int> {
  @override
  int build() => 0;
  void request() => state++;
}

final tourRequestProvider = NotifierProvider<TourRequest, int>(TourRequest.new);

/// Show the tour on the Tonight tab, then remember they've seen it.
Future<void> startTour(BuildContext context, WidgetRef ref) async {
  ref.read(homeTabProvider.notifier).set(0);
  // Let Tonight load, lay out and its cards finish rising before lighting
  // them up; a stop whose target never shows is left out.
  try {
    await ref.read(homeProvider.future);
  } catch (_) {}
  await Future<void>.delayed(const Duration(milliseconds: 800));
  if (!context.mounted) return;
  await showSpotlight(context, tourSteps);
  await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(toured: true));
}
