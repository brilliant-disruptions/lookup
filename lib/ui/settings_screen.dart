import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/settings.dart';
import '../state/providers.dart';
import 'demo.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/woven.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'theme.dart';

Future<void> openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

typedef _Set = Future<void> Function(LookUpSettings Function(LookUpSettings));

_Set _setter(WidgetRef ref) => (f) async {
      await ref.read(settingsProvider.notifier).edit(f);
      // Re-plan with the new rules; cheap, all cached.
      await ref.read(homeProvider.notifier).refresh();
    };

/// The short list: where, what, when. Everything else is one level down.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const LookUpSettings();
    final set = _setter(ref);

    return Scaffold(
      appBar: const WovenHeader(title: Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _Header('Where'),
          WovenRows(children: [
            _Row(
              icon: s.locationMode == LocationMode.auto ? Icons.near_me_outlined : Icons.place_outlined,
              title: s.locationMode == LocationMode.auto
                  ? 'Following your phone'
                  : (s.placeName?.isNotEmpty ?? false) ? s.placeName! : 'Pinned place',
              subtitle: s.places.isEmpty ? 'Save home, a cabin, a trip' : '${s.places.length} saved',
              onTap: () => openPlaces(context),
            ),
          ]),
          const _Header('Alerts'),
          WovenRows(children: [
            _Row(
              icon: Icons.notifications_none,
              title: 'What to tell me about',
              subtitle: alertTypesSummary(s),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _AlertTypesScreen())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Heads-up', style: TextStyle(fontSize: 16)),
                    SizedBox(height: 2),
                    Text('Before it starts', style: TextStyle(color: LookUpColors.grey, fontSize: 13)),
                  ]),
                ),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 5, label: Text('5m')),
                    ButtonSegment(value: 10, label: Text('10m')),
                    ButtonSegment(value: 20, label: Text('20m')),
                  ],
                  selected: {s.leadMinutes},
                  onSelectionChanged: (v) => set((s) => s.copyWith(leadMinutes: v.first)),
                ),
              ]),
            ),
            _Switch(
              value: s.clearSkyOnly,
              onChanged: (v) => set((s) => s.copyWith(clearSkyOnly: v)),
              title: 'Only when it\'s clear',
              subtitle: 'Skip it if the forecast is cloudy',
            ),
            _Row(
              icon: Icons.bedtime_outlined,
              title: 'Quiet hours',
              subtitle: '${_hm(s.quietHours.startMinute)} – ${_hm(s.quietHours.endMinute)}',
              onTap: () => _quietHours(context, s, set),
            ),
          ]),
          const _Header('Outside'),
          WovenRows(children: [
            _Switch(
              value: s.nightVision,
              onChanged: (v) => set((s) => s.copyWith(nightVision: v)),
              title: 'Night vision',
              subtitle: 'Red screen that keeps your eyes dark-adapted',
            ),
            _Row(
              icon: Icons.play_circle_outline,
              title: 'Preview an alert',
              subtitle: 'A whole pass in fast-forward',
              onTap: () => showDemo(context, ref),
            ),
          ]),
          const _Header('LookUp+'),
          WovenRows(children: [
            _Row(
              icon: Icons.auto_awesome,
              title: s.isPlus ? 'You have LookUp+' : 'Get LookUp+',
              subtitle: s.isPlus ? 'Thank you' : 'Aurora now, Starlink trains, launches. From \$2.99/mo.',
              onTap: () => showPaywall(context),
            ),
            _Row(
              icon: Icons.tune,
              title: 'More',
              subtitle: 'Go-now nudge, wake-ups, what LookUp learned',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _MoreScreen())),
            ),
          ]),
        ],
      ),
    );
  }

  static String _hm(int m) {
    final h = m ~/ 60, mm = m % 60;
    final ap = h >= 12 ? 'pm' : 'am';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${mm.toString().padLeft(2, '0')} $ap';
  }

  Future<void> _quietHours(BuildContext context, LookUpSettings s, _Set set) async {
    final start = await showTimePicker(
        context: context,
        helpText: 'Quiet from',
        initialTime: TimeOfDay(hour: s.quietHours.startMinute ~/ 60, minute: s.quietHours.startMinute % 60));
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
        context: context,
        helpText: 'Until',
        initialTime: TimeOfDay(hour: s.quietHours.endMinute ~/ 60, minute: s.quietHours.endMinute % 60));
    if (end == null) return;
    await set((s) => s.copyWith(
        quietHours: QuietHours(startMinute: start.hour * 60 + start.minute, endMinute: end.hour * 60 + end.minute)));
  }
}

/// "Space station, Starlink, aurora +4".
String alertTypesSummary(LookUpSettings s) {
  final on = [
    if (s.issEnabled) 'Space station',
    if (s.starlinkEnabled) 'Starlink',
    if (s.auroraEnabled) 'aurora',
    if (s.meteorsEnabled) 'meteors',
    if (s.eclipsesEnabled) 'eclipses',
    if (s.pairingsEnabled) 'planets',
    if (s.launchesEnabled) 'launches',
    if (s.tiangongEnabled) 'Tiangong',
  ];
  if (on.isEmpty) return 'Nothing yet';
  if (on.length <= 3) return on.join(', ');
  return '${on.take(3).join(', ')} +${on.length - 3}';
}

class _AlertTypesScreen extends ConsumerWidget {
  const _AlertTypesScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const LookUpSettings();
    final set = _setter(ref);
    _Switch toggle(bool v, LookUpSettings Function(LookUpSettings, bool) f, String title, String subtitle) =>
        _Switch(value: v, onChanged: (x) => set((s) => f(s, x)), title: title, subtitle: subtitle);
    return Scaffold(
      appBar: const WovenHeader(title: Text('Tell me about')),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 32), children: [
        WovenRows(children: [
          toggle(s.issEnabled, (s, v) => s.copyWith(issEnabled: v), 'Space station', 'Bright, 3–6 minutes, a few times a month'),
          toggle(s.starlinkEnabled, (s, v) => s.copyWith(starlinkEnabled: v), 'Starlink trains', 'A line of lights after each launch · LookUp+'),
          toggle(s.auroraEnabled, (s, v) => s.copyWith(auroraEnabled: v), 'Aurora', 'Tonight\'s outlook free; "aurora now" is LookUp+'),
          toggle(s.meteorsEnabled, (s, v) => s.copyWith(meteorsEnabled: v), 'Meteor showers', 'Peak nights, Moon factored in'),
          toggle(s.eclipsesEnabled, (s, v) => s.copyWith(eclipsesEnabled: v), 'Lunar eclipses', 'When the Moon is up for you'),
          toggle(s.pairingsEnabled, (s, v) => s.copyWith(pairingsEnabled: v), 'Planet pairings', 'The Moon and bright planets side by side'),
          toggle(s.launchesEnabled, (s, v) => s.copyWith(launchesEnabled: v), 'Rocket launches', 'Ones you can see from here · LookUp+'),
          toggle(s.tiangongEnabled, (s, v) => s.copyWith(tiangongEnabled: v), 'Tiangong', 'China\'s station · LookUp+'),
        ]),
        const _Header('Listed, never tapped'),
        WovenRows(children: [
          toggle(s.transitsEnabled, (s, v) => s.copyWith(transitsEnabled: v), 'Station crossing the Sun or Moon',
              'Under a second, for photographers'),
        ]),
      ]),
    );
  }
}

class _MoreScreen extends ConsumerWidget {
  const _MoreScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const LookUpSettings();
    final set = _setter(ref);
    final learned = ref.watch(tuningProvider).value;
    return Scaffold(
      appBar: const WovenHeader(title: Text('More')),
      body: ListView(padding: const EdgeInsets.only(top: 8, bottom: 32), children: [
        WovenRows(children: [
          _Switch(
            value: s.goNowNudge,
            onChanged: (v) => set((s) => s.copyWith(goNowNudge: v)),
            title: '"Go outside now" nudge',
            subtitle: 'A second tap one minute before',
          ),
          _Switch(
            value: s.auroraWakeMe,
            onChanged: (v) => set((s) => s.copyWith(auroraWakeMe: v)),
            title: 'Wake me for aurora and eclipses',
            subtitle: 'Rare enough to ignore quiet hours',
          ),
        ]),
        if (learned != null && !learned.isNeutral) ...[
          const _Header('Learned from you'),
          WovenRows(children: [
            for (final r in learned.reasons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(r, style: const TextStyle(fontSize: 14, height: 1.35)),
              ),
          ]),
        ],
        const _Header('Housekeeping'),
        WovenRows(children: [
          _Row(icon: Icons.refresh, title: 'Refresh everything now', onTap: () => ref.read(homeProvider.notifier).refresh(force: true)),
          if (!s.isPlus)
            _Row(icon: Icons.restore, title: 'Restore purchases', onTap: () => ref.read(plusServiceProvider).restore()),
        ]),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(children: [
            Icon(icon, size: 21, color: LookUpColors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: const TextStyle(color: LookUpColors.grey, fontSize: 13)),
                ],
              ]),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, size: 20, color: LookUpColors.greyDim),
          ]),
        ),
      );
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.onChanged, required this.title, required this.subtitle});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: InkWell(
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: LookUpColors.grey, fontSize: 13)),
                ]),
              ),
              const SizedBox(width: 12),
              Switch(value: value, onChanged: onChanged),
            ]),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 6),
        child: OrnamentRule(label: text, color: LookUpColors.greyDim),
      );
}
