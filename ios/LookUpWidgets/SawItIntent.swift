// "Saw it" on the Lock Screen and in the Dynamic Island.
//
// A LiveActivityIntent runs in the app's process, so this file must be a
// member of BOTH the Runner and LookUpWidgets targets (docs/mac-checklist.md).
// It never needs the app on screen: it leaves the event's id in the app
// group for the app to log next time it runs
// (lib/services/lock_screen_catches.dart), thanks you, and goes.
import ActivityKit
import AppIntents
import Foundation

@available(iOS 17.0, *)
struct SawItIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Saw it"
  static let description = IntentDescription("Log that you caught it.")

  @Parameter(title: "Event")
  var eventId: String

  init() {}

  init(eventId: String) {
    self.eventId = eventId
  }

  func perform() async throws -> some IntentResult {
    // Same key and shape as lockScreenCatchesKey: a JSON list of event ids.
    let defaults = UserDefaults(suiteName: "group.com.brilliantdisruptions.lookup")
    var ids: [String] = []
    if let raw = defaults?.string(forKey: "saw_it_pending"), let data = raw.data(using: .utf8),
       let list = try? JSONDecoder().decode([String].self, from: data) {
      ids = list
    }
    if !ids.contains(eventId) { ids.append(eventId) }
    if let data = try? JSONEncoder().encode(ids), let raw = String(data: data, encoding: .utf8) {
      defaults?.set(raw, forKey: "saw_it_pending")
    }
    // "Logged. Nice one." for a few minutes, then off the Lock Screen.
    for activity in Activity<LookUpActivityAttributes>.activities where activity.attributes.eventId == eventId {
      let state = LookUpActivityAttributes.ContentState(phase: "logged", direction: activity.content.state.direction)
      await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(180)))
    }
    return .result()
  }
}
