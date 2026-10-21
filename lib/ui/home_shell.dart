import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'look_sheet.dart';
import 'now_screen.dart';
import 'settings_screen.dart';
import 'upcoming_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final home = ref.read(homeProvider).value;
      final stale = home?.lastRefresh == null ||
          DateTime.now().toUtc().difference(home!.lastRefresh!) > const Duration(hours: 3);
      if (stale) ref.read(homeProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tappedEventIdProvider, (_, id) {
      if (id == null) return;
      final events = ref.read(homeProvider).value?.events ?? const [];
      final e = events.where((e) => e.id == id).firstOrNull;
      ref.read(tappedEventIdProvider.notifier).set(null);
      if (e != null) showLookSheet(context, e);
    });
    final pages = const [NowScreen(), UpcomingScreen(), SettingsScreen()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.nightlight_outlined), label: 'Now'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Upcoming'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}
