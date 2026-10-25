/// Feeds the home-screen widgets (Android native widget, iOS WidgetKit
/// extension) with the next event. Called after every refresh.
library;

import 'package:home_widget/home_widget.dart';

import '../domain/models/sky_event.dart';
import '../domain/sky/direction.dart';
import '../ui/format.dart';

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

  /// Plain strings so both native widgets stay dumb.
  static Map<String, Object?> payloadFor(SkyEvent? e) {
    if (e == null) {
      return {'next_title': 'A quiet sky', 'next_when': 'We\'ll tap you when something\'s up', 'next_direction': '', 'next_start_ms': 0};
    }
    return {
      'next_title': eventTitle(e),
      'next_when': '${fmtDay(e.start)}, ${fmtTime(e.start)}',
      'next_direction': 'Look ${compassWord(e.type == SkyEventType.iss || e.type == SkyEventType.tiangong || e.type == SkyEventType.starlinkTrain ? e.riseAzimuthDeg : e.peakAzimuthDeg)}, ${elevationWord(e.peakElevationDeg)}',
      'next_start_ms': e.start.millisecondsSinceEpoch,
    };
  }

  Future<void> update(List<SkyEvent> events) async {
    final next = events.where((e) => e.type != SkyEventType.auroraOutlook && e.details['past'] != true).firstOrNull;
    try {
      for (final entry in payloadFor(next).entries) {
        await HomeWidget.saveWidgetData(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(androidName: 'NextEventWidget', iOSName: 'LookUpWidget');
    } catch (_) {
      // Widgets are optional; never fail a refresh over them.
    }
  }
}
