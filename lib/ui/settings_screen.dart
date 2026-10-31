import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/settings.dart';
import '../domain/sky/skyglow.dart';
import '../domain/sky/visibility.dart';
import '../services/widget_service.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'demo.dart';
import '../domain/models/sky_event.dart';
import 'kit/kit.dart';
import 'paywall_sheet.dart';
import 'places_screen.dart';
import 'theme.dart';
import 'tour.dart';

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

    return PageScaffold(
      title: 'Settings',
      children: [
        const _Header('Where'),
        GroupedList(indent: 60, children: [
          _Row(
            icon: s.locationMode == LocationMode.auto ? Icons.near_me_rounded : Icons.place_rounded,
            color: LookUpColors.blue,
            title: s.locationMode == LocationMode.auto
                ? 'Following your phone'
                : (s.placeName?.isNotEmpty ?? false) ? s.placeName! : 'Pinned place',
            subtitle: s.places.isEmpty ? 'Save home, a cabin, a trip' : '${s.places.length} saved',
            onTap: () => openPlaces(context),
          ),
        ]),
        const _Header('Alerts'),
        GroupedList(indent: 60, children: [
          _Row(
            icon: Icons.notifications_rounded,
            color: LookUpColors.red,
            title: 'What to tell me about',
            subtitle: alertTypesSummary(s),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _AlertTypesScreen())),
          ),
          ListRow(
            leading: const _Glyph(Icons.timer_rounded, LookUpColors.orange),
            title: 'Heads-up',
            subtitle: 'Before it starts',
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 5, label: Text('5m')),
                ButtonSegment(value: 10, label: Text('10m')),
                ButtonSegment(value: 20, label: Text('20m')),
              ],
              selected: {s.leadMinutes},
              onSelectionChanged: (v) => set((s) => s.copyWith(leadMinutes: v.first)),
            ),
          ),
          _Switch(
            icon: Icons.cloud_rounded,
            color: LookUpColors.cyan,
            value: s.clearSkyOnly,
            onChanged: (v) => set((s) => s.copyWith(clearSkyOnly: v)),
            title: 'Only when it\'s clear',
            subtitle: 'Skip it if the forecast is cloudy',
          ),
          _Row(
            icon: Icons.bedtime_rounded,
            color: LookUpColors.violet,
            title: 'Quiet hours',
            subtitle: '${_hm(s.quietHours.startMinute)} – ${_hm(s.quietHours.endMinute)}',
            onTap: () => _quietHours(context, s, set),
          ),
        ]),
        const _Header('Outside'),
        GroupedList(indent: 60, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const _Glyph(Icons.landscape_rounded, LookUpColors.good),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Your sky', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
                    const SizedBox(height: 2),
                    Text(s.skyDarkness.hint, style: const TextStyle(color: LookUpColors.grey, fontSize: 13.5)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              SegmentedButton<SkyDarkness>(
                showSelectedIcon: false,
                segments: [for (final d in SkyDarkness.values) ButtonSegment(value: d, label: Text(d.label))],
                selected: {s.skyDarkness},
                onSelectionChanged: (v) => set((s) => s.copyWith(skyDarkness: v.first)),
              ),
              if (ref.watch(darkSpotsProvider).value?.here case final m? when darknessForSqm(m) != s.skyDarkness)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    Expanded(
                      child: Text('The night-lights map puts your sky at ${darknessForSqm(m).label}.',
                          style: const TextStyle(color: LookUpColors.grey, fontSize: 13.5)),
                    ),
                    TextButton(
                      onPressed: () => set((s) => s.copyWith(skyDarkness: darknessForSqm(m))),
                      child: const Text('Use it'),
                    ),
                  ]),
                ),
            ]),
          ),
          _Switch(
            icon: Icons.visibility_rounded,
            color: LookUpColors.red,
            value: s.nightVision,
            onChanged: (v) => set((s) => s.copyWith(nightVision: v)),
            title: 'Night vision',
            subtitle: 'Red screen that keeps your eyes dark-adapted, deeper the darker it is',
          ),
          _Switch(
            icon: Icons.nights_stay_rounded,
            color: LookUpColors.red,
            value: s.nightVisionAuto,
            onChanged: (v) => set((s) => s.copyWith(nightVisionAuto: v)),
            title: 'Red by itself outside',
            subtitle: 'In the finder, Look up now and the camera view, once it\'s dark',
          ),
          if (ref.watch(widgetPinnableProvider).value ?? false)
            _Row(
              icon: Icons.widgets_rounded,
              color: LookUpColors.violet,
              title: 'Add to your home screen',
              subtitle: 'The next pass, where to look and a live countdown',
              onTap: WidgetService.pin,
            ),
          _Row(
            icon: Icons.play_arrow_rounded,
            color: LookUpColors.good,
            title: 'Preview an alert',
            subtitle: 'A whole pass in fast-forward',
            onTap: () => showDemo(context, ref),
          ),
          _Row(
            icon: Icons.tips_and_updates_rounded,
            color: LookUpColors.blue,
            title: 'Show me around',
            subtitle: 'A quick tour of what\'s where',
            onTap: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              ref.read(tourRequestProvider.notifier).request();
            },
          ),
        ]),
        const _Header('LookUp+'),
        GroupedList(indent: 60, children: [
          _Row(
            icon: Icons.auto_awesome_rounded,
            color: LookUpColors.gold,
            title: s.isPlus ? 'You have LookUp+' : 'Get LookUp+',
            subtitle: s.isPlus ? 'Thank you' : 'Aurora now, Starlink trains, launches. From \$2.99/mo.',
            onTap: () => showPaywall(context),
          ),
          _Row(
            icon: Icons.tune_rounded,
            color: LookUpColors.grey,
            title: 'More',
            subtitle: 'Go-now nudge, wake-ups, what LookUp learned',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _MoreScreen())),
          ),
        ]),
      ],
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
    _Switch toggle(SkyEventType type, bool v, LookUpSettings Function(LookUpSettings, bool) f, String title, String subtitle) =>
        _Switch(
          leading: EventGlyph.forType(type, size: 32),
          value: v,
          onChanged: (x) => set((s) => f(s, x)),
          title: title,
          subtitle: subtitle,
        );
    return PageScaffold(title: 'Tell me about', children: [
      GroupedList(indent: 60, children: [
        toggle(SkyEventType.iss, s.issEnabled, (s, v) => s.copyWith(issEnabled: v), 'Space station', 'Bright, 3–6 minutes, a few times a month'),
        toggle(SkyEventType.starlinkTrain, s.starlinkEnabled, (s, v) => s.copyWith(starlinkEnabled: v), 'Starlink trains', 'A line of lights after each launch · LookUp+'),
        toggle(SkyEventType.auroraNow, s.auroraEnabled, (s, v) => s.copyWith(auroraEnabled: v), 'Aurora', 'Tonight\'s outlook free; "aurora now" is LookUp+'),
        toggle(SkyEventType.meteorShower, s.meteorsEnabled, (s, v) => s.copyWith(meteorsEnabled: v), 'Meteor showers', 'Peak nights, Moon factored in'),
        toggle(SkyEventType.lunarEclipse, s.eclipsesEnabled, (s, v) => s.copyWith(eclipsesEnabled: v), 'Lunar eclipses', 'When the Moon is up for you'),
        toggle(SkyEventType.planetPairing, s.pairingsEnabled, (s, v) => s.copyWith(pairingsEnabled: v), 'Planet pairings', 'The Moon and bright planets side by side'),
        toggle(SkyEventType.rocketLaunch, s.launchesEnabled, (s, v) => s.copyWith(launchesEnabled: v), 'Rocket launches', 'Ones you can see from here · LookUp+'),
        toggle(SkyEventType.tiangong, s.tiangongEnabled, (s, v) => s.copyWith(tiangongEnabled: v), 'Tiangong', 'China\'s station · LookUp+'),
      ]),
      const _Header('Listed, never tapped'),
      GroupedList(indent: 60, children: [
        toggle(SkyEventType.issTransit, s.transitsEnabled, (s, v) => s.copyWith(transitsEnabled: v), 'Station crossing the Sun or Moon',
            'Under a second, for photographers'),
      ]),
    ]);
  }
}

class _MoreScreen extends ConsumerWidget {
  const _MoreScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const LookUpSettings();
    final set = _setter(ref);
    final learned = ref.watch(tuningProvider).value;
    return PageScaffold(title: 'More', children: [
      GroupedList(indent: 60, children: [
        _Switch(
          icon: Icons.directions_walk_rounded,
          color: LookUpColors.blue,
          value: s.goNowNudge,
          onChanged: (v) => set((s) => s.copyWith(goNowNudge: v)),
          title: '"Go outside now" nudge',
          subtitle: 'A second tap one minute before',
        ),
        _Switch(
          icon: Icons.alarm_rounded,
          color: LookUpColors.good,
          value: s.auroraWakeMe,
          onChanged: (v) => set((s) => s.copyWith(auroraWakeMe: v)),
          title: 'Wake me for aurora and eclipses',
          subtitle: 'Rare enough to ignore quiet hours',
        ),
      ]),
      if (learned != null && !learned.isNeutral) ...[
        const _Header('Learned from you'),
        GroupedList(children: [
          for (final r in learned.reasons)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Text(r, style: const TextStyle(fontSize: 14.5, height: 1.4)),
            ),
        ]),
      ],
      const _Header('Housekeeping'),
      GroupedList(indent: 60, children: [
        _Row(
          icon: Icons.refresh_rounded,
          color: LookUpColors.blue,
          title: 'Refresh everything now',
          onTap: () => ref.read(homeProvider.notifier).refresh(force: true),
        ),
        if (!s.isPlus)
          _Row(
            icon: Icons.restore_rounded,
            color: LookUpColors.grey,
            title: 'Restore purchases',
            onTap: () => ref.read(plusServiceProvider).restore(),
          ),
      ]),
    ]);
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph(this.icon, this.color);
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => EventGlyph(icon: icon, color: color, size: 32);
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.color, required this.title, this.subtitle, this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListRow(leading: _Glyph(icon, color), title: title, subtitle: subtitle, onTap: onTap);
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.value,
    required this.onChanged,
    required this.title,
    required this.subtitle,
    this.icon,
    this.color = LookUpColors.blue,
    this.leading,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;
  final IconData? icon;
  final Color color;
  final Widget? leading;
  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: ListRow(
          leading: leading ?? (icon == null ? null : _Glyph(icon!, color)),
          title: title,
          subtitle: subtitle,
          onTap: () => onChanged(!value),
          trailing: Switch(value: value, onChanged: onChanged),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => SectionHeader(text, small: true);
}
