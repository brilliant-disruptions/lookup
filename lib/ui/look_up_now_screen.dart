import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/finder/look_up_now.dart';
import '../domain/models/sky_event.dart';
import 'finder_screen.dart';

/// Ids already taken over this session, so closing it means closed.
final _shown = <String>{};

/// From Tonight: take over the screen if [e] is in its last two minutes and
/// hasn't been shown yet. Returns whether it opened.
bool maybeOpenLookUpNow(BuildContext context, SkyEvent e, DateTime now) {
  if (!LookUpNow.due(e, now) || _shown.contains(e.id)) return false;
  _shown.add(e.id);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, _, _) => LookUpNowScreen(event: e),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );
  });
  return true;
}

/// The final stretch, full screen: Pip waiting where it will rise beside a
/// small clock. When it comes up the same screen becomes the sky finder, in
/// place, with a chime and two taps.
class LookUpNowScreen extends StatelessWidget {
  const LookUpNowScreen({super.key, required this.event, this.orientationStream});
  final SkyEvent event;

  /// For tests; otherwise the phone's rotation sensor.
  final Stream<List<double>>? orientationStream;

  @override
  Widget build(BuildContext context) =>
      FinderScreen(event: event, orientationStream: orientationStream, countdown: true, camera: false);
}
