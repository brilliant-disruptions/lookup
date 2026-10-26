import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_store.dart';
import '../../domain/sky/direction.dart';
import '../../state/providers.dart';
import '../fancy/foil_text.dart';
import '../fancy/ornament_rule.dart';
import '../finder_screen.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/compass_arrow.dart';
import 'sky_thing.dart';

Future<void> showObjectSheet(BuildContext context, SkyThing thing) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ObjectSheet(thing: thing),
    );

/// A planet, the Moon, a constellation or a showpiece: can I see it
/// tonight, when, and where to look.
class ObjectSheet extends ConsumerStatefulWidget {
  const ObjectSheet({super.key, required this.thing});
  final SkyThing thing;
  @override
  ConsumerState<ObjectSheet> createState() => _ObjectSheetState();
}

class _ObjectSheetState extends ConsumerState<ObjectSheet> {
  bool _logged = false;

  SkyThing get t => widget.thing;

  Future<void> _found() async {
    final s = ref.read(settingsProvider).value;
    if (s?.latitude == null) return;
    final e = t.asEvent(DateTime.now(), s!.latitude!, s.longitude!);
    await ref.read(storeProvider).addFeedback(SeenFeedback.forEvent(e, seen: true, place: s.placeName));
    ref.invalidate(skyLogProvider);
    if (mounted) setState(() => _logged = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    final now = DateTime.now().toUtc();
    final h = t.position(now);
    final upNow = h.altitudeDeg > 0;
    final sight = t.sighting;
    final az = upNow ? h.azimuthDeg : (sight?.azDeg ?? h.azimuthDeg);
    final alt = upNow ? h.altitudeDeg : (sight?.altDeg ?? 0);
    final headline = t.whyNot != null
        ? 'Not tonight'
        : sight == null
            ? 'Not up tonight'
            : sight.verdict.yes
                ? (upNow && sight.best.difference(now).inMinutes.abs() < 45 ? 'Up now' : 'Best at ${fmtTime(sight.best)}')
                : sight.verdict.words;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Eyebrow(t.kind),
          const SizedBox(height: 6),
          Text(t.name, style: displaySerif(context, size: 38, weight: FontWeight.w500)),
          const SizedBox(height: 2),
          FoilText(headline, style: displaySerif(context, size: 34, weight: FontWeight.w600, italic: true, height: 1.05)),
          if (sight != null && t.whyNot == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                sight.verdict.yes ? sight.verdict.words : 'Tonight: ${sight.verdict.words.toLowerCase()}',
                style: TextStyle(color: verdictColor(sight.verdict), fontWeight: FontWeight.w600),
              ),
            ),
          if (t.whyNot != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t.whyNot!, style: const TextStyle(color: LookUpColors.grey)),
            ),
          const SizedBox(height: 18),
          if (t.whyNot == null && (upNow || sight != null)) ...[
            Center(child: CompassArrow(azimuthDeg: az, size: 150)),
            const SizedBox(height: 10),
            Text(
              '${upNow ? 'Now' : 'At ${fmtTime(sight!.best)}'}: look ${compassWord(az)}, ${elevationWord(alt)}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
          if (t.blurb != null) ...[
            const SizedBox(height: 16),
            Text(t.blurb!, textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.grey, height: 1.45)),
          ],
          const SizedBox(height: 16),
          const OrnamentRule(),
          const SizedBox(height: 12),
          Text(
            [
              if (t.extra != null) t.extra!,
              if (t.rise != null) 'rises ${fmtTime(t.rise!)}',
              if (t.set != null) 'sets ${fmtTime(t.set!)}',
            ].join('  ·  ').toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: LookUpColors.greyDim, fontSize: 10.5, letterSpacing: 1.6, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          if (s?.latitude != null && t.whyNot == null)
            FilledButton.icon(
              onPressed: () => openFinder(context, t.asEvent(DateTime.now(), s!.latitude!, s.longitude!)),
              icon: const Icon(Icons.explore_outlined),
              label: const Text('FIND IT IN THE SKY'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
          if (upNow)
            Center(
              child: TextButton.icon(
                onPressed: _logged ? null : _found,
                icon: Icon(_logged ? Icons.check : Icons.auto_awesome_outlined, size: 18),
                label: Text(_logged ? 'In your log' : 'I found it'),
              ),
            ),
        ]),
      ),
    );
  }
}
