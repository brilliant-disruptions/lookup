import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/geocoding_client.dart';
import '../domain/models/settings.dart';
import '../state/providers.dart';
import 'fancy/ornament_rule.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text('Places', style: displaySerif(context, size: 26, weight: FontWeight.w600))),
      body: ListView(
        children: [
          RadioGroup<String>(
            groupValue: s.locationMode == LocationMode.auto ? 'auto' : (active == null ? 'custom' : _key(active)),
            onChanged: (v) {
              if (v == 'auto') {
                set((s) => s.copyWith(locationMode: LocationMode.auto, placeName: ''));
                return;
              }
              final p = s.places.where((p) => _key(p) == v).firstOrNull;
              if (p != null) set((s) => s.usePlace(p));
            },
            child: Column(children: [
              const RadioListTile<String>(
                value: 'auto',
                title: Text('Follow my phone'),
                subtitle: Text('Alerts follow you wherever you are'),
                secondary: Icon(Icons.my_location),
              ),
              if (s.places.isNotEmpty)
                const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 6), child: OrnamentRule(label: 'Saved', color: LookUpColors.greyDim)),
              for (final p in s.places)
                Dismissible(
                  key: ValueKey(_key(p)),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: const Color(0x33E6B450),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) => set((s) {
                    final rest = [for (final x in s.places) if (_key(x) != _key(p)) x];
                    final wasActive = s.activePlace != null && _key(s.activePlace!) == _key(p);
                    return wasActive
                        ? s.copyWith(places: rest, locationMode: LocationMode.auto, placeName: '')
                        : s.copyWith(places: rest);
                  }),
                  child: RadioListTile<String>(
                    value: _key(p),
                    title: Text(p.name),
                    subtitle: Text('${p.latitude.toStringAsFixed(2)}, ${p.longitude.toStringAsFixed(2)}'),
                    secondary: const Icon(Icons.place_outlined),
                  ),
                ),
            ]),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 6), child: OrnamentRule(label: 'Add', color: LookUpColors.greyDim)),
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text('Search for a place'),
            subtitle: const Text('A town, a dark-sky park, where you\'re headed'),
            onTap: () async {
              final p = await showDialog<SavedPlace>(context: context, builder: (_) => const _SearchDialog());
              if (p != null) await set((s) => s.usePlace(p));
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_location_alt_outlined),
            title: const Text('Save where I am now'),
            onTap: () => _saveHere(context, ref, set),
          ),
          if (s.places.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Text('Swipe a place left to remove it.', style: TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
            ),
        ],
      ),
    );
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
    await set((s) => s.usePlace(SavedPlace(name: label, latitude: fix.lat, longitude: fix.lon)));
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
