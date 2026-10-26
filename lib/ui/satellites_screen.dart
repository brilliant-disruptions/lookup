import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../state/sky_extras.dart';
import 'fancy/ornament_rule.dart';
import 'fancy/rise.dart';
import 'format.dart';
import 'look_sheet.dart';
import 'fancy/woven.dart';
import 'theme.dart';

Future<void> openSatellitesTonight(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SatellitesTonightScreen()));

/// The brightest satellites crossing tonight: Hubble, big rocket stages,
/// the new BlueBirds. A list to browse with the finder, never pushed.
class SatellitesTonightScreen extends ConsumerWidget {
  const SatellitesTonightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(brightTonightProvider);
    return Scaffold(
      appBar: const WovenHeader(title: Text('Satellites tonight'), subtitle: 'The bright ones, besides the stations'),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(brightTonightProvider.future),
        child: list.when(
          loading: () => ListView(children: const [
            SizedBox(height: 120),
            Center(child: CircularProgressIndicator()),
            SizedBox(height: 16),
            Center(child: Text('Working out tonight\'s passes…', style: TextStyle(color: LookUpColors.grey))),
          ]),
          error: (e, _) => ListView(padding: const EdgeInsets.all(24), children: const [
            Text('Couldn\'t download satellite orbits. Pull to try again.', style: TextStyle(color: LookUpColors.grey)),
          ]),
          data: (events) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text(
                  'The brightest things in orbit crossing your sky, besides the stations. Steady points of light, '
                  'moving: no blinking, no sound. Brightness is approximate.',
                  style: TextStyle(color: LookUpColors.grey, height: 1.45),
                ),
              ),
              if (events.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 24, 4, 0),
                  child: Text('Nothing bright enough passes over tonight.', style: TextStyle(color: LookUpColors.grey)),
                ),
              for (final (i, e) in events.indexed) ...[
                if (i == 0 || fmtDay(e.start) != fmtDay(events[i - 1].start))
                  Padding(padding: const EdgeInsets.fromLTRB(0, 22, 0, 12), child: OrnamentRule(label: fmtDay(e.start))),
                Rise(index: i, child: _SatelliteRow(e)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SatelliteRow extends StatelessWidget {
  const _SatelliteRow(this.e);
  final SkyEvent e;

  @override
  Widget build(BuildContext context) {
    final mag = (e.details['magnitude'] as num?)?.toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          onTap: () => showLookSheet(context, e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(eventTitle(e), style: displaySerif(context, size: 22, weight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(
                    describeArc(riseAzimuthDeg: e.riseAzimuthDeg, peakElevationDeg: e.peakElevationDeg, duration: e.duration),
                    style: const TextStyle(color: LookUpColors.grey, fontSize: 13, height: 1.35),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtTime(e.start), style: monoData(context, size: 14, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (mag != null)
                  Text(_brightWord(mag),
                      style: const TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: LookUpColors.blue)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  static String _brightWord(double mag) => mag <= 0
      ? 'VERY BRIGHT'
      : mag <= 1.5
          ? 'BRIGHT'
          : mag <= 2.5
              ? 'EASY'
              : 'DARK SKY';
}
