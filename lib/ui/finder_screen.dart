/// Live sky finder: hold the phone up and it guides you onto the target,
/// tracking the satellite in real time. Vibrates when you're on it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rotation_sensor/flutter_rotation_sensor.dart';
import 'package:satellite_observer/satellite_observer.dart';

import '../domain/finder/pointing.dart';
import '../domain/models/sky_event.dart';
import '../domain/orbit/omm.dart';
import '../domain/sky/astro.dart';
import '../domain/sky/direction.dart';
import '../domain/sky/wmm.dart';
import '../state/providers.dart';
import 'fancy/starfield.dart';
import 'format.dart';
import 'theme.dart';

Future<void> openFinder(BuildContext context, SkyEvent event) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => FinderScreen(event: event)));

/// Where to point at [now] for [event]. Satellites are propagated live from
/// the elements stored on the event; sky objects are computed live.
class FinderTarget {
  FinderTarget(this.event, {required this.latDeg, required this.lonDeg}) {
    final omm = event.details['omm'];
    if (omm is Map) {
      try {
        _sat = SatelliteObserver(
          elements: OmmRecord.fromJson(omm.cast<String, Object?>()).toElements(),
          observer: Observer(latitudeDeg: latDeg, longitudeDeg: lonDeg),
        );
      } catch (_) {
        _sat = null;
      }
    }
  }

  final SkyEvent event;
  final double latDeg, lonDeg;
  SatelliteObserver? _sat;

  bool get isLive => _sat != null;

  SkyDir at(DateTime now) {
    final u = now.toUtc();
    final sat = _sat;
    if (sat != null) {
      // Before the pass: wait where it will appear. During: track it.
      final t = u.isBefore(event.start) ? event.start : (u.isAfter(event.end) ? event.end : u);
      final look = sat.lookAngleAt(t);
      return SkyDir(look.azimuthDeg, math.max(look.elevationDeg, 2));
    }
    switch (event.type) {
      case SkyEventType.auroraNow:
      case SkyEventType.auroraOutlook:
        return const SkyDir(0, 15);
      case SkyEventType.lunarEclipse:
        final m = moonHorizontal(u, latDeg, lonDeg);
        return SkyDir(m.azimuthDeg, m.altitudeDeg);
      case SkyEventType.planetPairing:
        final bodies = (event.details['bodies'] as List?)?.cast<String>() ?? const [];
        final dirs = [
          for (final b in bodies)
            if (b == 'Moon')
              moonHorizontal(u, latDeg, lonDeg)
            else
              for (final p in Planet.values)
                if (p.label == b) planetHorizontal(p, u, latDeg, lonDeg),
        ];
        if (dirs.isEmpty) return SkyDir(event.peakAzimuthDeg, event.peakElevationDeg);
        return SkyDir(dirs.map((d) => d.azimuthDeg).reduce((a, b) => a + b) / dirs.length,
            dirs.map((d) => d.altitudeDeg).reduce((a, b) => a + b) / dirs.length);
      default:
        return SkyDir(event.peakAzimuthDeg, event.peakElevationDeg);
    }
  }
}

class FinderScreen extends ConsumerStatefulWidget {
  const FinderScreen({super.key, required this.event, this.orientationStream});
  final SkyEvent event;

  /// Injected in tests; defaults to the fused rotation sensor.
  final Stream<List<double>>? orientationStream;

  @override
  ConsumerState<FinderScreen> createState() => _FinderState();
}

class _FinderState extends ConsumerState<FinderScreen> {
  StreamSubscription<List<double>>? _sub;
  List<double>? _r;
  String? _error;
  bool _wasOnTarget = false;
  late final double _declination;
  FinderTarget? _target;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final s = ref.read(settingsProvider).value;
    final lat = s?.latitude ?? 0, lon = s?.longitude ?? 0;
    _declination = declinationDeg(lat, lon, DateTime.now().toUtc());
    _target = FinderTarget(widget.event, latDeg: lat, lonDeg: lon);
    Stream<List<double>>? stream = widget.orientationStream;
    if (stream == null) {
      try {
        if (RotationSensor.isPlatformSupported) {
          RotationSensor.samplingPeriod = SensorInterval.uiInterval;
          RotationSensor.referenceFrame = ReferenceFrame.magneticNorth;
          RotationSensor.coordinateSystem = CoordinateSystem.device();
          stream = RotationSensor.orientationStream.map((e) {
            final m = e.rotationMatrix;
            return [m.a, m.b, m.c, m.d, m.e, m.f, m.g, m.h, m.i];
          });
        }
      } catch (e) {
        _error = '$e';
      }
    }
    _sub = stream?.listen((r) => setState(() => _r = r), onError: (e) => setState(() => _error = '$e'));
    if (stream == null) _error ??= 'This device has no orientation sensor.';
  }

  @override
  void dispose() {
    _sub?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final target = _target!.at(now);
    final r = _r;
    final camera = r == null ? null : cameraDirection(r, declinationDeg: _declination);
    final g = camera == null ? null : guide(camera, target);
    if (g != null && g.onTarget != _wasOnTarget) {
      _wasOnTarget = g.onTarget;
      if (g.onTarget) {
        HapticFeedback.heavyImpact();
        ref.read(analyticsProvider).log('finder_on_target', {'type': widget.event.type.name});
      }
    }
    final e = widget.event;
    final nowUtc = now.toUtc();
    final status = nowUtc.isBefore(e.start)
        ? 'Appears in ${fmtCountdown(e.start.difference(nowUtc))}. Point where it will rise.'
        : nowUtc.isBefore(e.end)
            ? (_target!.isLive ? 'Tracking it live' : 'Happening now')
            : 'That one\'s over';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Starfield(
        density: 0.0002,
        maxOpacity: 0.5,
        fadeBottom: false,
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              const Spacer(),
              const Eyebrow('Sky finder', color: LookUpColors.blue),
              const Spacer(),
              const SizedBox(width: 48),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(children: [
                Text(eventTitle(e), style: displaySerif(context, size: 34, weight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(status, textAlign: TextAlign.center, style: const TextStyle(color: LookUpColors.grey)),
              ]),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Semantics(
                  liveRegion: true,
                  label: g == null
                      ? 'Look ${compassWord(target.azimuthDeg)}, ${elevationWord(target.elevationDeg)}'
                      : g.words,
                  child: CustomPaint(
                    size: Size(c.maxWidth, c.maxHeight),
                    painter: _FinderPainter(guidance: g, onTarget: g?.onTarget ?? false),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                g?.words ?? (_error != null ? 'Look ${compassWord(target.azimuthDeg)}, ${elevationWord(target.elevationDeg)}' : 'Hold your phone up toward the sky'),
                textAlign: TextAlign.center,
                style: displaySerif(context, size: 30, italic: true, weight: FontWeight.w600,
                    color: (g?.onTarget ?? false) ? LookUpColors.blue : LookUpColors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${compassAbbrev(target.azimuthDeg)} ${target.azimuthDeg.round()}°  ·  ${target.elevationDeg.round()}° up',
                    style: monoData(context, size: 13, color: LookUpColors.grey)),
                if (camera != null) ...[
                  const SizedBox(width: 14),
                  Text('you ${camera.azimuthDeg.round()}° / ${camera.elevationDeg.round()}°',
                      style: monoData(context, size: 13, color: LookUpColors.greyDim)),
                ],
              ]),
            ),
            if (_error != null)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text('No motion sensor here, so use the directions above.',
                    textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text('Tip: wave the phone in a figure-8 once to calibrate the compass.',
                  textAlign: TextAlign.center, style: TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Reticle in the middle; the target drawn where it is relative to where
/// the camera points (≈ 5 px per degree), or an edge arrow when off-screen.
class _FinderPainter extends CustomPainter {
  _FinderPainter({required this.guidance, required this.onTarget});
  final Guidance? guidance;
  final bool onTarget;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final accent = onTarget ? LookUpColors.blue : LookUpColors.white;
    final ring = Paint()
      ..color = accent.withValues(alpha: onTarget ? 1 : 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = onTarget ? 3 : 1.5;
    canvas.drawCircle(c, 44, ring);
    final tick = Paint()
      ..color = LookUpColors.grey.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    for (final d in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      canvas.drawLine(c + d * 52, c + d * 70, tick);
    }
    final g = guidance;
    if (g == null) return;
    const pxPerDeg = 6.0;
    final p = c + Offset(g.dAzimuth * pxPerDeg, -g.dElevation * pxPerDeg);
    final bounds = Rect.fromCenter(center: c, width: size.width - 60, height: size.height - 60);
    if (bounds.contains(p)) {
      final glow = Paint()..color = LookUpColors.blue.withValues(alpha: 0.25);
      canvas.drawCircle(p, 22, glow);
      canvas.drawCircle(p, 9, Paint()..color = Colors.white);
    } else {
      // Arrow on the edge pointing toward the target.
      final dir = (p - c);
      final ang = math.atan2(dir.dy, dir.dx);
      final rx = bounds.width / 2, ry = bounds.height / 2;
      final t = math.min(rx / dir.dx.abs().clamp(1e-6, double.infinity), ry / dir.dy.abs().clamp(1e-6, double.infinity));
      final edge = c + dir * t;
      final path = Path()
        ..moveTo(edge.dx + 18 * math.cos(ang), edge.dy + 18 * math.sin(ang))
        ..lineTo(edge.dx + 14 * math.cos(ang + 2.5), edge.dy + 14 * math.sin(ang + 2.5))
        ..lineTo(edge.dx + 14 * math.cos(ang - 2.5), edge.dy + 14 * math.sin(ang - 2.5))
        ..close();
      canvas.drawPath(path, Paint()..color = LookUpColors.blue);
    }
  }

  @override
  bool shouldRepaint(_FinderPainter o) => true;
}
