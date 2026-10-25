// Widget extension for LookUp: a home-screen "next event" widget and the
// Live Activity (Lock Screen + Dynamic Island) countdown.
// Setup: docs/ios-widgets.md.
import ActivityKit
import SwiftUI
import WidgetKit

private let appGroup = "group.com.brilliantdisruptions.lookup"
private let blue = Color(red: 0.235, green: 0.616, blue: 1.0)
private let grey = Color(red: 0.655, green: 0.675, blue: 0.702)

// MARK: Home-screen widget (data written by home_widget from Flutter)

struct NextEntry: TimelineEntry {
  let date: Date
  let title: String
  let whenText: String
  let direction: String
  let start: Date?
}

struct NextProvider: TimelineProvider {
  func placeholder(in context: Context) -> NextEntry {
    NextEntry(date: .now, title: "ISS flyover", whenText: "Tonight, 6:42 PM", direction: "Look west-southwest", start: .now.addingTimeInterval(3600))
  }

  func getSnapshot(in context: Context, completion: @escaping (NextEntry) -> Void) {
    completion(read())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NextEntry>) -> Void) {
    let entry = read()
    // The app pushes fresh data on every refresh; this is just a safety net.
    completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
  }

  private func read() -> NextEntry {
    let d = UserDefaults(suiteName: appGroup)
    let ms = d?.double(forKey: "next_start_ms") ?? 0
    return NextEntry(
      date: .now,
      title: d?.string(forKey: "next_title") ?? "A quiet sky",
      whenText: d?.string(forKey: "next_when") ?? "We'll tap you when something's up",
      direction: d?.string(forKey: "next_direction") ?? "",
      start: ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
    )
  }
}

struct NextWidgetView: View {
  let entry: NextEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("LOOKUP").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(blue)
      Text(entry.title).font(.system(size: 19, design: .serif)).foregroundStyle(.white).lineLimit(1)
      if let start = entry.start, start > .now, start.timeIntervalSinceNow < 86_400 {
        Text(start, style: .timer).font(.system(size: 24, design: .serif).italic()).foregroundStyle(blue)
      }
      Text(entry.whenText).font(.caption).foregroundStyle(grey).lineLimit(1)
      Text(entry.direction).font(.caption2).foregroundStyle(grey).lineLimit(2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .widgetBackground(Color(red: 0.055, green: 0.059, blue: 0.067))
  }
}

struct NextEventWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "LookUpWidget", provider: NextProvider()) { NextWidgetView(entry: $0) }
      .configurationDisplayName("Next up")
      .description("The next thing worth stepping outside for.")
      .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

private extension View {
  /// iOS 17 requires containerBackground; iOS 16 uses a plain background.
  @ViewBuilder
  func widgetBackground(_ color: Color) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { color }
    } else {
      padding().background(color)
    }
  }
}

// MARK: Live Activity

struct LookUpLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LookUpActivityAttributes.self) { context in
      // Lock Screen / banner
      HStack(alignment: .center, spacing: 14) {
        VStack(alignment: .leading, spacing: 2) {
          Text("LOOKUP").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(blue)
          Text(context.attributes.title).font(.system(size: 20, design: .serif)).foregroundStyle(.white)
          Text(context.state.direction).font(.caption).foregroundStyle(grey).lineLimit(2)
        }
        Spacer()
        countdown(context)
          .font(.system(size: 28, design: .serif).italic())
          .foregroundStyle(blue)
          .monospacedDigit()
          .frame(maxWidth: 110, alignment: .trailing)
      }
      .padding(16)
      .activityBackgroundTint(Color.black)
      .activitySystemActionForegroundColor(blue)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.title).font(.system(size: 16, design: .serif)).foregroundStyle(.white)
        }
        DynamicIslandExpandedRegion(.trailing) {
          countdown(context).font(.system(size: 20, design: .serif).italic()).foregroundStyle(blue).monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.direction).font(.caption).foregroundStyle(grey)
        }
      } compactLeading: {
        Image(systemName: "sparkle").foregroundStyle(blue)
      } compactTrailing: {
        countdown(context).monospacedDigit().foregroundStyle(blue).frame(maxWidth: 52)
      } minimal: {
        Image(systemName: "sparkle").foregroundStyle(blue)
      }
    }
  }

  @ViewBuilder
  private func countdown(_ context: ActivityViewContext<LookUpActivityAttributes>) -> some View {
    if context.state.phase == "countdown" {
      Text(timerInterval: Date.now...context.attributes.start, countsDown: true)
    } else if context.state.phase == "live" {
      Text("Now")
    } else {
      Text("Done")
    }
  }
}

@main
struct LookUpWidgetsBundle: WidgetBundle {
  var body: some Widget {
    NextEventWidget()
    LookUpLiveActivity()
  }
}
