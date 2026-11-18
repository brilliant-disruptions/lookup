// Widget extension for LookUp: the home-screen and Lock Screen widgets, and
// the Live Activity (Lock Screen + Dynamic Island) countdown.
// Setup: docs/ios-widgets.md. Design: Pip is the light, the only flourish;
// directions stay in words, never degrees.
import ActivityKit
import SwiftUI
import WidgetKit

private let appGroup = "group.com.brilliantdisruptions.lookup"

// Pip's colours, as in lib/ui/kit/firefly_mark.dart.
private let glow = Color(red: 0.769, green: 0.961, blue: 0.369)   // #C4F55E
private let core = Color(red: 0.957, green: 1.0, blue: 0.851)     // #F4FFD9
private let ink = Color(red: 0.957, green: 0.965, blue: 0.980)    // #F4F6FA
private let grey = Color(red: 0.627, green: 0.659, blue: 0.722)   // #A0A8B8
private let night = LinearGradient(
  colors: [Color(red: 0.082, green: 0.125, blue: 0.259), Color(red: 0.043, green: 0.067, blue: 0.141), Color(red: 0.027, green: 0.043, blue: 0.094)],
  startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: Pip

/// Pip, the light: a soft glow, a brighter ring and a pale core, drawn like
/// paintFirefly. [size] is the core; the glow spills past it.
struct PipLight: View {
  var size: CGFloat = 12
  var dim = false

  var body: some View {
    ZStack {
      Circle().fill(glow.opacity(dim ? 0.10 : 0.28)).frame(width: size * 4, height: size * 4).blur(radius: size * 1.2)
      Circle().fill(glow.opacity(dim ? 0.30 : 0.75)).frame(width: size * 1.6, height: size * 1.6).blur(radius: size * 0.35)
      Circle().fill(core).frame(width: size, height: size)
    }
    .frame(width: size, height: size)
    .opacity(dim ? 0.55 : 1)
  }
}

/// Pip inside its lock ring: found it, it's up.
struct PipFound: View {
  var size: CGFloat = 12

  var body: some View {
    ZStack {
      Circle().stroke(glow.opacity(0.85), lineWidth: max(1, size / 8)).frame(width: size * 2.4, height: size * 2.4)
      PipLight(size: size)
    }
    .frame(width: size * 2.4, height: size * 2.4)
  }
}

// MARK: The pass, drawn

/// A pass as a little arc over the horizon, labelled in words: where it
/// rises, how high, where it sets. [pip] places Pip along it (0 = rising);
/// nil leaves Pip off, as while it's up (the bar below shows how far along).
struct PassArc: View {
  let rise: String
  let peak: String
  let set: String
  var pip: Double? = 0

  var body: some View {
    GeometryReader { g in
      let w = g.size.width, h = g.size.height
      let a = CGPoint(x: 8, y: h - 14), b = CGPoint(x: w - 8, y: h - 14)
      let c = CGPoint(x: w / 2, y: -h * 0.35)
      ZStack {
        Path { p in
          p.move(to: a)
          p.addQuadCurve(to: b, control: c)
        }
        .stroke(grey.opacity(0.5), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [2, 5]))
        Path { p in
          p.move(to: CGPoint(x: 0, y: h - 12))
          p.addLine(to: CGPoint(x: w, y: h - 12))
        }
        .stroke(grey.opacity(0.28), lineWidth: 1)
        label(rise).position(x: a.x + 10, y: h - 3)
        label(peak).position(x: w / 2, y: max(6, h * 0.325 - 16))
        label(set).position(x: b.x - 6, y: h - 3)
        if let t = pip {
          PipLight(size: 9).position(point(t, a, c, b))
        }
      }
    }
  }

  private func label(_ s: String) -> some View {
    Text(s).font(.system(size: 10, weight: .semibold)).foregroundStyle(grey).lineLimit(1)
  }

  private func point(_ t: Double, _ a: CGPoint, _ c: CGPoint, _ b: CGPoint) -> CGPoint {
    let u = 1 - t
    return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
  }
}

/// "2h 14m", "14m", "now".
private func shortUntil(_ start: Date, from now: Date) -> String {
  let s = Int(start.timeIntervalSince(now))
  if s <= 0 { return "now" }
  let h = s / 3600, m = (s % 3600 + 59) / 60
  if h == 0 { return "\(m)m" }
  return m == 0 ? "\(h)h" : "\(h)h \(m)m"
}

private let timeFormat: DateFormatter = {
  let f = DateFormatter()
  f.timeStyle = .short
  f.dateStyle = .none
  return f
}()

// MARK: Home-screen and Lock Screen widgets (data written by home_widget)

/// One sight, as lib/services/widget_service.dart writes it.
struct Sight: Codable, Hashable {
  var title: String
  var where_: String
  var time: String
  var day: String
  var start_ms: Double
  var end_ms: Double
  var sky: String
  var rise: String
  var set: String
  var peak: String
  var rise_word: String

  enum CodingKeys: String, CodingKey {
    case title, time, day, start_ms, end_ms, sky, rise, set, peak, rise_word
    case where_ = "where"
  }

  var start: Date { Date(timeIntervalSince1970: start_ms / 1000) }
  var end: Date { Date(timeIntervalSince1970: end_ms / 1000) }
  var crosses: Bool { !rise.isEmpty && !set.isEmpty }
  /// "ISS" from "ISS flyover", for the tiny widgets.
  var short: String { title.split(separator: " ").first.map(String.init) ?? title }
}

struct NextEntry: TimelineEntry {
  let date: Date
  let sights: [Sight]

  /// The first sight that hasn't ended by this entry's time.
  var current: Sight? { sights.first { $0.end > date } }
  var isUp: Bool { current.map { $0.start <= date } ?? false }
  var upcoming: [Sight] { sights.filter { $0.end > date } }
}

struct NextProvider: TimelineProvider {
  static let sample: [Sight] = {
    let now = Date.now
    func s(_ title: String, _ w: String, _ inMin: Double, _ sky: String, _ rise: String, _ set: String, _ peak: String, _ word: String) -> Sight {
      let start = now.addingTimeInterval(inMin * 60)
      return Sight(title: title, where_: w, time: timeFormat.string(from: start), day: "Tonight",
                   start_ms: start.timeIntervalSince1970 * 1000, end_ms: (start.timeIntervalSince1970 + 360) * 1000,
                   sky: sky, rise: rise, set: set, peak: peak, rise_word: word)
    }
    return [
      s("ISS flyover", "from the west-southwest, high", 134, "clear", "WSW", "E", "high", "west-southwest"),
      s("Saturn at its best", "south, high", 200, "clear", "", "", "high", "south"),
      s("Starlink train", "from the southwest, low", 1400, "some cloud", "SW", "ENE", "low", "southwest"),
    ]
  }()

  func placeholder(in context: Context) -> NextEntry { NextEntry(date: .now, sights: Self.sample) }

  func getSnapshot(in context: Context, completion: @escaping (NextEntry) -> Void) {
    let sights = read()
    completion(NextEntry(date: .now, sights: context.isPreview && sights.isEmpty ? Self.sample : sights))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NextEntry>) -> Void) {
    let sights = read()
    let now = Date.now
    // Every few minutes for the countdown, and exactly at each rise and set,
    // so "It's up" shows on time without the app running.
    var times: Set<Date> = [now]
    for i in 1...36 { times.insert(now.addingTimeInterval(Double(i) * 300)) }
    for s in sights where s.end > now {
      if s.start > now { times.insert(s.start) }
      times.insert(s.end)
    }
    let entries = times.sorted().map { NextEntry(date: $0, sights: sights) }
    // The app pushes fresh data on every refresh; this is just a safety net.
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600))))
  }

  private func read() -> [Sight] {
    let d = UserDefaults(suiteName: appGroup)
    if let json = d?.string(forKey: "upcoming_json"), let data = json.data(using: .utf8),
       let rows = try? JSONDecoder().decode([Sight].self, from: data) {
      return rows
    }
    // Written by an older app: just the next one.
    let ms = d?.double(forKey: "next_start_ms") ?? 0
    guard ms > 0, let title = d?.string(forKey: "next_title") else { return [] }
    return [Sight(title: title, where_: d?.string(forKey: "next_direction") ?? "", time: d?.string(forKey: "next_when") ?? "",
                  day: "", start_ms: ms, end_ms: ms + 600_000, sky: "", rise: "", set: "", peak: "", rise_word: "")]
  }
}

struct NextWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: NextEntry

  var body: some View {
    switch family {
    case .accessoryInline, .accessoryCircular, .accessoryRectangular:
      content.accessoryBackground()
    default:
      content.widgetBackground()
    }
  }

  @ViewBuilder
  private var content: some View {
    switch family {
    case .accessoryInline: inline
    case .accessoryCircular: circular
    case .accessoryRectangular: rectangular
    case .systemLarge: large
    case .systemMedium: medium
    default: small
    }
  }

  // Small: next up, while it's up, or a quiet sky.
  @ViewBuilder
  private var small: some View {
    if let s = entry.current {
      if entry.isUp {
        VStack(alignment: .leading, spacing: 0) {
          PipFound(size: 11)
          Text("It's up").font(.system(size: 26, weight: .heavy)).foregroundStyle(glow).padding(.top, 10)
          Spacer(minLength: 4)
          Text("\(s.short) · look \(s.rise_word), climbing \(s.peak)")
            .font(.system(size: 12.5)).foregroundStyle(ink.opacity(0.88)).lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else {
        countdownColumn(s)
      }
    } else {
      VStack(alignment: .leading, spacing: 0) {
        PipLight(size: 10, dim: true)
        Text("A quiet sky").font(.system(size: 18, weight: .bold)).foregroundStyle(ink).padding(.top, 14)
        Spacer(minLength: 4)
        Text("Nothing bright for a few days. I'll tap you when that changes.")
          .font(.system(size: 12.5)).foregroundStyle(grey).lineLimit(4)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private func countdownColumn(_ s: Sight) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      PipLight(size: 11)
      Text(s.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink).lineLimit(1).padding(.top, 14)
      Text(shortUntil(s.start, from: entry.date))
        .font(.system(size: 30, weight: .heavy)).tracking(-1).foregroundStyle(glow).lineLimit(1).minimumScaleFactor(0.7)
      Spacer(minLength: 4)
      Text(s.time).font(.system(size: 12)).foregroundStyle(grey)
      Text(s.rise_word).font(.system(size: 12)).foregroundStyle(grey).lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // Medium: the countdown, and the pass drawn.
  @ViewBuilder
  private var medium: some View {
    if let s = entry.current, !entry.isUp, s.crosses {
      HStack(spacing: 12) {
        countdownColumn(s).frame(width: 130)
        PassArc(rise: s.rise, peak: s.peak, set: s.set).padding(.top, 18)
      }
    } else {
      small
    }
  }

  // Large: what's coming, then where to look for the first.
  private var large: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text("Coming up").font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
        Spacer()
        if let s = entry.current, !s.sky.isEmpty {
          Text(s.sky.prefix(1).uppercased() + s.sky.dropFirst())
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(glow)
        }
      }
      if entry.upcoming.isEmpty {
        Spacer()
        Text("A quiet sky. I'll tap you when something's up.").font(.system(size: 14)).foregroundStyle(grey)
        Spacer()
      } else {
        VStack(spacing: 0) {
          ForEach(Array(entry.upcoming.prefix(3).enumerated()), id: \.offset) { i, s in
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                Text(s.where_).font(.system(size: 12)).foregroundStyle(grey).lineLimit(1)
              }
              Spacer(minLength: 6)
              VStack(alignment: .trailing, spacing: 1) {
                Text(s.time).font(.system(size: 14.5, weight: .bold)).monospacedDigit().foregroundStyle(ink)
                Text(i == 0 && entry.isUp ? "up now" : s.day).font(.system(size: 11.5)).foregroundStyle(i == 0 ? glow : grey)
              }
              if i == 0 { PipLight(size: 8) } else { Color.clear.frame(width: 8, height: 8) }
            }
            .padding(.vertical, 9)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
          }
        }
        .padding(.top, 10)
        Spacer(minLength: 8)
        if let s = entry.current, s.crosses {
          Text(entry.isUp ? "Up now: look \(s.rise_word)" : "Where to look for the \(s.short)")
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(grey)
          PassArc(rise: s.rise, peak: s.peak, set: s.set, pip: entry.isUp ? nil : 0).frame(height: 84).padding(.top, 4)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // Lock Screen: iOS tints these, so plain shapes and words.
  @ViewBuilder
  private var circular: some View {
    if let s = entry.current {
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 0) {
          Text(entry.isUp ? "up" : shortUntil(s.start, from: entry.date).split(separator: " ").first.map(String.init) ?? "")
            .font(.system(size: 16, weight: .heavy)).minimumScaleFactor(0.6)
          Text(s.short).font(.system(size: 9, weight: .semibold)).opacity(0.75).lineLimit(1)
        }
      }
    } else {
      ZStack { AccessoryWidgetBackground(); Circle().frame(width: 7, height: 7).opacity(0.6) }
    }
  }

  @ViewBuilder
  private var rectangular: some View {
    if let s = entry.current {
      VStack(alignment: .leading, spacing: 1) {
        Text(entry.isUp ? "It's up: \(s.short)" : s.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
        Text(s.crosses ? "\(s.time) · \(s.rise)" : "\(s.time) · \(s.rise_word)").font(.system(size: 12.5)).lineLimit(1)
        Text(s.crosses ? "climbs \(s.peak)" : s.peak).font(.system(size: 12.5)).opacity(0.75).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text("A quiet sky").font(.system(size: 14, weight: .semibold))
    }
  }

  @ViewBuilder
  private var inline: some View {
    if let s = entry.current {
      Text(entry.isUp ? "\(s.short) up now · \(s.rise_word)" : "\(s.short) \(s.time) · \(s.rise_word)")
    } else {
      Text("A quiet sky")
    }
  }
}

struct NextEventWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "LookUpWidget", provider: NextProvider()) { NextWidgetView(entry: $0) }
      .configurationDisplayName("Next up")
      .description("The next thing worth stepping outside for.")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

private extension View {
  /// iOS 17 requires containerBackground; iOS 16 uses a plain background.
  @ViewBuilder
  func widgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { night }
    } else {
      padding().background(night)
    }
  }

  /// Lock Screen widgets: the system draws their background.
  @ViewBuilder
  func accessoryBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { Color.clear }
    } else {
      self
    }
  }
}

// MARK: Live Activity: Lock Screen and Dynamic Island

typealias LookUpContext = ActivityViewContext<LookUpActivityAttributes>

/// Seconds to the rise, or to the set while it's up; never a reversed range.
@ViewBuilder
private func timer(_ context: LookUpContext) -> some View {
  let target = context.state.phase == "countdown" ? context.attributes.start : context.attributes.end
  if target > .now {
    Text(timerInterval: Date.now...target, countsDown: true)
  } else {
    Text(context.state.phase == "over" ? "Done" : "Now")
  }
}

private func isUp(_ context: LookUpContext) -> Bool { context.state.phase == "live" }
private func hasArc(_ context: LookUpContext) -> Bool { !context.attributes.rise.isEmpty && !context.attributes.set.isEmpty }

/// While it's up: how far along the pass, moved by the system on its own.
private func passBar(_ context: LookUpContext) -> some View {
  ProgressView(timerInterval: context.attributes.start...max(context.attributes.end, context.attributes.start.addingTimeInterval(1)),
               countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
    .tint(glow)
}

struct LookUpLockScreenView: View {
  let context: LookUpContext

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 12) {
        Group { if isUp(context) { PipFound(size: 12) } else { PipLight(size: 13) } }.frame(width: 30, height: 30)
        VStack(alignment: .leading, spacing: 1) {
          Text(isUp(context) ? "It's up" : context.attributes.title)
            .font(.system(size: 16, weight: isUp(context) ? .bold : .semibold)).foregroundStyle(isUp(context) ? glow : ink)
          Text(isUp(context) ? context.attributes.title : "Rises in the \(context.attributes.riseWord)")
            .font(.system(size: 12.5)).foregroundStyle(grey).lineLimit(1)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 0) {
          Text(isUp(context) ? "fades in" : "rises in").font(.system(size: 11)).foregroundStyle(grey)
          timer(context)
            .font(.system(size: 28, weight: .bold)).monospacedDigit()
            .foregroundStyle(isUp(context) ? ink : glow)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 110, alignment: .trailing)
        }
      }
      if hasArc(context) {
        PassArc(rise: context.attributes.rise, peak: context.attributes.peak, set: context.attributes.set,
                pip: isUp(context) ? nil : 0)
          .frame(height: 70)
        if isUp(context) { passBar(context) }
      }
      Text(context.state.direction).font(.system(size: 13.5)).foregroundStyle(ink.opacity(0.82)).lineLimit(2)
    }
    .padding(16)
  }
}

struct LookUpLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LookUpActivityAttributes.self) { context in
      LookUpLockScreenView(context: context)
        .activityBackgroundTint(Color(red: 0.086, green: 0.106, blue: 0.157).opacity(0.85))
        .activitySystemActionForegroundColor(glow)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Group { if isUp(context) { PipFound(size: 12) } else { PipLight(size: 13) } }
            .frame(width: 36, height: 36)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 1) {
            Text(isUp(context) ? "It's up" : context.attributes.title)
              .font(.system(size: 16, weight: .semibold)).foregroundStyle(isUp(context) ? glow : ink).lineLimit(1)
            Text(isUp(context) ? "Look \(context.attributes.riseWord), climbing \(context.attributes.peak)" : "Rises in the \(context.attributes.riseWord)")
              .font(.system(size: 12.5)).foregroundStyle(grey).lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        DynamicIslandExpandedRegion(.trailing) {
          timer(context)
            .font(.system(size: 24, weight: .bold)).monospacedDigit()
            .foregroundStyle(isUp(context) ? ink : glow)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 84, alignment: .trailing)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if hasArc(context) {
            VStack(spacing: 6) {
              PassArc(rise: context.attributes.rise, peak: context.attributes.peak, set: context.attributes.set,
                      pip: isUp(context) ? nil : 0)
                .frame(height: 58)
              if isUp(context) { passBar(context) }
            }
          } else {
            Text(context.state.direction).font(.system(size: 13)).foregroundStyle(grey)
          }
        }
      } compactLeading: {
        Group { if isUp(context) { PipFound(size: 7) } else { PipLight(size: 9) } }
          .padding(.leading, 2)
      } compactTrailing: {
        timer(context)
          .font(.system(size: 15, weight: .semibold)).monospacedDigit()
          .foregroundStyle(glow)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 52)
      } minimal: {
        Group { if isUp(context) { PipFound(size: 6) } else { PipLight(size: 9) } }
      }
      .keylineTint(glow)
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
