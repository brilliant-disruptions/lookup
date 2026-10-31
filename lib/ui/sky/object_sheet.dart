import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_store.dart';
import '../../domain/sky/direction.dart';
import '../../domain/sky/visibility.dart';
import '../../state/providers.dart';
import '../../state/sky_state.dart';
import '../caught_it_screen.dart';
import '../finder_screen.dart';
import '../format.dart';
import '../kit/kit.dart';
import '../theme.dart';
import '../widgets/compass_arrow.dart';
import 'sky_thing.dart';

Future<void> showObjectSheet(BuildContext context, SkyThing thing, {DateTime? at, (double, double)? place}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ObjectSheet(thing: thing, at: at, place: place),
    );

/// A planet, the Moon, a constellation or a showpiece: can I see it
/// tonight, when, and where to look.
class ObjectSheet extends ConsumerStatefulWidget {
  const ObjectSheet({super.key, required this.thing, this.at, this.place});
  final SkyThing thing;

  /// Another moment the sky map was moved to: answer for then, not now.
  final DateTime? at;

  /// Somewhere else the map is standing (a famous night), as (lat, lon).
  final (double, double)? place;
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
    if (!mounted) return;
    setState(() => _logged = true);
    await showCaughtIt(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).value;
    final now = DateTime.now().toUtc();
    final h = t.position(now);
    final upNow = h.altitudeDeg > 0;
    final sight = t.sighting;
    // Looking ahead: where it'll be then, and the sky's verdict for then.
    final at = widget.at?.toUtc();
    final away = widget.place;
    final then = at != null && at.difference(now).abs() > const Duration(minutes: 10) && (away != null || s?.latitude != null) ? at : null;
    final hThen = then == null ? null : t.position(then);
    // Somewhere else, nobody has the weather: same as outside the forecast.
    final weather = away == null ? ref.watch(weatherProvider).value : null;
    final vThen = then == null
        ? null
        : canSee(
            altDeg: hThen!.altitudeDeg,
            mag: t.mag,
            diffuse: t.diffuse,
            c: SkyConditions.at(then, away?.$1 ?? s!.latitude!, away?.$2 ?? s!.longitude!, weather: weather),
            // Before electric light every sky was a dark sky.
            darkness: then.year < 1880 ? SkyDarkness.dark : (s?.skyDarkness ?? SkyDarkness.suburbs),
          );
    // Outside the forecast nobody knows the clouds: never a plain yes then.
    final thenWords = vThen == null
        ? null
        : vThen.yes && weather?.sampleAt(then!) == null
            ? 'Up then, if it\'s clear'
            : vThen.words;
    final hUp = hThen != null && hThen.altitudeDeg > 0 ? hThen : null;
    final upThen = hUp != null;
    final az = hUp?.azimuthDeg ?? (upNow ? h.azimuthDeg : (sight?.azDeg ?? h.azimuthDeg));
    final alt = hUp?.altitudeDeg ?? (upNow ? h.altitudeDeg : (sight?.altDeg ?? 0));
    final headline = then != null
        ? 'At ${fmtSkyMoment(then, away?.$2 ?? s?.longitude ?? 0)}'
        : t.whyNot != null
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
          Row(children: [
            thingGlyph(t, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.name, style: display(24, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(t.kind, style: const TextStyle(fontSize: 14, color: LookUpColors.grey)),
              ]),
            ),
            CircleButton(
              tooltip: (s?.isFavourite(t.id) ?? false) ? 'Remove from favourites' : 'Add to favourites',
              icon: (s?.isFavourite(t.id) ?? false) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: LookUpColors.red,
              active: s?.isFavourite(t.id) ?? false,
              onPressed: () => ref.read(settingsProvider.notifier).edit((s) => s.toggleFavourite(t.id)),
            ),
          ]),
          const SizedBox(height: 20),
          Text(headline, style: display(34, weight: FontWeight.w700)),
          if (vThen != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                Pill(thenWords!, dot: true, color: thenWords == vThen.words ? verdictColor(vThen) : LookUpColors.warn),
                if (sight != null && sight.verdict.yes && t.whyNot == null)
                  Pill('Tonight: best ${fmtTime(sight.best)}', color: LookUpColors.grey),
              ]),
            )
          else if (sight != null && t.whyNot == null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Pill(
                  sight.verdict.yes ? sight.verdict.words : 'Tonight: ${sight.verdict.words.toLowerCase()}',
                  dot: true,
                  color: verdictColor(sight.verdict),
                ),
              ),
            ),
          if (t.whyNot != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(t.whyNot!, style: const TextStyle(color: LookUpColors.grey)),
            ),
          const SizedBox(height: 18),
          if (then != null ? upThen : t.whyNot == null && (upNow || sight != null)) ...[
            Center(child: CompassArrow(azimuthDeg: az, size: 150)),
            const SizedBox(height: 10),
            Text(
              '${then != null ? 'At ${fmtSkyMoment(then, away?.$2 ?? s?.longitude ?? 0)}' : upNow ? 'Now' : 'At ${fmtTime(sight!.best)}'}: look ${compassWord(az)}, ${elevationWord(alt)}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
          if (t.blurb != null) ...[
            const SizedBox(height: 16),
            Text(t.blurb!, textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.grey, height: 1.45)),
          ],
          const SizedBox(height: 18),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
            if (t.extra != null) Pill('${t.extra![0].toUpperCase()}${t.extra!.substring(1)}', color: LookUpColors.grey),
            if (t.rise != null) Pill('Rises ${fmtTime(t.rise!)}', icon: Icons.north_east_rounded, color: LookUpColors.grey),
            if (t.set != null) Pill('Sets ${fmtTime(t.set!)}', icon: Icons.south_east_rounded, color: LookUpColors.grey),
          ]),
          const SizedBox(height: 22),
          if (s?.latitude != null && t.whyNot == null)
            FilledButton.icon(
              onPressed: () => openFinder(context, t.asEvent(DateTime.now(), s!.latitude!, s.longitude!)),
              icon: const Icon(Icons.explore_rounded),
              label: const Text('Find it in the sky'),
            ),
          if (upNow)
            Center(
              child: TextButton.icon(
                onPressed: _logged ? null : _found,
                icon: Icon(_logged ? Icons.check_rounded : Icons.auto_awesome_rounded, size: 18),
                label: Text(_logged ? 'In your log' : 'I found it'),
              ),
            ),
        ]),
      ),
    );
  }
}
