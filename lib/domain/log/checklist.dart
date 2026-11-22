/// The Log's list to work through: every kind of thing LookUp can show you,
/// from the Moon to a solar eclipse, each ticked off by the first catch of
/// its kind. The easy ones come first.
library;

import '../models/sky_event.dart';
import 'sighting.dart';

class ChecklistItem {
  const ChecklistItem({required this.key, required this.name, this.type, this.skyId, this.catches = const []});

  /// Stable id ("moon", "planet:venus", "iss").
  final String key;
  final String name;

  /// For its glyph: an event type, or a sky id (`SkyId`) for things found on the map.
  final SkyEventType? type;
  final String? skyId;

  /// Its catches, newest first.
  final List<Sighting> catches;

  bool get seen => catches.isNotEmpty;
  int get count => catches.length;
  Sighting? get latest => catches.firstOrNull;
}

/// What a catch from the sky map is of: "moon", "planet:venus", "con:Ori", a showpiece's id.
String? _object(Sighting s) => s.eventId.startsWith('obj:') ? s.eventId.substring(4) : null;

bool _isShowpiece(Sighting s) {
  final o = _object(s);
  return o != null && !o.startsWith('moon') && !o.startsWith('planet:') && !o.startsWith('con:') && !o.startsWith('star:');
}

typedef _Spec = ({String key, String name, SkyEventType? type, String? skyId, bool Function(Sighting) match});

_Spec _event(String key, String name, SkyEventType type, [SkyEventType? also]) =>
    (key: key, name: name, type: type, skyId: null, match: (s) => s.inferredType == type || (also != null && s.inferredType == also));

_Spec _planet(String id, String name) =>
    (key: 'planet:$id', name: name, type: null, skyId: 'planet:$id', match: (s) => _object(s) == 'planet:$id');

final List<_Spec> _specs = [
  (key: 'moon', name: 'The Moon', type: null, skyId: 'moon', match: (s) => _object(s)?.startsWith('moon') ?? false),
  _event('iss', 'The space station', SkyEventType.iss),
  _planet('venus', 'Venus'),
  _planet('jupiter', 'Jupiter'),
  _planet('saturn', 'Saturn'),
  _planet('mars', 'Mars'),
  _planet('mercury', 'Mercury'),
  (key: 'constellation', name: 'A constellation', type: null, skyId: 'con:', match: (s) => _object(s)?.startsWith('con:') ?? false),
  (key: 'showpiece', name: 'A showpiece', type: null, skyId: 'showpiece', match: _isShowpiece),
  _event('fullMoonRise', 'A full Moon rising', SkyEventType.fullMoonRise),
  _event('moonPhase', 'A half Moon', SkyEventType.moonPhase),
  _event('planetPairing', 'Planets side by side', SkyEventType.planetPairing),
  _event('meteorShower', 'A meteor shower', SkyEventType.meteorShower),
  _event('satellitePass', 'A satellite', SkyEventType.satellitePass),
  _event('tiangong', 'Tiangong', SkyEventType.tiangong),
  _event('starlinkTrain', 'A Starlink train', SkyEventType.starlinkTrain),
  _event('aurora', 'The aurora', SkyEventType.auroraNow, SkyEventType.auroraOutlook),
  _event('lunarEclipse', 'A lunar eclipse', SkyEventType.lunarEclipse),
  _event('rocketLaunch', 'A rocket launch', SkyEventType.rocketLaunch),
  _event('issTransit', 'The station crossing the Sun or Moon', SkyEventType.issTransit),
  _event('occultation', 'The Moon covering a star', SkyEventType.occultation, SkyEventType.occultationNear),
  _event('comet', 'A comet', SkyEventType.comet),
  _event('nova', 'A new star', SkyEventType.nova),
  _event('solarEclipse', 'A solar eclipse', SkyEventType.solarEclipse),
];

/// Every kind of sight, with the catches of each from [seen] (newest first, as the Log keeps them).
List<ChecklistItem> skyChecklist(Iterable<Sighting> seen) {
  final caught = [for (final s in seen) if (s.seen) s];
  return [
    for (final spec in _specs)
      ChecklistItem(
        key: spec.key,
        name: spec.name,
        type: spec.type,
        skyId: spec.skyId,
        catches: [for (final s in caught) if (spec.match(s)) s],
      ),
  ];
}
