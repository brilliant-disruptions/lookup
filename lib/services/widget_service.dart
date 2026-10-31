/// Feeds the home-screen widgets (Android native widget, iOS WidgetKit
/// extension) with the next event. Called after every refresh, in the app
/// and in the background refresh.
library;

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
  static Map<String, Object?> payloadFor(SkyEvent? e, {String artPath = ''}) {
    if (e == null) {
      return {
        'next_title': 'A quiet sky',
        'next_when': 'We\'ll tap you when something\'s up',
        'next_direction': '',
        'next_start_ms': 0,
        'next_kicker': 'Nothing over you yet',
        'next_tint': eventStyle(null).color.toARGB32(),
        'next_art': '',
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
    };
  }

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

  Future<void> update(List<SkyEvent> events) async {
    final next = events.where((e) => e.type.pushes && e.details['past'] != true).firstOrNull;
    try {
      for (final entry in payloadFor(next, artPath: await _art(next)).entries) {
        await HomeWidget.saveWidgetData(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(androidName: 'NextEventWidget', iOSName: 'LookUpWidget');
    } catch (_) {
      // Widgets are optional; never fail a refresh over them.
    }
  }
}
