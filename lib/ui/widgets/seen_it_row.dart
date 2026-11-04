/// Seen near you, the giving half: "Can you see it?" on an aurora's Look
/// sheet. One tap sends an anonymous report (a half-degree cell, the time,
/// eye or camera) to the relay; the first time, it asks before switching
/// the feature on. docs/seen-near-you.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/aurora_reports_client.dart';
import '../../domain/aurora/seen_nearby.dart';
import '../../domain/models/sky_event.dart';
import '../../domain/sky/sun.dart';
import '../../state/providers.dart';
import '../format.dart' show fmtDistance;
import '../theme.dart';

/// Whether to offer "Can you see it?" for [e] at [lat], [lon] right now.
bool showSeenItRow(SkyEvent e, {required double? lat, required double? lon, required DateTime now, bool? configured}) {
  if (!(configured ?? relayConfigured) || lat == null || lon == null) return false;
  if (e.type != SkyEventType.auroraNow && e.type != SkyEventType.auroraOutlook) return false;
  if (e.details['past'] == true || now.toUtc().isAfter(e.end)) return false;
  return seenNearbyOffered(lat, lon) && isDark(now.toUtc(), lat, lon);
}

class SeenItRow extends ConsumerStatefulWidget {
  const SeenItRow({super.key, this.client});

  /// Injected in tests.
  final AuroraReportsClient? client;

  @override
  ConsumerState<SeenItRow> createState() => _SeenItRowState();
}

class _SeenItRowState extends ConsumerState<SeenItRow> {
  bool _sending = false;
  String? _done;

  Future<bool> _askFirst() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tell people nearby?'),
        content: Text(
          'LookUp sends that you can see it, when, and roughly where: '
          'a square about ${fmtDistance(55)} across, never your position. No name, no account.\n\n'
          'In return you\'ll hear when people near you see the aurora (LookUp+). '
          'You can turn this off in Settings › Tell me about.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Turn on and send')),
        ],
      ),
    );
    if (ok != true) return false;
    await ref.read(settingsProvider.notifier).edit((s) => s.copyWith(seenNearby: true));
    return true;
  }

  Future<void> _send(SeenHow how) async {
    final s = ref.read(settingsProvider).value ?? await ref.read(settingsProvider.future);
    if (s == null || s.latitude == null || s.longitude == null) return;
    if (!s.seenNearby && !await _askFirst()) return;
    setState(() => _sending = true);
    try {
      final reporter = await ref.read(storeProvider).auroraReporter(DateTime.now());
      final ok = await (widget.client ?? AuroraReportsClient())
          .report(latDeg: s.latitude!, lonDeg: s.longitude!, how: how, reporter: reporter);
      if (mounted) setState(() => _done = ok ? 'Thanks. People near you will hear about it.' : 'Already counted. Thanks.');
    } catch (_) {
      if (mounted) setState(() => _done = 'Couldn\'t send it just now. Try again in a minute.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    if (done != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(done, textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.good, fontWeight: FontWeight.w600)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Can you see it?',
            textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _sending ? null : () => _send(SeenHow.eye),
              child: const Text('Yes, by eye'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: _sending ? null : () => _send(SeenHow.camera),
              child: const Text('On my camera'),
            ),
          ),
        ]),
      ]),
    );
  }
}
