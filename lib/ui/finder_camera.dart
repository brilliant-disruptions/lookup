/// Camera mode for the sky finder: the live camera with the pass drawn over
/// the real sky. Phone compasses are good to ~5–10°, so the path is a guide
/// to "that bit of sky", not a reticle to trust to the pixel.
library;

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../domain/finder/pointing.dart';
import '../domain/sky/direction.dart';
import 'format.dart';
import 'theme.dart';

/// Back camera, filling the screen (cropped to cover, never letterboxed).
class CameraBackdrop extends StatefulWidget {
  const CameraBackdrop({super.key, required this.onError, required this.onHeight});
  final void Function(String message) onError;

  /// Reports the on-screen height of the full camera frame, which is what
  /// the field of view maps to.
  final void Function(double height) onHeight;

  @override
  State<CameraBackdrop> createState() => _CameraBackdropState();
}

class _CameraBackdropState extends State<CameraBackdrop> with WidgetsBindingObserver {
  CameraController? _c;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final cams = await availableCameras();
      final back = cams.where((c) => c.lensDirection == CameraLensDirection.back).firstOrNull;
      if (back == null) {
        widget.onError('No back camera on this device.');
        return;
      }
      final c = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } on CameraException catch (e) {
      widget.onError(e.code.contains('Denied')
          ? 'Camera access is off. Turn it on in Settings to see the path over the sky.'
          : 'The camera didn\'t start.');
    } catch (_) {
      widget.onError('The camera didn\'t start.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null) return;
    if (state == AppLifecycleState.inactive) {
      _c = null;
      unawaited(c.dispose());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_c?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return const ColoredBox(color: Colors.black);
    final size = c.value.previewSize!; // landscape: width > height
    return LayoutBuilder(builder: (context, box) {
      // Portrait frame is (size.height × size.width); scale to cover the box.
      final scale = [box.maxWidth / size.height, box.maxHeight / size.width].reduce((a, b) => a > b ? a : b);
      widget.onHeight(size.width * scale);
      return ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: SizedBox(width: size.height * scale, height: size.width * scale, child: CameraPreview(c)),
        ),
      );
    });
  }
}

/// The pass's track with minute marks, where it is now, the target ring
/// and the horizon's compass points, all projected onto the camera view.
class SkyOverlayPainter extends CustomPainter {
  SkyOverlayPainter({
    required this.r,
    required this.declinationDeg,
    required this.target,
    required this.path,
    required this.now,
    required this.onTarget,
    required this.previewHeightPx,
  });

  final List<double> r;
  final double declinationDeg;
  final SkyDir target;
  final List<({DateTime t, SkyDir d})> path;
  final DateTime now;
  final bool onTarget;
  final double previewHeightPx;

  Offset? _at(Size size, SkyDir d) {
    final p = projectToScreen(r, d, declinationDeg: declinationDeg, previewHeightPx: previewHeightPx);
    return p == null ? null : size.center(Offset(p.x, p.y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.18);
    canvas.drawRect(Offset.zero & size, scrim);

    // Horizon and compass points.
    final horizon = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    Offset? prev;
    for (var az = 0; az <= 360; az += 5) {
      final p = _at(size, SkyDir(az.toDouble(), 0));
      if (p != null && prev != null && (p - prev).distance < size.width) canvas.drawLine(prev, p, horizon);
      prev = p;
    }
    for (final az in const [0, 45, 90, 135, 180, 225, 270, 315]) {
      final p = _at(size, SkyDir(az.toDouble(), 0));
      if (p == null) continue;
      _label(canvas, compassAbbrev(az.toDouble()), p + const Offset(0, 12), Colors.white.withValues(alpha: 0.8), 13);
    }

    // The pass: past part dim, future part bright, minute ticks with times.
    if (path.length > 1) {
      final past = Paint()
        ..color = LookUpColors.blue.withValues(alpha: 0.35)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final ahead = Paint()
        ..color = LookUpColors.blue
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < path.length; i++) {
        final a = _at(size, path[i - 1].d), b = _at(size, path[i].d);
        if (a == null || b == null || (b - a).distance > size.width) continue;
        canvas.drawLine(a, b, path[i].t.isBefore(now) ? past : ahead);
      }
      int? lastMinute;
      for (final p in path) {
        final minute = p.t.toLocal().minute;
        if (minute == lastMinute) continue;
        lastMinute = minute;
        final o = _at(size, p.d);
        if (o == null) continue;
        canvas.drawCircle(o, 3.5, Paint()..color = Colors.white);
        _label(canvas, fmtTime(p.t), o + const Offset(0, -16), Colors.white, 11);
      }
    }

    // Target: where it is now (or will appear).
    final t = _at(size, target);
    if (t != null) {
      canvas.drawCircle(t, 26, Paint()..color = LookUpColors.blue.withValues(alpha: 0.25));
      canvas.drawCircle(t, 26,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = onTarget ? 3 : 2
            ..color = onTarget ? LookUpColors.blue : Colors.white);
      canvas.drawCircle(t, 6, Paint()..color = Colors.white);
    }

    // Centre crosshair.
    final c = size.center(Offset.zero);
    final cross = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;
    canvas.drawLine(c - const Offset(14, 0), c + const Offset(14, 0), cross);
    canvas.drawLine(c - const Offset(0, 14), c + const Offset(0, 14), cross);
  }

  void _label(Canvas canvas, String text, Offset at, Color color, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(SkyOverlayPainter o) => true;
}
