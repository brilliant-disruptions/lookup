import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/orbit/omm.dart';
import '../../domain/orbit/orbit_facts.dart';
import '../../domain/satellites/crew.dart';
import '../../state/sky_extras.dart';
import '../theme.dart';

/// "7 people aboard, moving at 17,100 mph": what you're actually looking at.
class StationFacts extends ConsumerWidget {
  const StationFacts({super.key, required this.event});
  final SkyEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final omm = event.details['omm'];
    OrbitFacts? facts;
    if (omm is Map) {
      try {
        facts = OrbitFacts.at(OmmRecord.fromJson(omm.cast<String, Object?>()), event.peak);
      } catch (_) {}
    }
    final station = event.type == SkyEventType.tiangong ? Station.tiangong : Station.iss;
    final crew = ref.watch(crewProvider).value?[station] ?? const <CrewMember>[];
    if (facts == null && crew.isEmpty) return const SizedBox.shrink();
    final line = [
      if (crew.isNotEmpty) '${crew.length} people aboard',
      if (facts != null) '${_thousands(facts.speedMph)} mph',
      if (facts != null) '${facts.altitudeKm.round()} km up',
      if (facts != null) 'a lap every ${facts.minutesPerOrbit.round()} min',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: const Eyebrow('Who\'s up there', color: LookUpColors.blue),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(line, style: const TextStyle(color: LookUpColors.grey, fontSize: 13)),
          ),
          children: [
            for (final c in crew)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(c.name, style: const TextStyle(fontSize: 14))),
                  Text([c.role, ?c.agency].join(' · '),
                      style: const TextStyle(color: LookUpColors.greyDim, fontSize: 12)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  static String _thousands(double v) {
    final n = (v / 100).round() * 100;
    final s = n.toString();
    return s.length > 3 ? '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}' : s;
  }
}
