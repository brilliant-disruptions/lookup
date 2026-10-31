import 'package:flutter_test/flutter_test.dart';
import 'package:lookup/domain/finder/look_up_now.dart';
import 'package:lookup/domain/models/sky_event.dart';

final _start = DateTime.utc(2026, 11, 6, 3, 5);

SkyEvent ev(SkyEventType type, {Map<String, Object?> details = const {}}) => SkyEvent(
  id: '${type.name}:1',
  type: type,
  start: _start,
  peak: _start.add(const Duration(minutes: 2)),
  end: _start.add(const Duration(minutes: 4)),
  peakElevationDeg: 60,
  riseAzimuthDeg: 247,
  peakAzimuthDeg: 180,
  setAzimuthDeg: 95,
  details: details,
);

void main() {
  test('due only in the last two minutes before a pass appears', () {
    final e = ev(SkyEventType.iss);
    expect(LookUpNow.due(e, _start.subtract(const Duration(minutes: 3))), isFalse);
    expect(LookUpNow.due(e, _start.subtract(const Duration(minutes: 2))), isTrue);
    expect(LookUpNow.due(e, _start.subtract(const Duration(seconds: 1))), isTrue);
    expect(LookUpNow.due(e, _start), isFalse); // it's up: the finder's job now
  });

  test('never for things that don\'t cross the sky, past records or the preview', () {
    final at = _start.subtract(const Duration(minutes: 1));
    expect(LookUpNow.due(ev(SkyEventType.starlinkTrain), at), isTrue);
    expect(LookUpNow.due(ev(SkyEventType.meteorShower), at), isFalse);
    expect(LookUpNow.due(ev(SkyEventType.issTransit), at), isFalse);
    expect(LookUpNow.due(ev(SkyEventType.iss, details: {'past': true}), at), isFalse);
    expect(LookUpNow.due(ev(SkyEventType.iss, details: {'demo': true}), at), isFalse);
  });

  test('clock rounds up and never goes negative', () {
    expect(LookUpNow.clock(const Duration(minutes: 1, seconds: 47)), '1:47');
    expect(LookUpNow.clock(const Duration(milliseconds: 4200)), '0:05');
    expect(LookUpNow.clock(const Duration(seconds: -3)), '0:00');
  });

  test('turn words', () {
    expect(LookUpNow.turn(0), 'You\'re facing it');
    expect(LookUpNow.turn(-12), 'You\'re facing it');
    expect(LookUpNow.turn(30), 'A little to your right');
    expect(LookUpNow.turn(-40), 'A little to your left');
    expect(LookUpNow.turn(90), 'Turn right');
    expect(LookUpNow.turn(-100), 'Turn left');
    expect(LookUpNow.turn(170), 'Turn around');
    expect(LookUpNow.turn(-180), 'Turn around');
  });
}
