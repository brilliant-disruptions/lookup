// "Hey Siri, when's the next pass in LookUp?" — answered from what the app
// last worked out (lib/services/shortcut_summary.dart writes the
// `siri_upcoming` key). Runs inside the app, no extension needed.
//
// Not in the Runner target yet: add it in Xcode (see docs/mac-checklist.md)
// so it gets compiled and checked on a Mac first.

import AppIntents
import Foundation

@available(iOS 16.0, *)
struct NextSkyEventIntent: AppIntent {
  static var title: LocalizedStringResource = "Next thing in the sky"
  static var description = IntentDescription(
    "When the space station, a Starlink train or the next sky event is visible from where you are.")

  func perform() async throws -> some IntentResult & ProvidesDialog {
    return .result(dialog: IntentDialog(stringLiteral: NextSkyEventIntent.answer(now: Date())))
  }

  static func answer(now: Date) -> String {
    guard
      let raw = UserDefaults.standard.string(forKey: "siri_upcoming"),
      let data = raw.data(using: .utf8),
      let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else {
      return "Open LookUp once so it can work out your sky."
    }
    let nowMs = now.timeIntervalSince1970 * 1000
    for item in items {
      guard let text = item["text"] as? String, let end = item["endMs"] as? Double else { continue }
      if end > nowMs { return text }
    }
    return "Nothing worth stepping out for right now. LookUp will tap you when there is."
  }
}

@available(iOS 16.0, *)
struct LookUpShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: NextSkyEventIntent(),
      phrases: [
        "When's the next pass in \(.applicationName)",
        "What's in the sky in \(.applicationName)",
        "Ask \(.applicationName) what's up tonight",
      ],
      shortTitle: "Next in the sky",
      systemImageName: "sparkles"
    )
  }
}
