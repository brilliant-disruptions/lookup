import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../services/plus_service.dart';
import '../state/providers.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'theme.dart';

/// The paywall appears only when a Plus-only event is actually coming for
/// this user (spec §7), or from Settings.
Future<void> showPaywall(BuildContext context, {SkyEvent? reason}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PaywallSheet(reason: reason),
    );

class PaywallSheet extends ConsumerStatefulWidget {
  const PaywallSheet({super.key, this.reason});
  final SkyEvent? reason;
  @override
  ConsumerState<PaywallSheet> createState() => _PaywallState();
}

class _PaywallState extends ConsumerState<PaywallSheet> {
  List<PlusOffer>? _offers;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(plusServiceProvider).offers().then((o) {
      if (mounted) setState(() => _offers = o);
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isPlus = ref.watch(settingsProvider).value?.isPlus ?? false;
    final r = widget.reason;
    return SafeArea(
      child: Starfield(
        density: 0.00012,
        maxOpacity: 0.45,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Text('LookUp', style: display(36, weight: FontWeight.w800)),
                Text('+', style: display(36, weight: FontWeight.w800, color: LookUpColors.blue)),
              ]),
              const SizedBox(height: 8),
              Text(
                r == null
                    ? 'Every reason to step outside, not just the station.'
                    : '${eventTitle(r)} passes over you ${fmtDay(r.start).toLowerCase()} at ${fmtTime(r.start)}. LookUp+ taps you 10 minutes before.',
                style: t.bodyLarge?.copyWith(color: LookUpColors.grey, fontSize: 17),
              ),
              const SizedBox(height: 22),
              GroupedList(indent: 60, children: [
                for (final (type, line) in const [
                  (SkyEventType.auroraNow, 'Aurora alerts the moment it\'s happening, and a wake-me option'),
                  (SkyEventType.starlinkTrain, 'Starlink trains for two weeks after every launch'),
                  (SkyEventType.tiangong, 'Tiangong flyovers'),
                  (null, 'The one-minute "go outside now" nudge'),
                ])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(children: [
                      type == null
                          ? const EventGlyph(icon: Icons.directions_walk_rounded, color: LookUpColors.blue, size: 32)
                          : EventGlyph.forType(type, size: 32),
                      const SizedBox(width: 12),
                      Expanded(child: Text(line, style: t.bodyMedium?.copyWith(height: 1.35))),
                    ]),
                  ),
              ]),
              const SizedBox(height: 20),
              if (isPlus)
                const Text('You have LookUp+. Thank you.', textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.grey))
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: LookUpColors.warn))
              else if (_offers == null)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
              else if (_offers!.isEmpty)
                const Text(
                  'The store isn\'t reachable right now. Products appear once the app is set up in App Store Connect / Play Console.',
                  style: TextStyle(color: LookUpColors.grey),
                )
              else
                for (final o in _offers!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OfferButton(offer: o, busy: _busy, onTap: () => _buy(o), highlight: o.id == PlusProducts.yearly),
                  ),
              if (!isPlus)
                TextButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restore purchases'),
                ),
              const SizedBox(height: 4),
              Text(
                'Subscriptions renew automatically and can be cancelled any time in your store account. 7-day free trial on yearly.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: LookUpColors.greyDim),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _buy(PlusOffer o) async {
    setState(() => _busy = true);
    try {
      await ref.read(plusServiceProvider).buy(o);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await ref.read(plusServiceProvider).restore();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _OfferButton extends StatelessWidget {
  const _OfferButton({required this.offer, required this.onTap, required this.busy, required this.highlight});
  final PlusOffer offer;
  final VoidCallback onTap;
  final bool busy;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final label = switch (offer.id) {
      PlusProducts.monthly => 'Monthly',
      PlusProducts.yearly => 'Yearly',
      _ => 'Lifetime',
    };
    final child = Row(children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      if (highlight) ...[
        const SizedBox(width: 10),
        const Pill('Best value', color: LookUpColors.blueInk),
      ],
      const Spacer(),
      Text(offer.price, style: numeric(size: 16, weight: FontWeight.w700, color: highlight ? LookUpColors.black : LookUpColors.white)),
      const SizedBox(width: 6),
      Text(offer.cadence, style: TextStyle(fontSize: 12.5, color: highlight ? LookUpColors.greyDim : LookUpColors.grey)),
    ]);
    const size = Size.fromHeight(58);
    return highlight
        ? FilledButton(onPressed: busy ? null : onTap, style: FilledButton.styleFrom(minimumSize: size), child: child)
        : OutlinedButton(onPressed: busy ? null : onTap, style: OutlinedButton.styleFrom(minimumSize: size), child: child);
  }
}
