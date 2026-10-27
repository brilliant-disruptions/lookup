/// One thing in the sky as the UI sees it (a planet, the Moon, a
/// constellation, a showpiece), with tonight's verdict and how the finder
/// can track it.
library;

import 'package:flutter/material.dart';

import '../../domain/models/sky_event.dart';
import '../../domain/sky/astro.dart';
import '../../domain/sky/catalog.dart';
import '../../domain/sky/tonight.dart';
import '../../domain/sky/direction.dart';
import '../../domain/sky/visibility.dart';
import '../format.dart';
import '../kit/event_style.dart';
import '../theme.dart';

class SkyThing {
  const SkyThing({
    required this.id,
    required this.name,
    required this.kind,
    required this.position,
    required this.mag,
    required this.finder,
    this.blurb,
    this.sighting,
    this.whyNot,
    this.rise,
    this.set,
    this.extra,
  });

  final String id;
  final String name;
  final String kind;
  final Horizontal Function(DateTime utc) position;
  final double mag;

  /// What [FinderTarget] needs to track it live: {planet} | {moon} | {ra, dec}.
  final Map<String, Object?> finder;
  final String? blurb;
  final SkySighting? sighting;
  final String? whyNot;
  final DateTime? rise;
  final DateTime? set;

  /// One more fact line ("Brightest star: Betelgeuse", "Binoculars").
  final String? extra;

  bool get seeable => sighting?.verdict.yes ?? false;

  /// Short status for list rows: "Best 9:40 PM, south-east" or why not.
  String get status {
    final s = sighting;
    if (whyNot != null) return whyNot!;
    if (s == null) return 'Not up tonight';
    if (!s.verdict.yes) return s.verdict.words;
    return 'Best ${fmtTime(s.best)}, ${compassWord(s.azDeg)}';
  }

  /// As an event, so the finder, the Look sheet's sharing and the log work.
  SkyEvent asEvent(DateTime now, double lat, double lon) {
    final n = now.toUtc();
    final s = sighting;
    final peak = s != null && s.best.isAfter(n) ? s.best : n;
    final h = s != null && peak == s.best ? null : position(n);
    return SkyEvent(
      id: 'obj:$id',
      type: SkyEventType.skyObject,
      start: n,
      peak: peak,
      end: peak.add(const Duration(hours: 6)),
      peakElevationDeg: h?.altitudeDeg ?? s!.altDeg,
      riseAzimuthDeg: h?.azimuthDeg ?? s!.azDeg,
      peakAzimuthDeg: h?.azimuthDeg ?? s!.azDeg,
      setAzimuthDeg: h?.azimuthDeg ?? s!.azDeg,
      details: {'name': name, 'magnitude': double.parse(mag.toStringAsFixed(1)), ...finder},
    );
  }

  static SkyThing planet(PlanetTonight p, double lat, double lon) => SkyThing(
        id: 'planet:${p.planet.name}',
        name: p.planet.label,
        kind: 'Planet',
        position: (t) => planetHorizontal(p.planet, t, lat, lon),
        mag: p.magnitude,
        finder: {'planet': p.planet.label},
        blurb: _planetBlurbs[p.planet],
        sighting: p.sighting,
        whyNot: p.whyNot,
        rise: p.rise,
        set: p.set,
        extra: planetBrightnessWord(p.magnitude),
      );

  static SkyThing moon(MoonTonight m, double lat, double lon) => SkyThing(
        id: 'moon',
        name: 'The Moon',
        kind: '${m.phase.label} · ${(m.illumination * 100).round()}% lit',
        position: (t) => moonHorizontal(t, lat, lon),
        mag: -10,
        finder: const {'moon': true},
        blurb: m.illumination > 0.9
            ? 'Bright enough to wash out faint stars tonight. A good night for the Moon itself.'
            : m.illumination < 0.25
                ? 'A thin Moon: look along the line between light and dark for craters in binoculars.'
                : 'Binoculars show craters best along the edge between light and dark.',
        sighting: m.sighting,
        rise: m.rise,
        set: m.set,
      );

  static SkyThing constellation(ConstellationTonight c, double lat, double lon, SkyCatalog catalog) {
    final con = c.constellation;
    return SkyThing(
      id: 'con:${con.id}',
      name: con.name,
      kind: con.meaning == null ? 'Constellation' : 'Constellation · ${con.meaning}',
      position: (t) => con.center(t, lat, lon),
      mag: 2,
      finder: {'ra': con.centerRaDeg, 'dec': con.centerDecDeg},
      blurb: constellationBlurbs[con.id],
      sighting: c.sighting,
      extra: _brightestName(catalog, con),
    );
  }

  static SkyThing showpiece(ShowpieceTonight s, double lat, double lon) => SkyThing(
        id: s.showpiece.id,
        name: s.showpiece.name,
        kind: switch (s.showpiece.kind) {
          ShowpieceKind.cluster => 'Star cluster',
          ShowpieceKind.nebula => 'Nebula',
          ShowpieceKind.galaxy => 'Galaxy',
          ShowpieceKind.doubleStar => 'Double star',
          ShowpieceKind.milkyWay => 'Milky Way',
        },
        position: (t) => s.showpiece.horizontal(t, lat, lon),
        mag: s.showpiece.mag,
        finder: {'ra': s.showpiece.raDeg, 'dec': s.showpiece.decDeg},
        blurb: s.showpiece.blurb,
        sighting: s.sighting,
        extra: switch (s.showpiece.aid) {
          Aid.eyes => 'Your eyes are enough',
          Aid.binoculars => 'Best in binoculars',
          Aid.telescope => 'Needs a small telescope',
        },
      );

  static String? _brightestName(SkyCatalog catalog, Constellation c) {
    for (final s in catalog.stars) {
      if (s.name == null) continue;
      for (final seg in c.lines) {
        for (final (ra, dec) in seg) {
          if ((s.raDeg - ra).abs() < 0.05 && (s.decDeg - dec).abs() < 0.05) return 'Brightest star: ${s.name}';
        }
      }
    }
    return null;
  }
}

const _planetBlurbs = <Planet, String>{
  Planet.mercury: 'The smallest planet, always close to the Sun. Catch it low in twilight; most people never have.',
  Planet.venus: 'The brightest thing in the sky after the Moon: the "evening star" or "morning star".',
  Planet.mars: 'The red planet: a steady orange-red point. Brightest every two years or so.',
  Planet.jupiter: 'The giant. Binoculars held steady show up to four of its moons in a line.',
  Planet.saturn: 'A steady golden point. Any small telescope shows the rings.',
};

/// Verdict in colour: blue when yes, amber when "maybe", grey when no.
Color verdictColor(Seeability v) => switch (v) {
      Seeability.great || Seeability.good => LookUpColors.blue,
      Seeability.low || Seeability.patchy => LookUpColors.warn,
      _ => LookUpColors.greyDim,
    };

/// A glyph per kind of thing in the sky, greyed when it's not seeable.
EventGlyph thingGlyph(SkyThing x, {double size = 36}) {
  final (IconData? icon, Color color) = x.id == 'moon'
      ? (Icons.nightlight_round, LookUpColors.white)
      : x.id.startsWith('planet:')
          ? (null, LookUpColors.gold)
          : x.id.startsWith('con:')
              ? (Icons.hub_outlined, LookUpColors.blue)
              : switch (x.kind) {
                  'Galaxy' => (Icons.cyclone_rounded, LookUpColors.violet),
                  'Nebula' => (Icons.cloud_rounded, LookUpColors.cyan),
                  'Milky Way' => (Icons.blur_on_rounded, LookUpColors.violet),
                  'Double star' => (Icons.join_full_rounded, LookUpColors.gold),
                  _ => (Icons.grain_rounded, LookUpColors.cyan),
                };
  return EventGlyph(icon: icon, color: color, size: size, dim: !x.seeable && x.id != 'moon');
}

/// The night's weather as one phrase.
String outlookWords(NightOutlook o) => switch (o.shape) {
      'clear' => 'Clear all night',
      'clouds-later' => 'Clear until ${fmtTime(o.bestEnd!)}',
      'clearing' => 'Clearing after ${fmtTime(o.bestStart!)}',
      'cloudy' => 'Cloudy all night',
      'patchy' => o.bestStart != null
          ? 'Best gap ${fmtTime(o.bestStart!)}–${fmtTime(o.bestEnd!)}'
          : 'Patchy cloud tonight',
      _ => 'No forecast yet',
    };
