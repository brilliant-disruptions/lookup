import ActivityKit
import Foundation

// Must match the struct in ios/Runner/AppDelegate.swift exactly.
struct LookUpActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var phase: String
    var direction: String
  }
  var title: String
  var start: Date
  var end: Date
}
