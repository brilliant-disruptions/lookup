/// Poster-style share cards rendered to PNG: "I saw it" after an event, and
/// "Look up with me" before one. The share sheet shows the card first.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../state/providers.dart';
import 'fancy/foil_text.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/starfield.dart';
import 'format.dart';
import 'theme.dart';

enum ShareMode { sawIt, invite }

/// Renders the [RepaintBoundary] under [key] to a PNG and opens the share
/// sheet with it and [text].
Future<void> sharePoster(GlobalKey key, String text) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 3);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/lookup-${DateTime.now().millisecondsSinceEpoch}.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: text));
}

Future<void> showShareCard(BuildContext context, SkyEvent event, {ShareMode mode = ShareMode.sawIt}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ShareSheet(event: event, mode: mode),
    );

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.event, required this.mode});
  final SkyEvent event;
  final ShareMode mode;
  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final place = ref.read(settingsProvider).value?.placeName;
      await sharePoster(_key,
          widget.mode == ShareMode.invite ? inviteText(widget.event, place) : shareText(widget.event, place));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = ref.watch(settingsProvider).value?.placeName;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: SizedBox(
              width: 300,
              child: RepaintBoundary(
                key: _key,
                child: ShareCard(event: widget.event, mode: widget.mode, place: place),
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.ios_share),
            label: Text(widget.mode == ShareMode.invite ? 'SEND THE INVITE' : 'SHARE'),
          ),
        ]),
      ),
    );
  }
}

String inviteText(SkyEvent e, String? place) =>
    'Look up with me: ${eventTitle(e)} ${fmtDay(e.start).toLowerCase()} at ${fmtTime(e.start)}'
    '${place == null ? '' : ' over $place'}. Face ${compassWord(e.riseAzimuthDeg)}. (LookUp)';

/// 4:5 poster. Fixed logical size so it renders identically everywhere.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.event, required this.mode, this.place});
  final SkyEvent event;
  final ShareMode mode;
  final String? place;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final invite = mode == ShareMode.invite;
    final headline = invite ? 'Look up with me' : 'I saw it';
    return AspectRatio(
      aspectRatio: 4 / 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x553C9DFF)),
          ),
          child: Starfield(
            density: 0.0007,
            maxOpacity: 0.6,
            seed: e.id.hashCode,
            fadeBottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Eyebrow(headline, color: LookUpColors.blue),
                const SizedBox(height: 10),
                Text(invite ? eventTitle(e) : pastTitle(e), style: displaySerif(context, size: 34, weight: FontWeight.w500)),
                const SizedBox(height: 2),
                FoilText(
                  invite ? '${fmtDay(e.start)}, ${fmtTime(e.start)}' : fmtTime(e.peak),
                  gold: !invite,
                  style: displaySerif(context, size: invite ? 26 : 30, weight: FontWeight.w600, italic: true),
                ),
                const Spacer(),
                SizedBox(height: 90, width: double.infinity, child: CustomPaint(painter: _MiniArc(e.peakElevationDeg))),
                const SizedBox(height: 8),
                Text(
                  invite
                      ? 'Face ${compassWord(e.riseAzimuthDeg)}. ${elevationWord(e.peakElevationDeg)[0].toUpperCase()}${elevationWord(e.peakElevationDeg).substring(1)} at its best.'
                      : [
                          if (e.details['brightness'] is String) '${e.details['brightness']}',
                          if (place != null && place!.isNotEmpty) 'over $place',
                          fmtDay(e.peak).toLowerCase(),
                        ].join(' · '),
                  style: const TextStyle(color: LookUpColors.grey, fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 12),
                const OrnamentRule(),
                const SizedBox(height: 10),
                Row(children: [
                  Text('LookUp', style: displaySerif(context, size: 20, weight: FontWeight.w600)),
                  Text('.', style: displaySerif(context, size: 20, weight: FontWeight.w700, color: LookUpColors.blue)),
                  const Spacer(),
                  const Text('STEP OUTSIDE RIGHT NOW',
                      style: TextStyle(color: LookUpColors.greyDim, fontSize: 8.5, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniArc extends CustomPainter {
  _MiniArc(this.peakEl);
  final double peakEl;
  @override
  void paint(Canvas canvas, Size s) {
    final base = s.height - 4;
    canvas.drawLine(Offset(0, base), Offset(s.width, base), Paint()..color = LookUpColors.line);
    final h = (peakEl / 90).clamp(0.25, 1.0) * (s.height - 14);
    final path = Path()..moveTo(8, base);
    for (var i = 1; i <= 60; i++) {
      final t = i / 60;
      path.lineTo(8 + (s.width - 16) * t, base - h * 4 * t * (1 - t));
    }
    canvas.drawPath(path, Paint()
      ..color = LookUpColors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round);
    final peak = Offset(s.width / 2, base - h);
    canvas.drawCircle(peak, 10, Paint()..color = LookUpColors.blue.withValues(alpha: 0.3));
    canvas.drawCircle(peak, 4.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MiniArc o) => o.peakEl != peakEl;
}
