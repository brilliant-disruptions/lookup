import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alert_actions.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import 'catch_it_screen.dart';
import 'finder_screen.dart';
import 'first_badge_sheet.dart';
import 'kit/navigation.dart';
import 'log_screen.dart';
import 'look_sheet.dart';
import 'now_screen.dart';
import 'pip/pip_button.dart';
import 'share_card.dart';
import 'sky/sky_camera_screen.dart';
import 'sky/sky_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Back from Settings (maybe after switching alerts or location on).
    _lifecycle = AppLifecycleListener(onResume: () {
      ref.invalidate(alertsEnabledProvider);
      if (ref.read(homeProvider).value?.needsLocation ?? false) ref.read(homeProvider.notifier).refresh();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final home = ref.read(homeProvider).value;
      final stale = home?.lastRefresh == null ||
          DateTime.now().toUtc().difference(home!.lastRefresh!) > const Duration(hours: 3);
      if (stale) ref.read(homeProvider.notifier).refresh();
      // Cold start from an alert: the tap arrived before we were listening.
      final pending = ref.read(alertTapProvider);
      if (pending != null) {
        _openAlert(pending);
        return;
      }
      unawaited(_firstBadge());
    });
  }

  /// Straight after setting up, the first badge gets its moment, once. (Set
  /// up before there was one? It's dated today.)
  Future<void> _firstBadge() async {
    final s = await ref.read(settingsProvider.future);
    if (!s.onboarded || s.firstBadgeShown || !mounted) return;
    await ref.read(settingsProvider.notifier).edit(
        (x) => x.copyWith(firstBadgeShown: true, onboardedAt: x.onboardedAt ?? DateTime.now().toUtc()));
    if (mounted) await showFirstBadge(context);
  }

  /// A tapped alert opens its Look sheet; "Find it" goes straight to the
  /// finder. Buttons the OS delivered to the running app are handled here.
  Future<void> _openAlert(AlertTap t) async {
    ref.read(alertTapProvider.notifier).set(null);
    final store = ref.read(storeProvider);
    if (t.action == AlertAction.snooze) {
      final result = await handleAlertAction(
          actionId: t.action, eventId: t.eventId, store: store, notifications: ref.read(notificationServiceProvider));
      if (!mounted || result == AlertActionResult.nothing) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('We\'ll remind you in 5 minutes.')));
      return;
    }
    // "Catch it" (and the old "Saw it!"): the camera with Pip. A sighting
    // goes in the Log only when it's caught there.
    if (t.action == AlertAction.catchIt || t.action == AlertAction.seen) {
      await ref.read(homeProvider.future);
      if (mounted) await openLiveSkyCamera(context, ref);
      return;
    }
    // Wait for the first load so the event is there to open.
    await ref.read(homeProvider.future);
    final event = await findStoredEvent(store, t.eventId);
    if (event == null || !mounted) return;
    // Any tap on the heads-up puts the countdown on the Lock Screen, so you
    // can lock the phone and head out (the Look sheet starts it too).
    if (t.action != null) unawaited(ref.read(liveActivityProvider).startIfSoon(event));
    if (t.action == AlertAction.find) {
      await openFinder(context, event);
    } else if (t.action == AlertAction.photo) {
      // "Photograph it" from the heads-up: straight to Catch it.
      await openCatchIt(context, event);
    } else if (t.action == AlertAction.invite) {
      // "Tell a friend" from the heads-up: straight to the invite.
      await showShareCard(context, event, mode: ShareMode.invite);
    } else {
      await showLookSheet(context, event);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(alertTapProvider, (_, t) {
      if (t != null) _openAlert(t);
    });
    final tab = ref.watch(homeTabProvider);
    const pages = [NowScreen(), SkyScreen(), LogScreen()];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: FloatingTabBar(
        index: tab,
        onSelect: ref.read(homeTabProvider.notifier).set,
        // Pip, beside the tabs on every screen: one tap to the camera.
        trailing: PipButton(onTap: () => openLiveSkyCamera(context, ref)),
        tabs: [
          const TabItem(Icons.home_outlined, 'Home', activeIcon: Icons.home_rounded),
          const TabItem(Icons.explore_outlined, 'Explore', activeIcon: Icons.explore_rounded),
          const TabItem(Icons.auto_awesome_outlined, 'Log', activeIcon: Icons.auto_awesome_rounded),
        ],
      ),
    );
  }
}
