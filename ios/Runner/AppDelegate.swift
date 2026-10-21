import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Background refresh (BGAppRefresh). The identifier must match
    // `backgroundTaskId` in lib/services/background.dart and the
    // BGTaskSchedulerPermittedIdentifiers entry in Info.plist.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.brilliantdisruptions.lookup.refresh",
      earliestBeginInSeconds: NSNumber(value: 6 * 60 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
  }
}
