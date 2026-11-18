/// Feeds the home-screen widgets (Android native widget, iOS WidgetKit
/// extension) with the next event. Called after every refresh, in the app
/// and in the background refresh.
library;

import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../ui/format.dart';
import '../ui/kit/event_style.dart';
import 'alert_art.dart';

const appGroupId = 'group.com.brilliantdisruptions.lookup';

class WidgetService {
  const WidgetService();

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(appGroupId);
    } catch (_) {
      // No widget support on this platform/build: fine.
    }
  }

  static bool _crosses(SkyEventType t) => t == SkyEventType.iss || t == SkyEventType.tiangong || t == SkyEventType.starlinkTrain;

  /// Plain strings and numbers so both native widgets stay dumb.
  /// [artPath] is the "where to look" picture for a pass ('' for none).
  /// [upcoming] is the next few (the large widget's list); the first is [e].
  static Map<String, Object?> payloadFor(SkyEvent? e, {String artPath = '', List<SkyEvent>? upcoming}) {
    if (e == null) {
      return {
        'next_title': 'A quiet sky',
        'next_when': 'We\'ll tap you when something\'s up',
        'next_direction': '',
        'next_start_ms': 0,
        'next_kicker': 'Nothing over you yet',
        'next_tint': eventStyle(null).color.toARGB32(),
        'next_art': '',
        'next_end_ms': 0,
        'next_rise': '',
        'next_set': '',
        'next_peak': '',
        'next_rise_word': '',
        'upcoming_json': '[]',
      };
    }
    return {
      'next_title': eventTitle(e),
      'next_when': '${fmtDay(e.start)}, ${fmtTime(e.start)}',
      'next_direction': 'Look ${compassWord(_crosses(e.type) ? e.riseAzimuthDeg : e.peakAzimuthDeg)}, ${elevationWord(e.peakElevationDeg)}',
      'next_start_ms': e.start.millisecondsSinceEpoch,
      'next_kicker': 'Next up · ${fmtDay(e.start)}',
      'next_tint': eventStyle(e.type, details: e.details).color.toARGB32(),
      'next_art': artPath,
      'next_end_ms': e.end.millisecondsSinceEpoch,
      // The arc on the medium widget and in the Dynamic Island, in words.
      // Only for things that cross the sky; '' hides the arc.
      'next_rise': _crosses(e.type) ? compassAbbrev(e.riseAzimuthDeg) : '',
      'next_set': _crosses(e.type) ? compassAbbrev(e.setAzimuthDeg) : '',
      'next_peak': elevationShort(e.peakElevationDeg).toLowerCase(),
      'next_rise_word': compassWord(_crosses(e.type) ? e.riseAzimuthDeg : e.peakAzimuthDeg),
      'upcoming_json': jsonEncode([for (final u in (upcoming ?? [e]).take(3)) _row(u)]),
    };
  }

  /// One line of the large widget, and what the small one moves on to when
  /// a pass is over: the widget picks the first row that hasn't ended.
  static Map<String, Object?> _row(SkyEvent e) => {
        'title': eventTitle(e),
        'where': whereShort(e),
        'time': fmtTime(e.start),
        'day': fmtDay(e.start),
        'start_ms': e.start.millisecondsSinceEpoch,
        'end_ms': e.end.millisecondsSinceEpoch,
        'sky': e.cloudCoverPercent == null ? '' : cloudWord(e.cloudCoverPercent),
        'rise': _crosses(e.type) ? compassAbbrev(e.riseAzimuthDeg) : '',
        'set': _crosses(e.type) ? compassAbbrev(e.setAzimuthDeg) : '',
        'peak': elevationShort(e.peakElevationDeg).toLowerCase(),
        'rise_word': compassWord(_crosses(e.type) ? e.riseAzimuthDeg : e.peakAzimuthDeg),
      };

  /// "from the west-southwest, high" for a pass; "south, high" for the rest.
  static String whereShort(SkyEvent e) => _crosses(e.type)
      ? 'from the ${compassWord(e.riseAzimuthDeg)}, ${elevationShort(e.peakElevationDeg).toLowerCase()}'
      : '${compassWord(e.peakAzimuthDeg)}, ${elevationShort(e.peakElevationDeg).toLowerCase()}';

  /// The next pass's picture, written where the native widget can read it.
  static Future<String> _art(SkyEvent? e) async {
    if (e == null || !AlertArt.types.contains(e.type)) return '';
    try {
      final bytes = await AlertArt.png(e, startLabel: fmtTime(e.start), titled: false).timeout(const Duration(seconds: 3));
      if (bytes == null) return '';
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/alert_art');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/widget.png');
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return '';
    }
  }

  static const _androidWidget = 'com.brilliantdisruptions.lookup.NextEventWidget';

  /// Whether the launcher can add the widget from inside the app (Android 8+
  /// on launchers that support pinning; never on iOS).
  static Future<bool> canPin() async {
    if (!Platform.isAndroid) return false;
    try {
      return await HomeWidget.isRequestPinWidgetSupported() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Ask the launcher to add the widget; it shows its own confirmation.
  static Future<void> pin() async {
    try {
      await HomeWidget.requestPinWidget(qualifiedAndroidName: _androidWidget, androidName: 'NextEventWidget');
    } catch (_) {}
  }

  Future<void> update(List<SkyEvent> events) async {
    final coming = events.where((e) => e.type.pushes && e.details['past'] != true).take(3).toList();
    final next = coming.firstOrNull;
    try {
      for (final entry in payloadFor(next, artPath: await _art(next), upcoming: coming).entries) {
        await HomeWidget.saveWidgetData(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(androidName: 'NextEventWidget', iOSName: 'LookUpWidget');
    } catch (_) {
      // Widgets are optional; never fail a refresh over them.
    }
  }
}
