/// Credits: who made the data and pictures LookUp shows. Several sources
/// ask to be acknowledged where they're used (NASA's Universe of Learning,
/// Open-Meteo, Stellarium); the full notes live in assets/sky/SOURCES-*.txt.
library;

import 'package:flutter/material.dart';

import 'kit/kit.dart';
import 'theme.dart';

typedef Credit = ({String what, String who});

/// What's credited, in the order people meet it.
const credits = <Credit>[
  (
    what: 'Constellation pictures',
    who: 'Courtesy of NASA and NASA\'s Universe of Learning, redrawn from Johannes Hevelius\'s Uranographia (1690). '
        'Others from Hevelius\'s plates via Wikimedia Commons, and from Stellarium\'s sky culture illustrations '
        '(Free Art License 1.3; anchors CC BY-SA 4.0).',
  ),
  (
    what: 'Stars and constellation lines',
    who: 'd3-celestial (BSD-3), from the Hipparcos and Yale Bright Star catalogues; star motions from Hipparcos; '
        'a few faint anchor stars from the HYG database (CC BY-SA 4.0).',
  ),
  (what: 'Satellite orbits', who: 'CelesTrak.'),
  (what: 'Aurora and space weather', who: 'NOAA Space Weather Prediction Center.'),
  (what: 'Clouds and place search', who: 'Open-Meteo (CC BY 4.0).'),
  (what: 'Rocket launches and station crews', who: 'The Space Devs\' Launch Library.'),
  (what: 'How dark the sky is', who: 'NASA Black Marble night lights and Natural Earth.'),
  (what: 'Towns under a pass', who: 'Natural Earth (public domain).'),
  (what: 'Eclipses', who: 'NASA\'s Besselian elements, from the GSFC eclipse search engine.'),
  (what: 'Magnetic north', who: 'The World Magnetic Model 2025 (NOAA NCEI and the British Geological Survey).'),
];

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) => PageScaffold(title: 'Credits', children: [
        GroupedList(children: [
          for (final c in credits)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.what, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(c.who, style: const TextStyle(color: LookUpColors.grey, fontSize: 13.5, height: 1.4)),
              ]),
            ),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Text('Thank you to everyone who makes the sky free to share.',
              style: TextStyle(color: LookUpColors.greyDim, fontSize: 13)),
        ),
      ]);
}
