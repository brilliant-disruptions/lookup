import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/log/starter_sky.dart';
import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../state/plan_state.dart';
import '../state/providers.dart';
import '../state/sky_state.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
import 'plan_screen.dart';
import 'sky/object_sheet.dart';
import 'sky/sky_thing.dart';
import 'theme.dart';

/// "Your first three" on Tonight, for new users: a pass, a planet and a star
/// pattern from their own sky, each on its first easy night. Gives a new
/// install something to do tonight instead of a countdown to wait out.
/// Gone once all three are seen (or for anyone with a long log already).
class StarterSkyCard extends ConsumerWidget {
  const StarterSkyCard({super.key, this.padding = const EdgeInsets.only(top: 12)});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(skyLogProvider).value;
    final s = ref.watch(settingsProvider).value;
    final events = ref.watch(homeProvider).value?.events;
    final nights = ref.watch(nightsAheadProvider).value;
    final catalog = ref.watch(skyCatalogProvider).value;
    if (log == null || s == null || events == null || nights == null || catalog == null || !s.hasLocation) {
      return const SizedBox.shrink();
    }
    final steps = StarterSky.plan(log: log, events: events, nights: nights, now: DateTime.now(), isPlus: s.isPlus);
    if (steps == null) return const SizedBox.shrink();
    final done = steps.where((x) => x.done).length;
    final alertsOn = ref.watch(alertsEnabledProvider).value != false;

    Widget row(StarterStep step) {
      final (String title, String sub, Widget glyph, VoidCallback? onTap, bool tonight) = switch (step.kind) {
        StarterKind.pass => (
          step.event == null ? 'A space station pass' : eventTitle(step.event!),
          step.done
              ? 'Seen'
              : step.event == null
              ? 'None bright enough over you in the next two weeks yet'
              : '${fmtDay(step.event!.start)}, ${fmtTime(step.event!.start)} · ${alertsOn ? 'we\'ll tap you if it\'s clear' : 'turn alerts on to get a tap'}',
          step.event == null ? EventGlyph.forType(SkyEventType.iss) : EventGlyph.of(step.event!),
          step.event == null ? null : () => showLookSheet(context, step.event!),
          step.event != null && fmtDay(step.event!.start) == 'Tonight',
        ),
        _ => (
          step.skyId == null ? (step.kind == StarterKind.planet ? 'A planet' : 'A star pattern') : skyName(step.skyId!, catalog),
          step.done
              ? 'Seen'
              : step.skyId == null
              ? 'Not well placed in the next two weeks'
              : '${_night(step.night!, nights[step.night!].window?.start)} · best ${fmtTime(step.sighting!.best)}, ${compassWord(step.sighting!.azDeg)}',
          step.skyId == null
              ? EventGlyph(icon: step.kind == StarterKind.planet ? null : Icons.star_rounded, color: LookUpColors.gold)
              : glyphForId(step.skyId!),
          step.skyId == null
              ? null
              : step.night == 0
              ? () {
                  final thing = skyThingsOf(nights[0], s.latitude!, s.longitude!, catalog)[step.skyId!];
                  if (thing != null) showObjectSheet(context, thing);
                }
              : () => openPlan(context, night: step.night!),
          step.night == 0,
        ),
      };
      return ListRow(
        leading: step.done ? const _Tick() : glyph,
        title: title,
        titleColor: step.done ? LookUpColors.grey : null,
        subtitle: sub,
        subtitleLines: 2,
        trailing: !step.done && tonight ? const Pill('Tonight', dot: true, color: LookUpColors.good) : null,
        chevron: !step.done && onTap != null,
        onTap: step.done ? null : onTap,
      );
    }

    return Padding(
      padding: padding,
      child: GlassCard(
        tint: LookUpColors.gold,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Kicker('Your first three', color: LookUpColors.gold),
                        const SizedBox(height: 4),
                        Text(
                          done == 0
                              ? 'Three sights to start with'
                              : done == 1
                              ? 'One down, two to go'
                              : 'One to go',
                          style: display(20, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'A pass, a planet and a star pattern, each on its best night over you.',
                          style: TextStyle(fontSize: 13.5, color: LookUpColors.grey, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Progress(done: done, of: steps.length),
                ],
              ),
            ),
            for (final (i, step) in steps.indexed) ...[if (i > 0) const Divider(height: 1, indent: 64), row(step)],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  static String _night(int night, DateTime? windowStart) => switch (night) {
    0 => 'Tonight',
    1 => 'Tomorrow night',
    _ => windowStart == null ? 'In $night nights' : fmtDay(windowStart),
  };
}

class _Tick extends StatelessWidget {
  const _Tick();
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(color: LookUpColors.good.withValues(alpha: 0.16), shape: BoxShape.circle),
    child: const Icon(Icons.check_rounded, color: LookUpColors.good, size: 22, semanticLabel: 'Seen'),
  );
}

/// Three arcs round a count: "1/3".
class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.of});
  final int done;
  final int of;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$done of $of seen',
    excludeSemantics: true,
    child: SizedBox(
      width: 52,
      height: 52,
      child: CustomPaint(
        painter: _ProgressPainter(done: done, of: of),
        child: Center(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$done',
                  style: numeric(size: 17, weight: FontWeight.w700),
                ),
                TextSpan(
                  text: '/$of',
                  style: numeric(size: 12, color: LookUpColors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter({required this.done, required this.of});
  final int done;
  final int of;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 3);
    const gap = 0.32;
    final sweep = math.pi * 2 / of;
    for (var i = 0; i < of; i++) {
      canvas.drawArc(
        r,
        -math.pi / 2 + i * sweep + gap / 2,
        sweep - gap,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = i < done ? LookUpColors.gold : LookUpColors.line,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => old.done != done || old.of != of;
}
