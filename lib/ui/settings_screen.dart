import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/settings.dart';
import '../state/providers.dart';
import 'fancy/ornament_rule.dart';
import 'theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const LookUpSettings();
    final n = ref.read(settingsProvider.notifier);
    Future<void> set(LookUpSettings Function(LookUpSettings) f) async {
      await n.edit(f);
      // Re-plan with the new rules; cheap, all cached.
      await ref.read(homeProvider.notifier).refresh();
    }

    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: displaySerif(context, size: 26, weight: FontWeight.w600))),
      body: ListView(
        children: [
          const _Header('Location'),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: Text(s.locationMode == LocationMode.auto ? 'Using your phone\'s location' : 'Pinned place'),
            subtitle: Text(s.hasLocation
                ? '${s.latitude!.toStringAsFixed(2)}, ${s.longitude!.toStringAsFixed(2)}${s.placeName != null ? ' · ${s.placeName}' : ''}'
                : 'No location yet'),
            trailing: TextButton(
              onPressed: () => _pinDialog(context, s, set),
              child: Text(s.locationMode == LocationMode.auto ? 'Pin a place' : 'Change'),
            ),
          ),
          if (s.locationMode == LocationMode.pinned)
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('Use my phone\'s location instead'),
              onTap: () => set((s) => s.copyWith(locationMode: LocationMode.auto, placeName: '')),
            ),
          const _Header('Tap me for'),
          SwitchListTile(
            value: s.issEnabled,
            onChanged: (v) => set((s) => s.copyWith(issEnabled: v)),
            title: const Text('Space station flyovers'),
            subtitle: const Text('Bright, 3–6 minutes, a few times a month'),
          ),
          SwitchListTile(
            value: s.starlinkEnabled,
            onChanged: (v) => set((s) => s.copyWith(starlinkEnabled: v)),
            title: const Text('Starlink trains'),
            subtitle: const Text('A line of lights for ~2 weeks after each launch · LookUp+'),
          ),
          SwitchListTile(
            value: s.auroraEnabled,
            onChanged: (v) => set((s) => s.copyWith(auroraEnabled: v)),
            title: const Text('Aurora'),
            subtitle: const Text('Tonight\'s outlook is free; live "aurora now" taps are LookUp+'),
          ),
          SwitchListTile(
            value: s.tiangongEnabled,
            onChanged: (v) => set((s) => s.copyWith(tiangongEnabled: v)),
            title: const Text('Tiangong (Chinese station)'),
            subtitle: const Text('LookUp+'),
          ),
          const _Header('How'),
          ListTile(
            title: const Text('Heads-up'),
            subtitle: const Text('How long before it starts'),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 5, label: Text('5m')),
                ButtonSegment(value: 10, label: Text('10m')),
                ButtonSegment(value: 20, label: Text('20m')),
              ],
              selected: {s.leadMinutes},
              onSelectionChanged: (v) => set((s) => s.copyWith(leadMinutes: v.first)),
            ),
          ),
          SwitchListTile(
            value: s.goNowNudge,
            onChanged: (v) => set((s) => s.copyWith(goNowNudge: v)),
            title: const Text('"Go outside now" nudge'),
            subtitle: const Text('A second tap one minute before'),
          ),
          SwitchListTile(
            value: s.clearSkyOnly,
            onChanged: (v) => set((s) => s.copyWith(clearSkyOnly: v)),
            title: const Text('Only when it\'s clear'),
            subtitle: const Text('Skip the tap if the forecast is over 60% cloud'),
          ),
          ListTile(
            title: const Text('Quiet hours'),
            subtitle: Text('${_hm(s.quietHours.startMinute)} – ${_hm(s.quietHours.endMinute)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _quietHours(context, s, set),
          ),
          SwitchListTile(
            value: s.auroraWakeMe,
            onChanged: (v) => set((s) => s.copyWith(auroraWakeMe: v)),
            title: const Text('Wake me for aurora'),
            subtitle: const Text('Aurora ignores quiet hours'),
          ),
          const _Header('LookUp+'),
          SwitchListTile(
            value: s.isPlus,
            onChanged: (v) => set((s) => s.copyWith(isPlus: v)),
            title: const Text('LookUp+ (developer toggle)'),
            subtitle: const Text('Aurora now, Starlink trains, Tiangong. Billing wires in before TestFlight.'),
          ),
          const _Header('Debug'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Send a test notification'),
            onTap: () => ref.read(notificationServiceProvider).showNow(
                  id: 1,
                  title: 'ISS flyover in 10 min',
                  body: 'Brighter than any star, rising in the west-southwest, high in the sky at its best, 4 min. Clear skies.',
                ),
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Force a full refresh'),
            onTap: () => ref.read(homeProvider.notifier).refresh(force: true),
          ),
          const SizedBox(height: 32),
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

  Future<void> _quietHours(BuildContext context, LookUpSettings s,
      Future<void> Function(LookUpSettings Function(LookUpSettings)) set) async {
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

  Future<void> _pinDialog(BuildContext context, LookUpSettings s,
      Future<void> Function(LookUpSettings Function(LookUpSettings)) set) async {
    final name = TextEditingController(text: s.placeName ?? '');
    final lat = TextEditingController(text: s.latitude?.toStringAsFixed(4) ?? '');
    final lon = TextEditingController(text: s.longitude?.toStringAsFixed(4) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pin a place'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name (e.g. Nashville)')),
          TextField(controller: lat, decoration: const InputDecoration(labelText: 'Latitude'), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
          TextField(controller: lon, decoration: const InputDecoration(labelText: 'Longitude'), keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pin')),
        ],
      ),
    );
    if (ok != true) return;
    final la = double.tryParse(lat.text), lo = double.tryParse(lon.text);
    if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180) return;
    await set((s) => s.copyWith(
        locationMode: LocationMode.pinned, latitude: la, longitude: lo, placeName: name.text.trim()));
  }
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
