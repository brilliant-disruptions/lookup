import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../state/sky_extras.dart';
import 'format.dart';
import 'kit/kit.dart';
import 'look_sheet.dart';
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
    return PageScaffold(
      title: 'Satellites tonight',
      subtitle: 'The bright ones, besides the stations',
      onRefresh: () => ref.refresh(brightTonightProvider.future),
      children: list.when(
        loading: () => const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(child: Text('Working out tonight\'s passes…', style: TextStyle(color: LookUpColors.grey))),
        ],
        error: (e, _) => const [
          Padding(
            padding: EdgeInsets.all(8),
            child: Text('Couldn\'t download satellite orbits. Pull to try again.', style: TextStyle(color: LookUpColors.grey)),
          ),
        ],
        data: (events) {
          final days = <String, List<SkyEvent>>{};
          for (final e in events) {
            days.putIfAbsent(fmtDay(e.start), () => []).add(e);
          }
          var i = 0;
          return [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
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
            for (final d in days.entries) ...[
              SectionHeader(d.key, padding: const EdgeInsets.fromLTRB(4, 24, 4, 10)),
              Rise(index: i++, child: GroupedList(indent: 64, children: [for (final e in d.value) _SatelliteRow(e)])),
            ],
          ];
        },
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
    return ListRow(
      onTap: () => showLookSheet(context, e),
      leading: EventGlyph.of(e),
      title: eventTitle(e),
      subtitle: _sentence(describeArc(riseAzimuthDeg: e.riseAzimuthDeg, peakElevationDeg: e.peakElevationDeg, duration: e.duration)),
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text(fmtTime(e.start), style: numeric(size: 14, weight: FontWeight.w600)),
        if (mag != null) ...[
          const SizedBox(height: 4),
          Text(_brightWord(mag),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: mag <= 1.5 ? LookUpColors.gold : LookUpColors.grey)),
        ],
      ]),
    );
  }

  static String _sentence(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _brightWord(double mag) => mag <= 0
      ? 'Very bright'
      : mag <= 1.5
          ? 'Bright'
          : mag <= 2.5
              ? 'Easy'
              : 'Dark sky';
}
