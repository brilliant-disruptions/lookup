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
    // Catch it: manual long exposures (ios/Runner/LookUpCapture.swift).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LookUpCapture") {
      LookUpCapture.register(with: registrar)
    }
    // Seen near you wake-ups (lib/services/push_service.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LookUpPush") {
      LookUpPush.shared.attach(registrar.messenger())
    }
  }

  // MARK: Push: the relay's silent "check now" nudge

  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    LookUpPush.shared.gotToken(deviceToken)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    LookUpPush.shared.failed(error)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    if userInfo["lookup"] as? String == "aurora-crowd" {
      LookUpPush.shared.wake(completionHandler)
      return
    }
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }
}

// MARK: - Seen near you wake-ups
//
// Dart asks for the push address ("register") and says when it can take a
// wake-up ("ready"). A silent push from the relay becomes a "wake" call that
// runs the usual refresh. iOS allows about 30 s, so it finishes by 25 s.

final class LookUpPush {
  static let shared = LookUpPush()

  private var channel: FlutterMethodChannel?
  private var dartReady = false
  private var waitingForToken: [FlutterResult] = []
  private var waitingForDart: [UUID: (UIBackgroundFetchResult) -> Void] = [:]

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lookup/push", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "register":
        self.waitingForToken.append(result)
        UIApplication.shared.registerForRemoteNotifications()
      case "ready":
        self.dartReady = true
        result(nil)
        let waiting = self.waitingForDart.values
        self.waitingForDart = [:]
        waiting.forEach { self.send($0) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  func gotToken(_ deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    #if DEBUG
    let sandbox = true   // Xcode builds use Apple's development push service
    #else
    let sandbox = false  // TestFlight and the App Store use production
    #endif
    let waiting = waitingForToken
    waitingForToken = []
    waiting.forEach { $0(["token": token, "sandbox": sandbox]) }
  }

  func failed(_ error: Error) {
    let waiting = waitingForToken
    waitingForToken = []
    waiting.forEach { $0(FlutterError(code: "push-unavailable", message: error.localizedDescription, details: nil)) }
  }

  func wake(_ done: @escaping (UIBackgroundFetchResult) -> Void) {
    if dartReady {
      send(done)
    } else {
      // Launched by this push: Dart is still starting and calls "ready".
      let id = UUID()
      waitingForDart[id] = done
      DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
        self?.waitingForDart.removeValue(forKey: id)?(.failed)
      }
    }
  }

  private func send(_ done: @escaping (UIBackgroundFetchResult) -> Void) {
    var finished = false
    let finish: (UIBackgroundFetchResult) -> Void = { r in
      guard !finished else { return }
      finished = true
      done(r)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { finish(.failed) }
    channel?.invokeMethod("wake", arguments: nil) { _ in finish(.newData) }
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
