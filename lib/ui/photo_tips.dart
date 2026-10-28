import 'package:flutter/material.dart';

import '../domain/models/sky_event.dart';
import 'kit/kit.dart';
import 'theme.dart';

/// Short, practical camera advice per kind of event: phone first, then a
/// real camera.
List<(String, String)> photoTips(SkyEventType t) => switch (t) {
      SkyEventType.iss || SkyEventType.tiangong || SkyEventType.satellitePass || SkyEventType.starlinkTrain => const [
          ('Phone', 'Prop it against something steady and use Night mode on its longest setting. Start just before it rises: you\'ll get a bright streak across the stars.'),
          ('Camera', 'Tripod, widest lens, manual focus on a bright star. ISO 800, f/2.8–f/4, 15–30 s exposures back to back; stack them later for one long streak.'),
          ('Framing', 'Put a tree, roofline or friend in the bottom third. The streak means more with something on the ground.'),
        ],
      SkyEventType.issTransit => const [
          ('Safety first', 'Sun transits: a certified solar filter on the lens, always. Never look at the Sun through a camera, binoculars or with your eyes.'),
          ('Gear', 'The longest lens you have (600 mm+ helps) on a tripod, focused on the disk\'s edge. Fastest shutter that still exposes the disk: 1/2000 s or quicker.'),
          ('Timing', 'Start a burst 3 seconds before the time shown and hold it for 6. The crossing itself is under a second.'),
        ],
      SkyEventType.auroraNow || SkyEventType.auroraOutlook => const [
          ('Phone', 'Night mode, steady on a wall or tripod, pointed north. Phones often see colour your eyes can\'t.'),
          ('Camera', 'Wide lens, f/2.8, ISO 1600–3200, 5–15 s. Shorter when it\'s dancing so the curtains stay sharp.'),
          ('Focus', 'Manual focus on a bright star, then tape the ring so it can\'t drift.'),
        ],
      SkyEventType.milkyWayNight => const [
          ('Phone', 'Night mode on its longest setting, phone propped or on a mini tripod, pointed at the brightest band.'),
          ('Camera', 'Widest, fastest lens. f/2.8 or wider, ISO 3200, 15–20 s (shorter on longer lenses so stars stay points).'),
          ('Focus', 'Manual focus on a bright star at full zoom on the screen, then leave it.'),
        ],
      SkyEventType.meteorShower => const [
          ('Patience', 'Meteors are luck. Set a camera on a tripod shooting continuously for an hour and pick the frames that caught one.'),
          ('Settings', 'Wide lens, f/2.8, ISO 1600–3200, 20 s exposures, interval shooting on.'),
          ('Where', 'Aim about 45° away from the radiant, not right at it: trails there are longer.'),
        ],
      SkyEventType.lunarEclipse => const [
          ('Phone', 'Zoom in all the way, tap the Moon and slide exposure down until the surface shows detail.'),
          ('Camera', 'A long lens on a tripod. The eclipsed Moon is dim: ISO 800–1600, 1–2 s at totality; much faster before and after.'),
          ('Sequence', 'Shoot every 5 minutes from start to end and line them up for a classic eclipse sequence.'),
        ],
      SkyEventType.planetPairing || SkyEventType.planetHighlight || SkyEventType.skyObject || SkyEventType.favourite => const [
          ('Phone', 'Use 2–3× zoom and frame some landscape; the pair reads best low over a skyline at dusk.'),
          ('Camera', 'Tripod, 50–200 mm, ISO 400, 1–2 s. Shoot in twilight, not full dark, for a deep-blue sky.'),
        ],
      SkyEventType.rocketLaunch => const [
          ('Camera', 'Tripod, wide lens, ISO 100–200, f/8, 30 s+ exposures from liftoff for the arc of the climb.'),
          ('Twilight', 'If the plume lights up after sunset, switch to 1–2 s shots: it changes fast.'),
        ],
    };

Future<void> showPhotoTips(BuildContext context, SkyEventType t) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Photo tips', style: display(26, weight: FontWeight.w700)),
            const SizedBox(height: 16),
            for (final (title, body) in photoTips(t))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Kicker(title, color: LookUpColors.blue),
                  const SizedBox(height: 4),
                  Text(body, style: const TextStyle(height: 1.45)),
                ]),
              ),
          ]),
        ),
      ),
    );
