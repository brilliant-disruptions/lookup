import Flutter
import UIKit
import workmanager_apple
// Notification actions ("Saw it!", "Remind me") run Dart in a background
// isolate; it needs the plugins registered too.
import flutter_local_notifications
#if canImport(ActivityKit)
import ActivityKit
#endif

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
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LookUpLiveActivity") {
      LookUpLiveActivityChannel.register(messenger: registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LookUpAmbientLight") {
      FlutterEventChannel(name: "lookup/ambient_light", binaryMessenger: registrar.messenger())
        .setStreamHandler(AmbientLightHandler())
    }
  }
}

// MARK: - Live Activity (Lock Screen + Dynamic Island countdown)
//
// The attributes type must match ios/LookUpWidgets/LookUpActivityAttributes.swift
// in the widget extension byte-for-byte (same name, same fields).

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct LookUpActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var phase: String       // "countdown" | "live" | "over"
    var direction: String   // "Look west-southwest, high in the sky"
  }
  var title: String
  var start: Date
  var end: Date
}
#endif

enum LookUpLiveActivityChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lookup/live_activity", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      #if canImport(ActivityKit)
      if #available(iOS 16.2, *) {
        handle(call, result: result)
        return
      }
      #endif
      result(false)
    }
  }

  #if canImport(ActivityKit)
  @available(iOS 16.2, *)
  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "supported":
      result(ActivityAuthorizationInfo().areActivitiesEnabled)
    case "start":
      guard ActivityAuthorizationInfo().areActivitiesEnabled,
            let title = args["title"] as? String,
            let startMs = args["startMs"] as? Double,
            let endMs = args["endMs"] as? Double
      else { result(false); return }
      // One LookUp activity at a time.
      for activity in Activity<LookUpActivityAttributes>.activities {
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
      }
      let attributes = LookUpActivityAttributes(
        title: title,
        start: Date(timeIntervalSince1970: startMs / 1000),
        end: Date(timeIntervalSince1970: endMs / 1000)
      )
      let state = LookUpActivityAttributes.ContentState(
        phase: "countdown",
        direction: args["direction"] as? String ?? ""
      )
      do {
        let activity = try Activity<LookUpActivityAttributes>.request(
          attributes: attributes,
          content: ActivityContent(state: state, staleDate: attributes.end),
          pushType: nil
        )
        result(activity.id)
      } catch {
        result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
      }
    case "update":
      let state = LookUpActivityAttributes.ContentState(
        phase: args["phase"] as? String ?? "live",
        direction: args["direction"] as? String ?? ""
      )
      for activity in Activity<LookUpActivityAttributes>.activities {
        Task { await activity.update(ActivityContent(state: state, staleDate: activity.attributes.end)) }
      }
      result(true)
    case "end":
      for activity in Activity<LookUpActivityAttributes>.activities {
        Task { await activity.end(nil, dismissalPolicy: .default) }
      }
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  #endif
}

// MARK: - Ambient light for night vision (lib/services/ambient_light.dart)
//
// iOS has no public light-sensor API. Screen brightness follows ambient
// light under Auto-Brightness, so it stands in: sent once on listen and
// again whenever it changes.

final class AmbientLightHandler: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    let send = { events(["screen": Double(UIScreen.main.brightness)]) }
    send()
    observer = NotificationCenter.default.addObserver(
      forName: UIScreen.brightnessDidChangeNotification, object: nil, queue: .main
    ) { _ in send() }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    return nil
  }
}
