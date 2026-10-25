/// Who's aboard the stations right now, from Launch Library 2's active
/// expeditions (decoded JSON in, plain lists out).
library;

class CrewMember {
  const CrewMember(this.name, this.role, this.agency);
  final String name;
  final String role;
  final String? agency;
}

enum Station { iss, tiangong }

/// Active crews by station. Unknown stations are ignored.
Map<Station, List<CrewMember>> crewFromExpeditions(Object? decoded) {
  final out = <Station, List<CrewMember>>{};
  final results = decoded is Map ? decoded['results'] : null;
  if (results is! List) return out;
  for (final r in results.whereType<Map>()) {
    final name = '${(r['spacestation'] as Map?)?['name'] ?? ''}'.toLowerCase();
    final station = name.contains('international') ? Station.iss : name.contains('tiangong') ? Station.tiangong : null;
    if (station == null) continue;
    for (final c in (r['crew'] as List? ?? const []).whereType<Map>()) {
      final a = c['astronaut'] as Map?;
      if (a == null) continue;
      (out[station] ??= []).add(CrewMember(
        '${a['name']}',
        '${(c['role'] as Map?)?['role'] ?? 'Crew'}',
        (a['agency'] as Map?)?['abbrev'] as String?,
      ));
    }
  }
  return out;
}

/// Keep only what [crewFromExpeditions] reads (the full payload carries
/// bios and images, ~100 KB).
Map<String, Object?> trimExpeditions(Object? decoded) {
  final results = decoded is Map ? decoded['results'] : null;
  return {
    'results': [
      if (results is List)
        for (final r in results.whereType<Map>())
          {
            'name': r['name'],
            'spacestation': {'name': (r['spacestation'] as Map?)?['name']},
            'crew': [
              for (final c in (r['crew'] as List? ?? const []).whereType<Map>())
                {
                  'role': {'role': (c['role'] as Map?)?['role']},
                  'astronaut': {
                    'name': (c['astronaut'] as Map?)?['name'],
                    'agency': {'abbrev': ((c['astronaut'] as Map?)?['agency'] as Map?)?['abbrev']},
                  },
                },
            ],
          },
    ],
  };
}
