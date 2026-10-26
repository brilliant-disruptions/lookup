/// The fixed sky: naked-eye stars, the 88 constellations and a handful of
/// showpieces worth stepping out for. Positions are J2000 (precession moves
/// them ~0.4° by 2026: invisible at this scale).
///
/// Star and constellation data: d3-celestial (c) Olaf Frohn, BSD-3-Clause,
/// from Hipparcos / the Yale Bright Star Catalog (assets/sky/).
library;

import 'astro.dart';

class Star {
  const Star(this.raDeg, this.decDeg, this.mag, {this.bv, this.hip, this.name});
  final double raDeg;
  final double decDeg;
  final double mag;

  /// Colour index: < 0 blue-white … > 1.2 orange-red.
  final double? bv;
  final int? hip;
  final String? name;

  Horizontal horizontal(DateTime utc, double lat, double lon) =>
      toHorizontal(Equatorial(raDeg, decDeg, 1), utc, lat, lon);
}

class Constellation {
  const Constellation({
    required this.id,
    required this.name,
    required this.rank,
    required this.centerRaDeg,
    required this.centerDecDeg,
    required this.lines,
    this.meaning,
  });
  final String id; // IAU abbreviation, e.g. "Ori"
  final String name; // Latin, as on every star chart: "Taurus"

  /// What the name means, when it isn't obvious: "the Bull".
  final String? meaning;

  /// 1 = the famous ones, 3 = obscure.
  final int rank;
  final double centerRaDeg;
  final double centerDecDeg;

  /// Stick figure: polylines of (ra, dec) in degrees.
  final List<List<(double, double)>> lines;

  Horizontal center(DateTime utc, double lat, double lon) =>
      toHorizontal(Equatorial(centerRaDeg, centerDecDeg, 1), utc, lat, lon);
}

class SkyCatalog {
  SkyCatalog({required this.stars, required this.constellations});
  final List<Star> stars; // brightest first
  final List<Constellation> constellations;

  static final empty = SkyCatalog(stars: const [], constellations: const []);

  /// From the decoded `assets/sky/stars.json` and `constellations.json`.
  factory SkyCatalog.fromJson(Map<String, Object?> starsJson, Map<String, Object?> constellationsJson) {
    final names = (starsJson['names'] as Map?)?.cast<String, Object?>() ?? const {};
    double d(Object? x) => (x as num).toDouble();
    return SkyCatalog(
      stars: [
        for (final s in (starsJson['stars'] as List? ?? const []).cast<List>())
          Star(d(s[0]), d(s[1]), d(s[2]),
              bv: (s[3] as num?)?.toDouble(),
              hip: (s[4] as num?)?.toInt(),
              name: names['${s[4]}'] as String?),
      ],
      constellations: [
        for (final c in (constellationsJson['constellations'] as List? ?? const []).cast<Map>())
          Constellation(
            id: c['id'] as String,
            name: c['name'] as String,
            meaning: c['en'] == null ? null : 'the ${c['en']}',
            rank: (c['rank'] as num).toInt(),
            centerRaDeg: d((c['c'] as List)[0]),
            centerDecDeg: d((c['c'] as List)[1]),
            lines: [
              for (final seg in (c['l'] as List).cast<List>())
                [for (final p in seg.cast<List>()) (d(p[0]), d(p[1]))],
            ],
          ),
      ],
    );
  }

  Constellation? constellation(String id) => constellations.where((c) => c.id == id).firstOrNull;
}

enum ShowpieceKind { cluster, nebula, galaxy, doubleStar, milkyWay }

enum Aid { eyes, binoculars, telescope }

/// Hand-picked deep-sky sights. [mag] is the integrated brightness; [diffuse]
/// ones (galaxies, nebulae) need a darker sky than a star of that magnitude.
class Showpiece {
  const Showpiece({
    required this.id,
    required this.name,
    required this.kind,
    required this.raDeg,
    required this.decDeg,
    required this.mag,
    required this.aid,
    required this.constellation,
    required this.blurb,
    this.diffuse = false,
  });
  final String id;
  final String name;
  final ShowpieceKind kind;
  final double raDeg;
  final double decDeg;
  final double mag;
  final Aid aid;
  final String constellation; // IAU id
  final String blurb;
  final bool diffuse;

  Horizontal horizontal(DateTime utc, double lat, double lon) =>
      toHorizontal(Equatorial(raDeg, decDeg, 1), utc, lat, lon);
}

const showpieces = <Showpiece>[
  Showpiece(id: 'm45', name: 'The Pleiades', kind: ShowpieceKind.cluster, raDeg: 56.75, decDeg: 24.12, mag: 1.6,
      aid: Aid.eyes, constellation: 'Tau',
      blurb: 'The Seven Sisters: a tiny dipper-shaped clutch of blue stars. Most people see six; binoculars show dozens.'),
  Showpiece(id: 'hyades', name: 'The Hyades', kind: ShowpieceKind.cluster, raDeg: 66.75, decDeg: 15.87, mag: 0.5,
      aid: Aid.eyes, constellation: 'Tau',
      blurb: 'The V-shaped face of Taurus the bull, with orange Aldebaran as its eye (Aldebaran is just in front of it).'),
  Showpiece(id: 'm42', name: 'Orion Nebula', kind: ShowpieceKind.nebula, raDeg: 83.82, decDeg: -5.39, mag: 4.0,
      aid: Aid.eyes, constellation: 'Ori', diffuse: true,
      blurb: 'The fuzzy middle "star" of Orion\'s sword: a cloud where stars are being born, 1,300 light-years away.'),
  Showpiece(id: 'm31', name: 'Andromeda Galaxy', kind: ShowpieceKind.galaxy, raDeg: 10.68, decDeg: 41.27, mag: 3.4,
      aid: Aid.eyes, constellation: 'And', diffuse: true,
      blurb: 'The farthest thing you can see with your own eyes: a whole galaxy, 2.5 million light-years away. A faint oval smudge.'),
  Showpiece(id: 'm44', name: 'Beehive Cluster', kind: ShowpieceKind.cluster, raDeg: 130.1, decDeg: 19.67, mag: 3.7,
      aid: Aid.binoculars, constellation: 'Cnc', diffuse: true,
      blurb: 'A misty patch in Cancer that binoculars turn into a swarm of stars.'),
  Showpiece(id: 'double-cluster', name: 'Double Cluster', kind: ShowpieceKind.cluster, raDeg: 34.75, decDeg: 57.13, mag: 4.3,
      aid: Aid.binoculars, constellation: 'Per', diffuse: true,
      blurb: 'Two star clusters side by side between Perseus and Cassiopeia. Stunning in binoculars.'),
  Showpiece(id: 'mizar', name: 'Mizar and Alcor', kind: ShowpieceKind.doubleStar, raDeg: 200.98, decDeg: 54.93, mag: 2.2,
      aid: Aid.eyes, constellation: 'UMa',
      blurb: 'The bend in the Big Dipper\'s handle is two stars. Ancient armies used it as an eyesight test.'),
  Showpiece(id: 'albireo', name: 'Albireo', kind: ShowpieceKind.doubleStar, raDeg: 292.68, decDeg: 27.96, mag: 3.1,
      aid: Aid.telescope, constellation: 'Cyg',
      blurb: 'The head of the Swan. A small telescope splits it into gold and blue: the prettiest double star in the sky.'),
  Showpiece(id: 'm13', name: 'Hercules Cluster', kind: ShowpieceKind.cluster, raDeg: 250.42, decDeg: 36.46, mag: 5.8,
      aid: Aid.binoculars, constellation: 'Her', diffuse: true,
      blurb: 'A ball of several hundred thousand ancient stars. A fuzzy star in binoculars.'),
  Showpiece(id: 'm7', name: 'Ptolemy Cluster', kind: ShowpieceKind.cluster, raDeg: 268.47, decDeg: -34.79, mag: 3.3,
      aid: Aid.eyes, constellation: 'Sco', diffuse: true,
      blurb: 'A bright cluster by the Scorpion\'s tail, noted by Ptolemy in 130 AD.'),
  Showpiece(id: 'milky-way', name: 'Milky Way core', kind: ShowpieceKind.milkyWay, raDeg: 266.4, decDeg: -29.0, mag: 4.5,
      aid: Aid.eyes, constellation: 'Sgr', diffuse: true,
      blurb: 'The bright heart of our own galaxy, low in the south in summer. Needs a properly dark sky and no Moon.'),
  Showpiece(id: 'omega-cen', name: 'Omega Centauri', kind: ShowpieceKind.cluster, raDeg: 201.7, decDeg: -47.48, mag: 3.9,
      aid: Aid.eyes, constellation: 'Cen', diffuse: true,
      blurb: 'The biggest star cluster in our galaxy: ten million stars in a fuzzy ball.'),
  Showpiece(id: 'carina', name: 'Carina Nebula', kind: ShowpieceKind.nebula, raDeg: 161.27, decDeg: -59.87, mag: 1.0,
      aid: Aid.eyes, constellation: 'Car', diffuse: true,
      blurb: 'A huge glowing cloud in the southern Milky Way, brighter than the Orion Nebula.'),
  Showpiece(id: 'lmc', name: 'Large Magellanic Cloud', kind: ShowpieceKind.galaxy, raDeg: 80.89, decDeg: -69.76, mag: 0.9,
      aid: Aid.eyes, constellation: 'Dor', diffuse: true,
      blurb: 'A neighbouring galaxy that looks like a detached piece of the Milky Way.'),
  Showpiece(id: 'smc', name: 'Small Magellanic Cloud', kind: ShowpieceKind.galaxy, raDeg: 13.19, decDeg: -72.83, mag: 2.7,
      aid: Aid.eyes, constellation: 'Tuc', diffuse: true,
      blurb: 'The Large Cloud\'s little sibling, another galaxy orbiting ours.'),
];

/// One-line guides for the constellations people actually look for.
const constellationBlurbs = <String, String>{
  'Ori': 'The Hunter: three stars in a row for his belt, red Betelgeuse at his shoulder, blue Rigel at his knee.',
  'UMa': 'Home of the Big Dipper. The two stars at the end of its bowl point to Polaris.',
  'UMi': 'The Little Dipper. Polaris, the North Star, is the tip of its handle and barely moves all night.',
  'Cas': 'A bright W (or M) on the far side of Polaris from the Big Dipper.',
  'Cyg': 'The Swan, flying down the Milky Way. Its bright tail star Deneb is part of the Summer Triangle.',
  'Lyr': 'Small but bright: Vega, one of the brightest stars, crowns this little harp.',
  'Aql': 'The Eagle. Its bright star Altair completes the Summer Triangle with Vega and Deneb.',
  'Sco': 'A curling scorpion low in the south in summer, with red Antares at its heart.',
  'Sgr': 'The Teapot. Steam from its spout is the brightest part of the Milky Way.',
  'Leo': 'A backwards question mark for the lion\'s mane, ending in bright Regulus.',
  'Tau': 'The Bull, with orange Aldebaran for its eye and the Pleiades on its shoulder.',
  'Gem': 'The Twins: Castor and Pollux, two bright stars side by side.',
  'CMa': 'The Great Dog, with Sirius, the brightest star in the night sky.',
  'Boo': 'A kite shape topped by orange Arcturus. Follow the arc of the Dipper\'s handle to find it.',
  'Peg': 'The Great Square of Pegasus: four stars marking a big empty square in autumn.',
  'And': 'A chain of stars off Pegasus. Home of the Andromeda Galaxy.',
  'Per': 'The hero Perseus, with the "demon star" Algol that dims every three days.',
  'Aur': 'A pentagon of stars with bright, yellow Capella.',
  'Cru': 'The Southern Cross: the smallest constellation and the south\'s signpost.',
  'Cen': 'Home of Alpha Centauri, the nearest star system to the Sun.',
  'Vir': 'The Maiden, with blue-white Spica. Follow the Dipper\'s handle: "arc to Arcturus, spike to Spica".',
  'Her': 'A keystone of four stars, with a great star cluster on one side.',
  'Cap': 'A faint triangle-shaped sea-goat low in the south in early autumn.',
  'Aqr': 'The Water Bearer, a faint spread of stars in the autumn sky.',
  'Psc': 'Two fish tied by a cord, faint, under the Great Square.',
  'Ari': 'A short crooked line of stars: the Ram.',
  'Cnc': 'Faint, but home to the Beehive Cluster.',
  'Lib': 'The Scales, between Virgo and Scorpius.',
  'Oph': 'The Serpent Bearer, a big faint house shape above Scorpius.',
  'Dra': 'The Dragon winds between the two Dippers.',
  'Cep': 'A faint house shape near Cassiopeia.',
  'CMi': 'The Little Dog: really just bright Procyon and one other star.',
  'Lep': 'The Hare, crouched at Orion\'s feet.',
  'Eri': 'The River, winding south from Orion\'s foot.',
  'PsA': 'Faint except for Fomalhaut, the lonely bright star of the autumn south.',
  'Car': 'The Keel of the ship Argo, with Canopus, the second-brightest star.',
};
