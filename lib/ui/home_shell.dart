import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/alert_actions.dart';
import '../services/notification_service.dart';
import '../state/providers.dart';
import 'demo.dart';
import 'fancy/woven.dart';
import 'finder_screen.dart';
import 'log_screen.dart';
import 'look_sheet.dart';
import 'now_screen.dart';
import 'upcoming_screen.dart';

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
      // First run: show the whole experience right away, not an empty sky.
      if (ref.read(playIntroProvider)) {
        ref.read(playIntroProvider.notifier).set(false);
        showDemo(context, ref);
      }
      // Cold start from an alert: the tap arrived before we were listening.
      final pending = ref.read(alertTapProvider);
      if (pending != null) _openAlert(pending);
    });
  }

  /// A tapped alert opens its Look sheet; "Find it" goes straight to the
  /// finder. Buttons the OS delivered to the running app are handled here.
  Future<void> _openAlert(AlertTap t) async {
    ref.read(alertTapProvider.notifier).set(null);
    final store = ref.read(storeProvider);
    if (t.action == AlertAction.seen || t.action == AlertAction.snooze) {
      final result = await handleAlertAction(
          actionId: t.action, eventId: t.eventId, store: store, notifications: ref.read(notificationServiceProvider));
      if (result == AlertActionResult.logged) ref.invalidate(skyLogProvider);
      if (!mounted || result == AlertActionResult.nothing) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result == AlertActionResult.logged ? 'Logged. Nice one.' : 'We\'ll remind you in 5 minutes.')));
      return;
    }
    // Wait for the first load so the event is there to open.
    await ref.read(homeProvider.future);
    final event = await findStoredEvent(store, t.eventId);
    if (event == null || !mounted) return;
    if (t.action == AlertAction.find) {
      await openFinder(context, event);
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
    const pages = [NowScreen(), UpcomingScreen(), LogScreen()];
    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: WovenNavBar(
        index: tab,
        onSelect: ref.read(homeTabProvider.notifier).set,
        tabs: const [
          WovenTab(Icons.nightlight_outlined, 'Tonight', activeIcon: Icons.nightlight),
          WovenTab(Icons.calendar_today_outlined, 'Sky', activeIcon: Icons.calendar_today),
          WovenTab(Icons.auto_awesome_outlined, 'Log', activeIcon: Icons.auto_awesome),
        ],
      ),
    );
  }
}
