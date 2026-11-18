import ActivityKit
import Foundation

// Must match the struct in ios/Runner/AppDelegate.swift exactly.
struct LookUpActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var phase: String       // "countdown" | "live" | "over"
    var direction: String   // "Look west-southwest, high in the sky"
  }
  var title: String
  var start: Date
  var end: Date
  // The little arc, in words: "WSW", "high", "E", "west-southwest".
  var rise: String
  var peak: String
  var set: String
  var riseWord: String
}
