import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/plus/free_plan.dart';
import 'paywall_sheet.dart';

import '../data/geocoding_client.dart';
import '../domain/models/settings.dart';
import '../domain/sky/skyglow.dart';
import '../domain/sky/visibility.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'kit/kit.dart';
import 'theme.dart';

Future<void> openPlaces(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlacesScreen()));

/// Where LookUp watches the sky for: follow the phone, or one of your
/// saved places (home, the cabin, next week's trip).
class PlacesScreen extends ConsumerWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value ?? const LookUpSettings();
    final active = s.activePlace;
    Future<void> set(LookUpSettings Function(LookUpSettings) f) async {
      await ref.read(settingsProvider.notifier).edit(f);
      await ref.read(homeProvider.notifier).refresh();
    }

    final auto = s.locationMode == LocationMode.auto;
    bool isActive(SavedPlace p) => !auto && active != null && _key(active) == _key(p);
    const check = Icon(Icons.check_rounded, color: LookUpColors.blue, size: 22);
    return PageScaffold(
      title: 'Places',
      subtitle: 'Where LookUp watches the sky',
      children: [
        GroupedList(indent: 60, children: [
          Semantics(
            selected: auto,
            child: ListRow(
              leading: const EventGlyph(icon: Icons.near_me_rounded, color: LookUpColors.blue, size: 32),
              title: 'Follow my phone',
              subtitle: 'Alerts follow you wherever you are',
              trailing: auto ? check : null,
              chevron: false,
              onTap: () => set((s) => s.copyWith(locationMode: LocationMode.auto, placeName: '')),
            ),
          ),
        ]),
        if (s.places.isNotEmpty) ...[
          const SectionHeader('Saved', small: true),
          GroupedList(indent: 60, children: [
            for (final p in s.places)
              Dismissible(
                key: ValueKey(_key(p)),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: const Color(0x40FF6B6B),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete_outline_rounded),
                ),
                onDismissed: (_) => set((s) {
                  final rest = [for (final x in s.places) if (_key(x) != _key(p)) x];
                  final wasActive = s.activePlace != null && _key(s.activePlace!) == _key(p);
                  return wasActive
                      ? s.copyWith(places: rest, locationMode: LocationMode.auto, placeName: '')
                      : s.copyWith(places: rest);
                }),
                child: Semantics(
                  selected: isActive(p),
                  child: ListRow(
                    leading: const EventGlyph(icon: Icons.place_rounded, color: LookUpColors.violet, size: 32),
                    title: p.name,
                    subtitle: p.skyDarkness == null
                        ? '${p.latitude.toStringAsFixed(2)}, ${p.longitude.toStringAsFixed(2)}'
                        : '${p.skyDarkness!.label} · ${p.latitude.toStringAsFixed(2)}, ${p.longitude.toStringAsFixed(2)}',
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      _SkyMenu(
                        place: p,
                        fallback: s.skyDarkness,
                        onChanged: (d) => ref.read(settingsProvider.notifier).edit((s) => s.copyWith(places: [
                              for (final x in s.places) _key(x) == _key(p) ? x.withDarkness(d) : x,
                            ])),
                      ),
                      if (isActive(p)) ...[const SizedBox(width: 6), check],
                    ]),
                    chevron: false,
                    onTap: () => set((s) => s.usePlace(p)),
                  ),
                ),
              ),
          ]),
        ],
        const SectionHeader('Add', small: true),
        GroupedList(indent: 60, children: [
          ListRow(
            leading: const EventGlyph(icon: Icons.search_rounded, color: LookUpColors.grey, size: 32),
            title: 'Search for a place',
            subtitle: 'A town, a dark-sky park, where you\'re headed',
            onTap: () async {
              if (!FreePlan.canAddPlace(s.places.length, isPlus: s.isPlus)) {
                await showPaywall(context, feature: PlusFeature.places);
                return;
              }
              final p = await showDialog<SavedPlace>(context: context, builder: (_) => const _SearchDialog());
              if (p == null) return;
              final q = await _withSky(ref, p);
              await set((s) => s.usePlace(q));
            },
          ),
          ListRow(
            leading: const EventGlyph(icon: Icons.add_location_alt_rounded, color: LookUpColors.grey, size: 32),
            title: 'Save where I am now',
            onTap: () => FreePlan.canAddPlace(s.places.length, isPlus: s.isPlus)
                ? _saveHere(context, ref, set)
                : showPaywall(context, feature: PlusFeature.places),
          ),
        ]),
        if (s.places.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text('Tap the sky icon to say how dark a place is. Swipe a place left to remove it.', style: TextStyle(color: LookUpColors.greyDim, fontSize: 12.5)),
          ),
        if (!s.isPlus)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('One saved place on free. LookUp+ keeps as many as you like.', style: TextStyle(color: LookUpColors.greyDim, fontSize: 12.5)),
          ),
      ],
    );
  }

  /// A new place starts with its sky estimated from the night-lights map;
  /// they can change it from the moon icon.
  static Future<SavedPlace> _withSky(WidgetRef ref, SavedPlace p) async {
    if (p.skyDarkness != null) return p;
    try {
      final m = (await ref.read(skyGlowProvider.future)).sqmNear(p.latitude, p.longitude);
      return m == null ? p : p.withDarkness(darknessForSqm(m));
    } catch (_) {
      return p;
    }
  }

  static String _key(SavedPlace p) => '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}';

  Future<void> _saveHere(BuildContext context, WidgetRef ref,
      Future<void> Function(LookUpSettings Function(LookUpSettings)) set) async {
    final messenger = ScaffoldMessenger.of(context);
    final fix = await ref
        .read(locationServiceProvider)
        .resolve(const LookUpSettings(), allowPrompt: true);
    if (fix == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn\'t get your location. Check location access in Settings.')));
      return;
    }
    if (!context.mounted) return;
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this place'),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Home, the cabin…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final label = name.text.trim().isEmpty ? 'Saved place' : name.text.trim();
    final p = await _withSky(ref, SavedPlace(name: label, latitude: fix.lat, longitude: fix.lon));
    await set((s) => s.usePlace(p));
  }
}

/// How dark a saved place's sky is: unset follows Settings.
class _SkyMenu extends StatelessWidget {
  const _SkyMenu({required this.place, required this.fallback, required this.onChanged});
  final SavedPlace place;
  final SkyDarkness fallback;
  final ValueChanged<SkyDarkness?> onChanged;
  static const _same = 'same';

  @override
  Widget build(BuildContext context) {
    final d = place.skyDarkness;
    // A null value would read as "dismissed", so the default has its own key.
    return PopupMenuButton<String>(
      tooltip: 'How dark is the sky at ${place.name}?',
      initialValue: d?.name ?? _same,
      onSelected: (v) => onChanged(SkyDarkness.values.where((x) => x.name == v).firstOrNull),
      itemBuilder: (_) => [
        PopupMenuItem(value: _same, child: Text('Same as Settings (${fallback.label})')),
        for (final x in SkyDarkness.values) PopupMenuItem(value: x.name, child: Text('${x.label} · ${x.hint}')),
      ],
      icon: Icon(Icons.nights_stay_rounded, size: 20, color: d == SkyDarkness.dark ? LookUpColors.good : d == null ? LookUpColors.greyDim : LookUpColors.grey),
    );
  }
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog();
  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _client = GeocodingClient();
  Timer? _debounce;
  List<({SavedPlace place, String detail})> _results = const [];
  bool _busy = false;
  String? _error;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _busy = true;
        _error = null;
      });
      try {
        final r = await _client.search(q);
        if (mounted) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _error = 'Search needs a connection.');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Search for a place'),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        content: SizedBox(
          width: 360,
          height: 320,
          child: Column(children: [
            TextField(
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Nashville, Joshua Tree…',
                prefixIcon: const Icon(Icons.search_rounded, color: LookUpColors.greyDim),
                suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null) Text(_error!, style: const TextStyle(color: LookUpColors.warn)),
            Expanded(
              child: ListView(children: [
                for (final r in _results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.place.name),
                    subtitle: Text(r.detail),
                    onTap: () => Navigator.pop(context, r.place),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      );
}
