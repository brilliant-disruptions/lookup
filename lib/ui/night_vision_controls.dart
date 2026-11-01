/// Night vision's controls, used in Settings and in the card that drops
/// down when Settings is pressed and held: on or off, Auto (follows the
/// light around you, like Auto-Brightness) and "How red". Dragging How red
/// turns the whole app that red as you go, by day too, as a preview.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/night_state.dart';
import '../state/providers.dart';
import 'kit/kit.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// "How red": shows what the screen does now and saves where it's left
/// (a nudge to Auto, or the fixed level with Auto off).
class HowRedSlider extends ConsumerStatefulWidget {
  const HowRedSlider({super.key, this.dense = false});
  final bool dense;

  @override
  ConsumerState<HowRedSlider> createState() => _HowRedSliderState();
}

class _HowRedSliderState extends ConsumerState<HowRedSlider> {
  double? _dragging;

  void _move(double v) {
    setState(() => _dragging = v);
    ref.read(nightVisionDragProvider.notifier).to(v);
  }

  Future<void> _end(double v) async {
    await saveHowRed(ref, v);
    ref.read(nightVisionDragProvider.notifier).to(null);
    if (mounted) setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final double value = _dragging ?? ref.watch(nightVisionStrengthProvider);
    final labels = TextStyle(fontSize: widget.dense ? 11.5 : 12.5, color: LookUpColors.grey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: LookUpColors.red,
            inactiveTrackColor: LookUpColors.glassStrong,
            thumbColor: LookUpColors.white,
            overlayColor: LookUpColors.red.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            onChangeStart: _move,
            onChanged: _move,
            onChangeEnd: _end,
            semanticFormatterCallback: (v) => v < 0.01 ? 'True colours' : '${(v * 100).round()}% red',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Less', style: labels), Text('More', style: labels)]),
        ),
      ],
    );
  }
}

/// One line on what night vision is doing right now.
String nightVisionStatus(WidgetRef ref) {
  final s = ref.watch(settingsProvider).value;
  if (s == null || !s.nightVision) return 'Off: the screen stays in true colours.';
  if (s.latitude == null) return 'Turns on after sunset once LookUp knows where you are.';
  if (!ref.watch(nightVisionOnProvider)) return 'Comes on after sunset. Drag to preview it.';
  final t = ref.watch(nightVisionStrengthProvider);
  if (t < 0.02) return s.nightVisionFollowsLight ? 'True colours for now: it\'s light around you.' : 'True colours.';
  return '${(t * 100).round()}% red right now.';
}

/// Pressing and holding Settings: just the night-vision card, under the
/// button. A tap on Settings still opens all of Settings.
Future<void> showNightVisionCard(BuildContext context) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => const NightVisionCard(),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), alignment: Alignment.topRight, child: child),
    ),
  );
}

class NightVisionCard extends ConsumerWidget {
  const NightVisionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider).value;
    final top = MediaQuery.paddingOf(context).top + AppHeader.height;
    final edit = ref.read(settingsProvider.notifier).edit;
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, top, 12, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            color: LookUpColors.panelRaised,
            elevation: 4,
            shadowColor: Colors.black54,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg), side: const BorderSide(color: LookUpColors.line)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(Icons.visibility_rounded, size: 20, color: LookUpColors.red),
                    const SizedBox(width: 10),
                    const Expanded(child: Text('Night vision', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                    Switch(value: s?.nightVision ?? true, onChanged: (v) => edit((x) => x.copyWith(nightVision: v))),
                  ]),
                  if (s?.nightVision ?? true) ...[
                    Row(children: [
                      const Expanded(child: Text('How red', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                      FilterChip(
                        label: const Text('Auto'),
                        selected: s?.nightVisionFollowsLight ?? true,
                        showCheckmark: false,
                        selectedColor: LookUpColors.blue,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: (s?.nightVisionFollowsLight ?? true) ? Colors.white : LookUpColors.grey,
                        ),
                        tooltip: 'Follows the light around you',
                        onSelected: (on) => setAuto(ref, on),
                      ),
                      const SizedBox(width: 8),
                    ]),
                    const HowRedSlider(dense: true),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 8, 0),
                    child: Text(nightVisionStatus(ref), style: const TextStyle(fontSize: 12.5, color: LookUpColors.grey, height: 1.3)),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
                      onPressed: () {
                        Navigator.of(context).pop();
                        openSettings(context, nightVision: true);
                      },
                      child: const Text('All night vision settings ›'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Auto on starts fresh from what the light says; Auto off keeps the
/// screen exactly as red as it is now, so nothing jumps.
Future<void> setAuto(WidgetRef ref, bool on) {
  final now = ref.read(nightVisionStrengthProvider);
  return ref.read(settingsProvider.notifier).edit((x) => on
      ? x.copyWith(nightVisionFollowsLight: true, nightVisionNudge: 0)
      : x.copyWith(nightVisionFollowsLight: false, nightVisionLevel: now));
}
